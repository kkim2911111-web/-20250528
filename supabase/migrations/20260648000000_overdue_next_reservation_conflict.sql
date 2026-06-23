-- 반납 지연(in_use + is_overdue) 시 다음 예약자 충돌 3단계 경고·자동취소

-- ── 1) 타임스탬프 컬럼 (지연 중인 A 예약에 기록) ─────────────────
alter table public.reservations
  add column if not exists overdue_next_reservation_warned_at timestamptz,
  add column if not exists overdue_next_reservation_second_warned_at timestamptz,
  add column if not exists overdue_next_reservation_cancelled_at timestamptz;

comment on column public.reservations.overdue_next_reservation_warned_at is
  '반납 지연 + 다음 예약 충돌 1차 경고 발송 시각';
comment on column public.reservations.overdue_next_reservation_second_warned_at is
  '반납 지연 + 다음 예약 충돌 2차 경고 발송 시각';
comment on column public.reservations.overdue_next_reservation_cancelled_at is
  '반납 지연으로 다음 예약(B) 자동취소 처리 완료 시각';

-- ── 2) cancel_reason CHECK 확장 ─────────────────────────────────
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
      'vehicle_not_returned',
      'overdue_conflict'
    )
  );

comment on column public.reservations.cancel_reason is
  'customer | admin_force | blacklist_auto | payment_failed | vehicle_not_returned | overdue_conflict';

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
    when 'overdue_conflict' then '반납지연취소'
    else '취소'
  end;
$$;

-- ── 3) 다음 충돌 예약(B) 조회 ────────────────────────────────────
create or replace function public.find_next_overdue_conflict_reservation(
  p_overdue_reservation_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_overdue public.reservations%rowtype;
  v_end timestamptz;
  v_next public.reservations%rowtype;
begin
  select *
  into v_overdue
  from public.reservations r
  where r.id::text = nullif(trim(p_overdue_reservation_id), '');

  if not found then
    return null;
  end if;

  v_end := coalesce(v_overdue.end_at, v_overdue.end_time);
  if v_end is null or v_overdue.vehicle_id is null then
    return null;
  end if;

  select *
  into v_next
  from public.reservations n
  where n.vehicle_id = v_overdue.vehicle_id
    and n.status in ('confirmed', 'pending')
    and coalesce(n.start_at, n.start_time) > v_end
    and coalesce(n.start_at, n.start_time) <= v_end + interval '30 minutes'
  order by coalesce(n.start_at, n.start_time) asc
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'overdueReservationId', v_overdue.id::text,
    'overdueUserId', v_overdue.user_id,
    'overdueEndAt', v_end,
    'nextReservationId', v_next.id::text,
    'nextUserId', v_next.user_id,
    'nextStartAt', coalesce(v_next.start_at, v_next.start_time),
    'vehicleId', v_overdue.vehicle_id::text
  );
end;
$$;

revoke all on function public.find_next_overdue_conflict_reservation(text) from public;
grant execute on function public.find_next_overdue_conflict_reservation(text)
  to service_role;

comment on function public.find_next_overdue_conflict_reservation(text) is
  '반납 지연 예약(A)에 대해 30분 이내 다음 예약(B) 존재 시 컨텍스트 반환';

