-- 취소·환불 정책 엔진 — rental_type별 환불율, 부분환불, 0% 취소 매출 반영

alter table public.reservations
  add column if not exists refund_amount integer not null default 0;

comment on column public.reservations.refund_amount is
  '고객 취소 시 카드 환불액(원). 0% 구간은 0, 부분환불은 결제액×환불율';

-- ── 환불율 (0 / 0.5 / 1) — start_at 기준 잔여 시간, KST 무관 epoch 비교 ──
create or replace function public.calc_cancel_refund_rate(
  p_rental_type text,
  p_start_at timestamptz,
  p_now timestamptz default now()
)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_type text := lower(coalesce(nullif(trim(p_rental_type), ''), 'hourly'));
  v_hours double precision;
begin
  if p_start_at is null then
    return 0;
  end if;

  v_hours := extract(epoch from (p_start_at - p_now)) / 3600.0;

  if v_type in ('daily', 'monthly') then
    if v_hours >= 72 then
      return 1;
    elsif v_hours >= 24 then
      return 0.5;
    else
      return 0;
    end if;
  end if;

  -- hourly(카셰어링) 및 기타
  if v_hours >= 1 then
    return 1;
  end if;
  return 0;
end;
$$;

comment on function public.calc_cancel_refund_rate(text, timestamptz, timestamptz) is
  'hourly: 출고 1시간 전까지 100% / daily·monthly: 72h 100%, 24~72h 50%, 24h 이내 0%';

-- ── 예약 카드 결제액 (환불 산정 기준) ─────────────────────────────
create or replace function public.reservation_card_paid_amount(p_reservation_id text)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select po.total_price::bigint
      from public.payment_orders po
      inner join public.reservations r on (
        (r.order_id is not null and po.order_id = r.order_id)
        or (po.reservation_id is not null and po.reservation_id = r.id::text)
      )
      where r.id::text = nullif(trim(p_reservation_id), '')
        and po.status in ('paid', 'confirmed')
      order by coalesce(po.updated_at, po.created_at) desc
      limit 1
    ),
    (
      select coalesce(r.total_price, 0)::bigint
      from public.reservations r
      where r.id::text = nullif(trim(p_reservation_id), '')
    ),
    0::bigint
  );
$$;

create or replace function public.calc_cancel_refund_amount(
  p_rental_type text,
  p_start_at timestamptz,
  p_paid_amount bigint,
  p_now timestamptz default now()
)
returns bigint
language sql
stable
set search_path = public
as $$
  select greatest(
    0::bigint,
    floor(
      greatest(coalesce(p_paid_amount, 0), 0)::numeric
      * public.calc_cancel_refund_rate(p_rental_type, p_start_at, p_now)
    )::bigint
  );
$$;

-- ── 취소 환불 견적 (클라이언트 미리보기 · Edge 사전 조회) ───────────
create or replace function public.preview_cancel_refund_for_me(
  p_reservation_id text,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_row public.reservations%rowtype;
  v_start timestamptz;
  v_paid bigint;
  v_rate numeric;
  v_refund bigint;
  v_type text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id::text = nullif(trim(p_reservation_id), '')
    and r.user_id = v_user;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status not in ('confirmed', 'pending') then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_row.start_at, v_row.start_time);
  v_type := lower(coalesce(nullif(trim(v_row.rental_type), ''), 'hourly'));
  v_paid := public.reservation_card_paid_amount(v_row.id::text);
  v_rate := public.calc_cancel_refund_rate(v_type, v_start, now());
  v_refund := public.calc_cancel_refund_amount(v_type, v_start, v_paid, now());

  return jsonb_build_object(
    'reservationId', v_row.id::text,
    'rentalType', v_type,
    'paidAmount', v_paid,
    'refundRate', v_rate,
    'refundAmount', v_refund,
    'refundPercent', (v_rate * 100)::integer,
    'restoreBenefits', (v_rate >= 1 or v_paid = 0)
  );
end;
$$;

-- ── 포인트 복구 (취소 시 — 전액 환불 또는 카드 결제 0원만) ────────
drop function if exists public.restore_used_points(uuid, text);

