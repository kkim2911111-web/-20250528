-- 노쇼 vs 차량미회수 분리 — 앞 예약 in_use 미반납 시 전액환불(vehicle_not_returned)

-- ── 1) cancel_reason CHECK 확장 ─────────────────────────────────
alter table public.reservations
  drop constraint if exists reservations_cancel_reason_check;

alter table public.reservations
  add constraint reservations_cancel_reason_check
  check (
    cancel_reason is null
    or cancel_reason in (
      'customer',
      'admin_force',
      'blacklist_auto',
      'payment_failed',
      'vehicle_not_returned'
    )
  );

comment on column public.reservations.cancel_reason is
  'customer | admin_force | blacklist_auto | payment_failed | vehicle_not_returned';

create or replace function public.cancel_reason_display_label(p_reason text)
returns text
language sql
immutable
as $$
  select case nullif(trim(p_reason), '')
    when 'customer' then '고객취소'
    when 'admin_force' then '관리자취소'
    when 'blacklist_auto' then '블랙리스트'
    when 'payment_failed' then '결제실패'
    when 'vehicle_not_returned' then '차량미회수'
    else '취소'
  end;
$$;

-- ── 2) 앞 예약 미반납 차단 여부 ───────────────────────────────────
create or replace function public.has_blocking_in_use_reservation(
  p_vehicle_id bigint,
  p_before timestamptz
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.reservations b
    where b.vehicle_id = p_vehicle_id
      and b.status = 'in_use'
      and b.returned_at is null
      and coalesce(b.start_at, b.start_time) < p_before
  );
$$;

comment on function public.has_blocking_in_use_reservation(bigint, timestamptz) is
  '동일 차량에 p_before 이전 시작한 in_use 미반납 예약 존재 여부';

revoke all on function public.has_blocking_in_use_reservation(bigint, timestamptz) from public;
grant execute on function public.has_blocking_in_use_reservation(bigint, timestamptz)
  to authenticated, service_role;

-- ── 3) 차량미회수 전액환불 DB 확정 (Edge → service_role) ────────
create or replace function public.finalize_vehicle_not_returned_refund_for_service(
  p_reservation_id text,
  p_refund_amount integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.reservations%rowtype;
  v_paid bigint;
  v_refund integer;
begin
  select *
  into v_row
  from public.reservations r
  where r.id::text = nullif(trim(p_reservation_id), '')
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status <> 'cancelled'
    or coalesce(v_row.cancel_reason, '') <> 'vehicle_not_returned' then
    raise exception 'invalid_status';
  end if;

  if coalesce(v_row.refund_amount, 0) > 0 then
    return jsonb_build_object(
      'ok', true,
      'alreadyRefunded', true,
      'refundAmount', v_row.refund_amount,
      'userId', v_row.user_id
    );
  end if;

  v_paid := public.reservation_card_paid_amount(p_reservation_id);
  v_refund := coalesce(p_refund_amount, 0);

  if v_refund::bigint <> v_paid then
    raise exception 'refund_amount_mismatch';
  end if;

  update public.reservations
  set
    refund_amount = v_refund,
    updated_at = now()
  where id = v_row.id;

  if v_row.order_id is not null and v_paid > 0 then
    update public.payment_orders
    set
      status = 'cancelled',
      updated_at = now()
    where order_id = v_row.order_id
      and user_id = v_row.user_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'refundAmount', v_refund,
    'paidAmount', v_paid,
    'userId', v_row.user_id,
    'orderId', v_row.order_id,
    'restoreBenefits', v_paid = 0 or v_refund >= v_paid
  );
end;
$$;

revoke all on function public.finalize_vehicle_not_returned_refund_for_service(text, integer)
  from public;
grant execute on function public.finalize_vehicle_not_returned_refund_for_service(text, integer)
  to service_role;

-- ── 4) 앱 경로 — Edge Function 비동기 호출 ───────────────────────
create or replace function public.try_invoke_vehicle_not_returned_refund(
  p_reservation_id text
)
returns void
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
begin
  perform public.invoke_supabase_edge_function(
    'reservation-vehicle-not-returned-refund',
    jsonb_build_object('reservationId', p_reservation_id)
  );
exception
  when others then
    raise notice 'vehicle_not_returned refund invoke failed: %', sqlerrm;
end;
$$;

