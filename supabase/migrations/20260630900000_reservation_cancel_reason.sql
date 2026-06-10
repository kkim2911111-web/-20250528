-- 취소 사유 기록 — cancel_reason · cancelled_at · 경로별 RPC · 정산 표시

alter table public.reservations
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_reason text;

comment on column public.reservations.cancelled_at is '예약 취소 시각';
comment on column public.reservations.cancel_reason is
  'customer | admin_force | blacklist_auto | payment_failed';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reservations_cancel_reason_check'
      and conrelid = 'public.reservations'::regclass
  ) then
    alter table public.reservations
      add constraint reservations_cancel_reason_check
      check (
        cancel_reason is null
        or cancel_reason in (
          'customer',
          'admin_force',
          'blacklist_auto',
          'payment_failed'
        )
      );
  end if;
end $$;

-- 기존 취소 건: rental_started_at 있으면 admin_force, 나머지 NULL
update public.reservations r
set cancel_reason = 'admin_force'
where r.status = 'cancelled'
  and r.cancel_reason is null
  and r.rental_started_at is not null;

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
    else '취소'
  end;
$$;

-- ── 1) 입주민 본인 취소 ───────────────────────────────────────
drop function if exists public.cancel_reservation_for_me(text, uuid);
drop function if exists public.cancel_reservation_for_me(text, uuid, text);

create or replace function public.cancel_reservation_for_me(
  p_reservation_id text,
  p_user_id uuid default auth.uid(),
  p_cancel_reason text default 'customer'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_row public.reservations%rowtype;
  v_start timestamptz;
  v_id text := nullif(trim(p_reservation_id), '');
  v_now timestamptz := now();
  v_reason text := 'customer';
  v_is_service boolean := coalesce(current_setting('role', true), '') = 'service_role';
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  if v_is_service then
    v_reason := coalesce(nullif(trim(p_cancel_reason), ''), 'customer');
    if v_reason not in ('customer', 'admin_force', 'blacklist_auto', 'payment_failed') then
      v_reason := 'customer';
    end if;
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id::text = v_id
    and r.user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status not in ('confirmed', 'pending') then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_row.start_at, v_row.start_time);
  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_reason = 'customer'
     and v_start <= v_now + interval '1 hour' then
    raise exception 'cancel_too_late';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    updated_at = v_now,
    cancelled_at = coalesce(cancelled_at, v_now),
    cancel_reason = v_reason
  where id::text = v_id
    and user_id = v_user;

  if v_row.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = v_now
    where order_id = v_row.order_id
      and user_id = v_user;
  end if;

  return jsonb_build_object(
    'reservationId', v_id,
    'cancelled', true,
    'cancelReason', v_reason,
    'orderId', v_row.order_id,
    'paymentKey', v_row.payment_key,
    'totalPrice', v_row.total_price
  );
end;
$$;

-- ── 2) 관리자 강제 결제취소 (단지) ─────────────────────────────
create or replace function public.force_payment_cancel_reservation_for_staff(
  p_reservation_id text,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_id text := nullif(trim(p_reservation_id), '');
  v_res public.reservations%rowtype;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is not null
    and p_user_id is distinct from auth.uid()
    and coalesce(current_setting('role', true), '') <> 'service_role' then
    raise exception 'forbidden';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status not in ('confirmed', 'in_use') then
    raise exception 'invalid_status';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    updated_at = v_now,
    cancelled_at = coalesce(cancelled_at, v_now),
    cancel_reason = 'admin_force'
  where id = v_res.id;

  if v_res.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = v_now
    where order_id = v_res.order_id;
  end if;

  update public.vehicles
  set is_available = true, updated_at = v_now
  where id = v_res.vehicle_id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'cancelled',
    'cancelReason', 'admin_force',
    'orderId', v_res.order_id,
    'paymentKey', v_res.payment_key,
    'totalPrice', v_res.total_price
  );
end;
$$;

-- ── 3) 관리자 강제 결제취소 (최고) ─────────────────────────────
create or replace function public.force_payment_cancel_reservation_for_super_admin(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := nullif(trim(p_reservation_id), '');
  v_res public.reservations%rowtype;
  v_now timestamptz := now();
begin
  perform public.assert_is_super_admin();

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_res
  from public.reservations r
  where r.id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status not in ('confirmed', 'in_use') then
    raise exception 'invalid_status';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    updated_at = v_now,
    cancelled_at = coalesce(cancelled_at, v_now),
    cancel_reason = 'admin_force'
  where id = v_res.id;

  if v_res.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = v_now
    where order_id = v_res.order_id;
  end if;

  update public.vehicles
  set is_available = true, updated_at = v_now
  where id = v_res.vehicle_id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'cancelled',
    'cancelReason', 'admin_force',
    'orderId', v_res.order_id,
    'paymentKey', v_res.payment_key,
    'totalPrice', v_res.total_price
  );
end;
$$;

create or replace function public.force_super_admin_cancel_reservation(p_reservation_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res public.reservations%rowtype;
  v_now timestamptz := now();
begin
  perform public.assert_is_super_admin();
  select *
  into v_res
  from public.reservations
  where id::text = trim(p_reservation_id)
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status in ('cancelled', 'completed') then
    raise exception 'invalid_status';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    updated_at = v_now,
    cancelled_at = coalesce(cancelled_at, v_now),
    cancel_reason = 'admin_force'
  where id = v_res.id;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_res.id::text,
    'cancelReason', 'admin_force'
  );
end;
$$;