-- ── 4) 1·2차 경고 타임스탬프 (중복 방지) ─────────────────────────
create or replace function public.mark_overdue_next_reservation_warned_for_service(
  p_overdue_reservation_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  update public.reservations r
  set
    overdue_next_reservation_warned_at = v_now,
    updated_at = v_now
  where r.id::text = nullif(trim(p_overdue_reservation_id), '')
    and r.status = 'in_use'
    and coalesce(r.is_overdue, false) = true
    and r.returned_at is null
    and r.overdue_next_reservation_warned_at is null
    and public.find_next_overdue_conflict_reservation(p_overdue_reservation_id) is not null;

  return found;
end;
$$;

revoke all on function public.mark_overdue_next_reservation_warned_for_service(text) from public;
grant execute on function public.mark_overdue_next_reservation_warned_for_service(text)
  to service_role;

create or replace function public.mark_overdue_next_reservation_second_warned_for_service(
  p_overdue_reservation_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  update public.reservations r
  set
    overdue_next_reservation_second_warned_at = v_now,
    updated_at = v_now
  where r.id::text = nullif(trim(p_overdue_reservation_id), '')
    and r.status = 'in_use'
    and coalesce(r.is_overdue, false) = true
    and r.returned_at is null
    and r.overdue_next_reservation_warned_at is not null
    and r.overdue_next_reservation_warned_at + interval '15 minutes' < v_now
    and r.overdue_next_reservation_second_warned_at is null
    and public.find_next_overdue_conflict_reservation(p_overdue_reservation_id) is not null;

  return found;
end;
$$;

revoke all on function public.mark_overdue_next_reservation_second_warned_for_service(text) from public;
grant execute on function public.mark_overdue_next_reservation_second_warned_for_service(text)
  to service_role;

-- ── 5) 3단계 — B 예약 취소 (DB만, 환불은 Edge) ───────────────────
create or replace function public.cancel_overdue_conflict_reservation_for_service(
  p_victim_reservation_id text,
  p_blocking_overdue_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_blocking public.reservations%rowtype;
  v_victim public.reservations%rowtype;
  v_end timestamptz;
  v_start timestamptz;
  v_ctx jsonb;
  v_paid bigint;
begin
  select *
  into v_blocking
  from public.reservations r
  where r.id::text = nullif(trim(p_blocking_overdue_reservation_id), '')
  for update;

  if not found then
    raise exception 'blocking_reservation_not_found';
  end if;

  if v_blocking.status <> 'in_use'
    or coalesce(v_blocking.is_overdue, false) = false
    or v_blocking.returned_at is not null then
    raise exception 'blocking_not_overdue_in_use';
  end if;

  if v_blocking.overdue_next_reservation_cancelled_at is not null then
    return jsonb_build_object(
      'ok', true,
      'alreadyCancelled', true,
      'victimReservationId', p_victim_reservation_id
    );
  end if;

  v_ctx := public.find_next_overdue_conflict_reservation(p_blocking_overdue_reservation_id);
  if v_ctx is null then
    raise exception 'no_conflict_reservation';
  end if;

  if (v_ctx->>'nextReservationId') <> nullif(trim(p_victim_reservation_id), '') then
    raise exception 'victim_mismatch';
  end if;

  v_start := (v_ctx->>'nextStartAt')::timestamptz;
  if v_start is null or v_start > v_now then
    raise exception 'next_start_not_reached';
  end if;

  select *
  into v_victim
  from public.reservations r
  where r.id::text = nullif(trim(p_victim_reservation_id), '')
  for update;

  if not found then
    raise exception 'victim_reservation_not_found';
  end if;

  if v_victim.status not in ('confirmed', 'pending') then
    raise exception 'invalid_victim_status';
  end if;

  v_end := coalesce(v_blocking.end_at, v_blocking.end_time);
  v_start := coalesce(v_victim.start_at, v_victim.start_time);

  if v_victim.vehicle_id is distinct from v_blocking.vehicle_id
    or v_start is null
    or v_end is null
    or v_start <= v_end
    or v_start > v_end + interval '30 minutes' then
    raise exception 'conflict_window_invalid';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    cancel_reason = 'overdue_conflict',
    cancelled_at = v_now,
    is_no_show = false,
    refund_amount = 0,
    updated_at = v_now
  where id = v_victim.id;

  update public.reservations
  set
    overdue_next_reservation_cancelled_at = v_now,
    updated_at = v_now
  where id = v_blocking.id;

  v_paid := public.reservation_card_paid_amount(p_victim_reservation_id);

  return jsonb_build_object(
    'ok', true,
    'victimReservationId', v_victim.id::text,
    'victimUserId', v_victim.user_id,
    'blockingReservationId', v_blocking.id::text,
    'paymentKey', v_victim.payment_key,
    'orderId', v_victim.order_id,
    'paidAmount', v_paid,
    'vehicleId', v_victim.vehicle_id::text
  );
end;
$$;

revoke all on function public.cancel_overdue_conflict_reservation_for_service(text, text) from public;
grant execute on function public.cancel_overdue_conflict_reservation_for_service(text, text)
  to service_role;

-- ── 6) 환불 DB 확정 (Edge → service_role) ───────────────────────
create or replace function public.finalize_overdue_conflict_refund_for_service(
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
    or coalesce(v_row.cancel_reason, '') <> 'overdue_conflict' then
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

revoke all on function public.finalize_overdue_conflict_refund_for_service(text, integer) from public;
grant execute on function public.finalize_overdue_conflict_refund_for_service(text, integer)
  to service_role;