create or replace function public.restore_used_points(
  p_user_id uuid,
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_rid text := nullif(trim(p_reservation_id), '');
  v_pts integer := 0;
  v_is_service boolean := coalesce(current_setting('role', true), '') = 'service_role';
begin
  if v_rid is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_reservation_id');
  end if;

  if not v_is_service then
    if v_user is null then
      raise exception 'not_authenticated';
    end if;
    if p_user_id is distinct from v_user then
      raise exception 'forbidden';
    end if;
  end if;

  if exists (
    select 1
    from public.point_history ph
    where ph.user_id = p_user_id
      and ph.reservation_id = v_rid
      and ph.type = 'restore'
  ) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_restored');
  end if;

  select coalesce(sum(abs(ph.amount)), 0)::integer
  into v_pts
  from public.point_history ph
  where ph.user_id = p_user_id
    and ph.reservation_id = v_rid
    and ph.type = 'use'
    and ph.amount < 0;

  if v_pts <= 0 then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_points_used');
  end if;

  update public.user_profiles
  set points = coalesce(points, 0) + v_pts
  where user_id = p_user_id;

  insert into public.point_history (user_id, amount, type, description, reservation_id)
  values (
    p_user_id,
    v_pts,
    'restore',
    '예약 취소 포인트 복구',
    v_rid
  );

  return jsonb_build_object('ok', true, 'restored', v_pts);
end;
$$;

create or replace function public.restore_booking_benefits_after_cancel(
  p_user_id uuid,
  p_reservation_id text,
  p_restore_benefits boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coupon jsonb;
  v_points jsonb;
begin
  if not coalesce(p_restore_benefits, false) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'partial_or_no_refund');
  end if;

  v_coupon := public.restore_user_coupon(p_user_id, p_reservation_id);
  v_points := public.restore_used_points(p_user_id, p_reservation_id);

  return jsonb_build_object(
    'ok', true,
    'coupon', v_coupon,
    'points', v_points
  );
end;
$$;

-- ── 입주민 본인 취소 — 시각 제한 제거, 서버 환불액 재계산 ───────────
drop function if exists public.cancel_reservation_for_me(text, uuid);
drop function if exists public.cancel_reservation_for_me(text, uuid, text);

create or replace function public.cancel_reservation_for_me(
  p_reservation_id text,
  p_user_id uuid default auth.uid(),
  p_cancel_reason text default 'customer',
  p_refund_amount integer default null
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
  v_type text;
  v_paid bigint;
  v_rate numeric;
  v_refund bigint;
  v_restore boolean;
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

  v_type := lower(coalesce(nullif(trim(v_row.rental_type), ''), 'hourly'));
  v_paid := public.reservation_card_paid_amount(v_id);
  v_rate := public.calc_cancel_refund_rate(v_type, v_start, v_now);
  v_refund := public.calc_cancel_refund_amount(v_type, v_start, v_paid, v_now);

  if p_refund_amount is not null and v_is_service then
    if p_refund_amount::bigint <> v_refund then
      raise exception 'refund_amount_mismatch';
    end if;
  end if;

  v_restore := (v_rate >= 1 or v_paid = 0);

  update public.reservations
  set
    status = 'cancelled',
    updated_at = v_now,
    cancelled_at = coalesce(cancelled_at, v_now),
    cancel_reason = v_reason,
    refund_amount = v_refund
  where id::text = v_id
    and user_id = v_user;

  if v_row.order_id is not null then
    update public.payment_orders
    set
      status = case when v_refund >= v_paid and v_paid > 0 then 'cancelled' else status end,
      updated_at = v_now
    where order_id = v_row.order_id
      and user_id = v_user;
  end if;

  return jsonb_build_object(
    'reservationId', v_id,
    'cancelled', true,
    'cancelReason', v_reason,
    'orderId', v_row.order_id,
    'paymentKey', v_row.payment_key,
    'paidAmount', v_paid,
    'refundRate', v_rate,
    'refundAmount', v_refund,
    'refundPercent', (v_rate * 100)::integer,
    'restoreBenefits', v_restore,
    'totalPrice', v_row.total_price
  );
end;
$$;

-- ── sales_completed_reservations_v — completed + 고객취소 잔여 매출 ──
drop view if exists public.sales_extension_lines_v;
drop view if exists public.sales_completed_reservations_v;

create view public.sales_completed_reservations_v as
select
  r.id,
  r.id::text as reservation_id_text,
  r.user_id,
  r.vehicle_id,
  v.complex_id,
  coalesce(v.model_name, '차량') as vehicle_name,
  coalesce(r.total_price, 0)::bigint as gross_amount,
  r.status,
  r.returned_at,
  r.actual_end_at,
  case
    when coalesce(r.is_no_show, false) then
      coalesce(
        public.sales_return_completed_at(
          r.returned_at,
          r.actual_end_at,
          coalesce(r.end_at, r.end_time)
        ),
        r.updated_at
      )
    else
      public.sales_return_completed_at(
        r.returned_at,
        r.actual_end_at,
        coalesce(r.end_at, r.end_time)
      )
  end as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  coalesce(r.is_no_show, false) as is_no_show,
  r.reservation_number
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'completed'
  and (
    coalesce(r.is_no_show, false) = true
    or public.sales_return_completed_at(
      r.returned_at,
      r.actual_end_at,
      coalesce(r.end_at, r.end_time)
    ) is not null
  )

union all

select
  r.id,
  r.id::text as reservation_id_text,
  r.user_id,
  r.vehicle_id,
  v.complex_id,
  coalesce(v.model_name, '차량') as vehicle_name,
  greatest(
    public.reservation_card_paid_amount(r.id::text)
      - coalesce(r.refund_amount, 0)::bigint,
    0::bigint
  ) as gross_amount,
  r.status,
  r.returned_at,
  r.actual_end_at,
  coalesce(r.cancelled_at, r.updated_at) as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  false as is_no_show,
  r.reservation_number
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'cancelled'
  and r.cancel_reason = 'customer'
  and coalesce(r.is_no_show, false) = false
  and (
    r.payment_status in ('paid', 'confirmed')
    or r.payment_key is not null
    or exists (
      select 1
      from public.payment_orders po
      where po.status in ('paid', 'confirmed')
        and (
          (r.order_id is not null and po.order_id = r.order_id)
          or (po.reservation_id is not null and po.reservation_id = r.id::text)
        )
    )
  )
  and greatest(
    public.reservation_card_paid_amount(r.id::text)
      - coalesce(r.refund_amount, 0)::bigint,
    0::bigint
  ) > 0;

comment on view public.sales_completed_reservations_v is
  '매출 집계 — completed(반납완료·노쇼) + 고객취소 잔여매출(결제액-환불액, cancelled_at 기준)';

create view public.sales_extension_lines_v as
select
  scr.reservation_id_text,
  scr.complex_id,
  scr.return_completed_at,
  coalesce(re.added_price, 0)::bigint as extension_amount
from public.reservation_extensions re
inner join public.sales_completed_reservations_v scr
  on scr.reservation_id_text = re.reservation_id::text;

-- 정산 취소 목록 refund_amount 컬럼 고정 사용
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
  v_cancel_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_payment_items jsonb := '[]'::jsonb;
  v_cancel_items jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_requested_at timestamptz;
  v_settled_at timestamptz;
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
        'cancelled_at', coalesce(r.cancelled_at, r.updated_at),
        'paid_amount', public.reservation_card_paid_amount(r.id::text),
        'refund_amount', coalesce(r.refund_amount, 0),
        'cancel_reason', public.cancel_reason_display_label(r.cancel_reason)
      )
      order by coalesce(r.cancelled_at, r.updated_at) desc nulls last
    ),
    '[]'::jsonb
  )
  into v_cancel_items
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  left join public.user_profiles up on up.user_id = r.user_id
  where v.complex_id = p_complex_id
    and r.status = 'cancelled'
    and coalesce(r.is_no_show, false) = false
    and date_trunc(
      'month',
      coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
    )::date = v_month_start;

  select coalesce(sum(coalesce(r.refund_amount, 0)), 0)::bigint
  into v_cancel_refund
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'cancelled'
    and coalesce(r.is_no_show, false) = false
    and date_trunc(
      'month',
      coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
    )::date = v_month_start;

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
    'cancel_refund', coalesce(v_cancel_refund, 0),
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

