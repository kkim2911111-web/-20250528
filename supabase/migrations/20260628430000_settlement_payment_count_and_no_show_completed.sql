-- 1) 결제건수 — 예약 1건 기준 distinct (연장 ext_{reservationId}_* 묶음)
-- 2) 노쇼(is_no_show) cancelled → completed 데이터 정정 + RPC 수정
-- 3) 취소건수/환불 — is_no_show 제외

-- ── 노쇼 데이터 정정 (기존 cancelled → completed) ─────────────────
update public.reservations r
set
  status = 'completed',
  actual_end_at = coalesce(
    r.actual_end_at,
    r.returned_at,
    coalesce(r.end_at, r.end_time),
    r.updated_at
  ),
  updated_at = now()
where coalesce(r.is_no_show, false) = true
  and r.status = 'cancelled';

-- ── 노쇼 처리 RPC — 앞으로 completed 로 저장, 결제 취소 안 함 ────
create or replace function public.cancel_reservation_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_res public.reservations%rowtype;
  v_start timestamptz;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
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

  if v_res.status <> 'confirmed' then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_res.start_at, v_res.start_time);
  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_start > v_now then
    raise exception 'not_no_show_suspect';
  end if;

  update public.reservations
  set
    status = 'completed',
    is_no_show = true,
    actual_end_at = coalesce(
      v_res.actual_end_at,
      coalesce(v_res.end_at, v_res.end_time),
      v_now
    ),
    updated_at = v_now
  where id = v_res.id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'completed',
    'isNoShow', true
  );
end;
$$;

-- ── 결제건수 집계 — 예약 distinct, 연장 order_id(ext_{id}_*) 묶음 ─
create or replace function public.settlement_sheet_counts(
  p_complex_id uuid,
  p_period_start timestamptz,
  p_period_end timestamptz,
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
  v_payment_count bigint := 0;
  v_cancel_count bigint := 0;
  v_rental_count bigint := 0;
  v_month_start date;
  v_has_cancelled_at_col boolean := false;
begin
  v_month_start := make_date(p_year, p_month, 1);

  v_rental_count := public.sales_count_reservations(
    p_complex_id, p_period_start, p_period_end
  );

  -- 결제건수: 반납완료 기간 내 completed 예약 중 paid 결제가 1건이라도 있는 예약 수
  -- 연장 결제 order_id = ext_{reservationId}_{suffix} → 동일 예약 1건으로 집계
  select count(distinct s.reservation_id_text)::bigint
  into v_payment_count
  from public.sales_completed_reservations_v s
  join public.reservations r on r.id::text = s.reservation_id_text
  where s.complex_id = p_complex_id
    and s.return_completed_at >= p_period_start
    and s.return_completed_at < p_period_end
    and exists (
      select 1
      from public.payment_orders po
      where po.status = 'paid'
        and (
          (r.order_id is not null and po.order_id = r.order_id)
          or po.order_id like 'ext_' || s.reservation_id_text || '_%'
          or exists (
            select 1
            from public.reservation_extensions re
            where re.reservation_id::text = s.reservation_id_text
              and re.payment_order_id is not null
              and po.order_id = re.payment_order_id
          )
        )
    );

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_cancelled_at_col then
    select count(*)::bigint
    into v_cancel_count
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status = 'cancelled'
      and coalesce(r.is_no_show, false) = false
      and date_trunc(
        'month',
        coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
      )::date = v_month_start;
  else
    select count(*)::bigint
    into v_cancel_count
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status = 'cancelled'
      and coalesce(r.is_no_show, false) = false
      and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date =
        v_month_start;
  end if;

  return jsonb_build_object(
    'payment_count', coalesce(v_payment_count, 0),
    'cancel_count', coalesce(v_cancel_count, 0),
    'rental_count', coalesce(v_rental_count, 0)
  );
end;
$$;

-- ── build_settlement_sheet_json — 취소 환불에서 노쇼 제외 ────────
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
  v_reservation_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_requested_at timestamptz;
  v_settled_at timestamptz;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
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
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'refund_amount'
  )
  into v_has_refund_col;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc(
            'month',
            coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
          )::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc(
          'month',
          coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
        )::date = v_month_start;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date =
          v_month_start;
    end if;
  end if;

  v_cancel_refund := coalesce(v_reservation_refund, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
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
        'actual_end_at', s.actual_end_at
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
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'payment_count', coalesce((v_counts->>'payment_count')::bigint, 0),
    'cancel_count', coalesce((v_counts->>'cancel_count')::bigint, 0),
    'rental_count', coalesce((v_counts->>'rental_count')::bigint, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'requested_at', v_requested_at,
    'settled_at', v_settled_at,
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

comment on function public.settlement_sheet_counts(uuid, timestamptz, timestamptz, integer, integer) is
  '정산 건수 — payment_count=예약 distinct paid(연장 ext_{id}_* 포함), cancel_count=노쇼 제외 cancelled, rental_count=반납완료 completed';