-- ── 4) 정산 취소 목록 — cancel_reason 컬럼 기반 표시 ───────────
create or replace function public.build_settlement_sheet_json(
  p_complex_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_month_start date;
  v_total_paid bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_payment_items jsonb := '[]'::jsonb;
  v_cancel_items jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_requested_at timestamptz;
  v_settled_at timestamptz;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
  v_has_cancel_reason_col boolean := false;
  v_cancel_reason_expr text;
  v_cancelled_at_expr text;
  v_cancelled_order_expr text;
  v_cancelled_month_filter text;
  v_refund_amount_expr text;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_month_start := make_date(p_year, p_month, 1);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(p_year, p_month) as b;

  v_total_paid := public.sales_sum_gross(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations'
      and column_name = 'refund_amount'
  ) into v_has_refund_col;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations'
      and column_name = 'cancelled_at'
  ) into v_has_cancelled_at_col;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations'
      and column_name = 'cancel_reason'
  ) into v_has_cancel_reason_col;

  v_cancel_reason_expr := case
    when v_has_cancel_reason_col then
      'public.cancel_reason_display_label(r.cancel_reason)'
    else
      'case when r.rental_started_at is not null then ''관리자취소'' else ''취소'' end'
  end;

  v_cancelled_at_expr := case
    when v_has_cancelled_at_col then 'coalesce(r.cancelled_at, r.updated_at)'
    else 'r.updated_at'
  end;

  v_cancelled_order_expr := v_cancelled_at_expr || ' desc nulls last';
  v_cancelled_month_filter := case
    when v_has_cancelled_at_col then
      'date_trunc(''month'', coalesce(r.cancelled_at, r.updated_at) at time zone ''Asia/Seoul'')::date = $2'
    else
      'date_trunc(''month'', r.updated_at at time zone ''Asia/Seoul'')::date = $2'
  end;

  v_refund_amount_expr := case
    when v_has_refund_col then 'coalesce(r.refund_amount, 0)'
    else 'coalesce(r.total_price, 0)'
  end;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'reservation_number', s.reservation_number,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at,
        'is_no_show', s.is_no_show
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'order_id', po.order_id,
        'reservation_id', r.id::text,
        'reservation_number', r.reservation_number,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'paid_at', coalesce(po.updated_at, po.created_at),
        'payment_amount', coalesce(po.total_price, 0)
      )
      order by coalesce(po.updated_at, po.created_at) desc nulls last
    ),
    '[]'::jsonb
  )
  into v_payment_items
  from public.payment_orders po
  inner join public.reservations r on (
    (r.order_id is not null and po.order_id = r.order_id)
    or (po.reservation_id is not null and po.reservation_id = r.id::text)
    or po.order_id like 'ext_' || r.id::text || '_%'
  )
  inner join public.vehicles v on v.id = r.vehicle_id
  left join public.user_profiles up on up.user_id = r.user_id
  where v.complex_id = p_complex_id
    and po.status = 'paid'
    and coalesce(po.vehicle_id, '') <> 'signup_card'
    and date_trunc(
      'month',
      coalesce(po.updated_at, po.created_at) at time zone 'Asia/Seoul'
    )::date = v_month_start;

  execute format(
    $sql$
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'reservation_id', r.id::text,
            'reservation_number', r.reservation_number,
            'renter_name', coalesce(
              nullif(trim(up.full_name), ''),
              nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
              '이름 미등록'
            ),
            'cancelled_at', %s,
            'paid_amount', coalesce(r.total_price, 0),
            'refund_amount', %s,
            'cancel_reason', %s
          )
          order by %s
        ),
        '[]'::jsonb
      )
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      left join public.user_profiles up on up.user_id = r.user_id
      where v.complex_id = $1
        and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and %s
    $sql$,
    v_cancelled_at_expr,
    v_refund_amount_expr,
    v_cancel_reason_expr,
    v_cancelled_order_expr,
    v_cancelled_month_filter
  )
  into v_cancel_items
  using p_complex_id, v_month_start;

  v_counts := public.settlement_sheet_counts(
    p_complex_id, v_period_start, v_period_end, p_year, p_month
  );

  select
    cs.settled_at is not null,
    cs.requested_at is not null and cs.settled_at is null,
    cs.requested_at,
    cs.settled_at
  into v_is_settled, v_is_requested, v_requested_at, v_settled_at
  from public.complex_settlements cs
  where cs.complex_id = p_complex_id
    and cs.period_year = p_year
    and cs.period_month = p_month;

  return jsonb_build_object(
    'complex_id', p_complex_id,
    'year', p_year,
    'month', p_month,
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', 0,
    'net_revenue', coalesce(v_total_paid, 0),
    'items', coalesce(v_items, '[]'::jsonb),
    'payment_items', coalesce(v_payment_items, '[]'::jsonb),
    'cancel_items', coalesce(v_cancel_items, '[]'::jsonb),
    'payment_count', coalesce((v_counts->>'payment_count')::bigint, 0),
    'cancel_count', coalesce((v_counts->>'cancel_count')::bigint, 0),
    'rental_count', coalesce((v_counts->>'rental_count')::bigint, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'requested_at', v_requested_at,
    'settled_at', v_settled_at
  );
end;
$$;

revoke all on function public.cancel_reservation_for_me(text, uuid, text) from public;
grant execute on function public.cancel_reservation_for_me(text, uuid, text)
  to authenticated, service_role;

revoke all on function public.cancel_reason_display_label(text) from public;
grant execute on function public.cancel_reason_display_label(text) to authenticated, service_role;

comment on function public.build_settlement_sheet_json(uuid, integer, integer) is
  '정산 상세 — cancel_reason 코드→고객취소/관리자취소/블랙리스트/결제실패, NULL→취소';