revoke all on function public.try_invoke_vehicle_not_returned_refund(text) from public;
grant execute on function public.try_invoke_vehicle_not_returned_refund(text) to service_role;

-- ── 5) cron RPC — 노쇼 / 차량미회수 분리 ────────────────────────
create or replace function public.auto_return_expired_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_no_show_count integer := 0;
  v_vehicle_not_returned_count integer := 0;
  v_overdue_count integer := 0;
  v_no_shows jsonb := '[]'::jsonb;
  v_vehicle_not_returneds jsonb := '[]'::jsonb;
  v_overdues jsonb := '[]'::jsonb;
begin
  with no_show_updated as (
    update public.reservations r
    set
      status = 'completed',
      is_no_show = true,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
      and not public.has_blocking_in_use_reservation(
        r.vehicle_id,
        coalesce(r.start_at, r.start_time, v_now)
      )
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_no_shows, v_no_show_count
  from no_show_updated;

  with vehicle_not_returned_updated as (
    update public.reservations r
    set
      status = 'cancelled',
      cancel_reason = 'vehicle_not_returned',
      cancelled_at = v_now,
      is_no_show = false,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
      and public.has_blocking_in_use_reservation(
        r.vehicle_id,
        coalesce(r.start_at, r.start_time, v_now)
      )
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_vehicle_not_returneds, v_vehicle_not_returned_count
  from vehicle_not_returned_updated;

  with overdue_updated as (
    update public.reservations r
    set
      is_overdue = true,
      updated_at = v_now
    where r.status = 'in_use'
      and coalesce(r.is_overdue, false) = false
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_overdues, v_overdue_count
  from overdue_updated;

  return jsonb_build_object(
    'overdueCount', v_overdue_count,
    'noShowCount', v_no_show_count,
    'vehicleNotReturnedCount', v_vehicle_not_returned_count,
    'overdues', v_overdues,
    'noShows', v_no_shows,
    'vehicleNotReturned', v_vehicle_not_returneds,
    'processedAt', v_now
  );
end;
$$;

-- ── 6) 앱 새로고침 RPC — 동일 분기 + Edge invoke ─────────────────
create or replace function public.auto_complete_expired_reservations_for_me()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_no_show_count integer := 0;
  v_vehicle_not_returned_count integer := 0;
  v_overdue_count integer := 0;
  v_no_shows jsonb := '[]'::jsonb;
  v_vehicle_not_returneds jsonb := '[]'::jsonb;
  v_overdues jsonb := '[]'::jsonb;
  v_now timestamptz := now();
  v_rec record;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  with no_show_updated as (
    update public.reservations r
    set
      status = 'completed',
      is_no_show = true,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.user_id = v_user
      and r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
      and not public.has_blocking_in_use_reservation(
        r.vehicle_id,
        coalesce(r.start_at, r.start_time, v_now)
      )
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_no_shows, v_no_show_count
  from no_show_updated;

  with vehicle_not_returned_updated as (
    update public.reservations r
    set
      status = 'cancelled',
      cancel_reason = 'vehicle_not_returned',
      cancelled_at = v_now,
      is_no_show = false,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.user_id = v_user
      and r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
      and public.has_blocking_in_use_reservation(
        r.vehicle_id,
        coalesce(r.start_at, r.start_time, v_now)
      )
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_vehicle_not_returneds, v_vehicle_not_returned_count
  from vehicle_not_returned_updated;

  for v_rec in
    select elem->>'reservationId' as reservation_id
    from jsonb_array_elements(coalesce(v_vehicle_not_returneds, '[]'::jsonb)) elem
  loop
    if v_rec.reservation_id is not null then
      perform public.try_invoke_vehicle_not_returned_refund(v_rec.reservation_id);
    end if;
  end loop;

  with overdue_updated as (
    update public.reservations r
    set
      is_overdue = true,
      updated_at = v_now
    where r.user_id = v_user
      and r.status = 'in_use'
      and coalesce(r.is_overdue, false) = false
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_overdues, v_overdue_count
  from overdue_updated;

  return jsonb_build_object(
    'overdueCount', v_overdue_count,
    'noShowCount', v_no_show_count,
    'vehicleNotReturnedCount', v_vehicle_not_returned_count,
    'overdues', v_overdues,
    'noShows', v_no_shows,
    'vehicleNotReturned', v_vehicle_not_returneds,
    'processedAt', v_now
  );
end;
$$;