revoke all on function public.calc_cancel_refund_rate(text, timestamptz, timestamptz) from public;
grant execute on function public.calc_cancel_refund_rate(text, timestamptz, timestamptz)
  to authenticated, service_role;

revoke all on function public.reservation_card_paid_amount(text) from public;
grant execute on function public.reservation_card_paid_amount(text)
  to authenticated, service_role;

revoke all on function public.calc_cancel_refund_amount(text, timestamptz, bigint, timestamptz) from public;
grant execute on function public.calc_cancel_refund_amount(text, timestamptz, bigint, timestamptz)
  to authenticated, service_role;

revoke all on function public.preview_cancel_refund_for_me(text, uuid) from public;
grant execute on function public.preview_cancel_refund_for_me(text, uuid) to authenticated;

revoke all on function public.restore_used_points(uuid, text) from public;
grant execute on function public.restore_used_points(uuid, text) to authenticated, service_role;

revoke all on function public.restore_booking_benefits_after_cancel(uuid, text, boolean) from public;
grant execute on function public.restore_booking_benefits_after_cancel(uuid, text, boolean)
  to authenticated, service_role;

revoke all on function public.cancel_reservation_for_me(text, uuid, text, integer) from public;
grant execute on function public.cancel_reservation_for_me(text, uuid, text, integer)
  to authenticated, service_role;

comment on function public.build_settlement_sheet_json(uuid, integer, integer) is
  '정산 상세 — refund_amount 컬럼 기반 취소 환불, 매출은 sales_completed_reservations_v(잔여매출 포함)';
