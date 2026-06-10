-- 월 수수료 — 해당 월 등록·해지 기준 차량 대수 (대당 10만원, 일할 없음)

alter table public.vehicles
  add column if not exists deactivated_at timestamptz;

comment on column public.vehicles.deactivated_at is
  '서비스 해지 시각. null=미해지. 월 수수료는 created_at·deactivated_at 기준(일할 없음).';

create or replace function public.platform_fee_vehicle_count_for_month(
  p_complex_id uuid,
  p_year integer,
  p_month integer,
  p_as_of timestamptz default now()
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_period_start timestamptz;
  v_period_end timestamptz;
begin
  if p_complex_id is null then
    return 0;
  end if;

  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(p_year, p_month) as b;

  -- 미래 월: 현재 미해지 차량 수(예상치)
  if v_period_start > p_as_of then
    return (
      select count(*)::integer
      from public.vehicles v
      where v.complex_id = p_complex_id
        and v.deactivated_at is null
    );
  end if;

  return (
    select count(*)::integer
    from public.vehicles v
    where v.complex_id = p_complex_id
      and v.created_at < v_period_end
      and (v.deactivated_at is null or v.deactivated_at >= v_period_start)
  );
end;
$$;

create or replace function public.platform_fee_is_estimate_month(
  p_year integer,
  p_month integer,
  p_as_of timestamptz default now()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_period_start timestamptz;
begin
  select b.period_start
  into v_period_start
  from public.sales_month_bounds(p_year, p_month) as b;
  return v_period_start > p_as_of;
end;
$$;

revoke all on function public.platform_fee_vehicle_count_for_month(uuid, integer, integer, timestamptz) from public;
grant execute on function public.platform_fee_vehicle_count_for_month(uuid, integer, integer, timestamptz)
  to authenticated, service_role;

revoke all on function public.platform_fee_is_estimate_month(integer, integer, timestamptz) from public;
grant execute on function public.platform_fee_is_estimate_month(integer, integer, timestamptz)
  to authenticated, service_role;

-- ── get_super_admin_revenue — billable_vehicle_count 추가 ───────
drop function if exists public.get_super_admin_revenue(integer, integer);

create function public.get_super_admin_revenue(
  p_year integer default null,
  p_month integer default null
)
returns table (
  complex_id uuid,
  complex_name text,
  period_year integer,
  period_month integer,
  reservation_count bigint,
  gross_revenue bigint,
  paid_order_count bigint,
  paid_order_amount bigint,
  extension_revenue bigint,
  billable_vehicle_count integer,
  is_fee_estimate boolean,
  is_settled boolean,
  is_requested boolean,
  settled_at timestamptz,
  requested_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_fee_estimate boolean;
begin
  perform public.assert_is_super_admin();
  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_fee_estimate := public.platform_fee_is_estimate_month(v_year, v_month);

  return query
  with complexes_all as (
    select c.id, c.name from public.complexes c
  ),
  res_sales as (
    select
      s.complex_id,
      count(*)::bigint as reservation_count,
      coalesce(sum(s.gross_amount), 0)::bigint as gross_revenue
    from public.sales_completed_reservations_v s
    where s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.complex_id
  ),
  extensions as (
    select
      e.complex_id,
      coalesce(sum(e.extension_amount), 0)::bigint as extension_revenue
    from public.sales_extension_lines_v e
    where e.return_completed_at >= v_period_start
      and e.return_completed_at < v_period_end
    group by e.complex_id
  ),
  paid_orders as (
    select
      s.complex_id,
      count(distinct po.order_id)::bigint as paid_order_count,
      coalesce(sum(po.total_price), 0)::bigint as paid_order_amount
    from public.sales_completed_reservations_v s
    join public.reservations r on r.id::text = s.reservation_id_text
    join public.payment_orders po
      on po.order_id = r.order_id
      and po.status = 'paid'
    where s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.complex_id
  )
  select
    ca.id,
    ca.name,
    v_year,
    v_month,
    coalesce(rs.reservation_count, 0),
    coalesce(rs.gross_revenue, 0),
    coalesce(po.paid_order_count, 0),
    coalesce(po.paid_order_amount, 0),
    coalesce(ex.extension_revenue, 0),
    public.platform_fee_vehicle_count_for_month(ca.id, v_year, v_month),
    v_fee_estimate,
    (cs.settled_at is not null),
    (cs.requested_at is not null and cs.settled_at is null),
    cs.settled_at,
    cs.requested_at
  from complexes_all ca
  left join res_sales rs on rs.complex_id = ca.id
  left join paid_orders po on po.complex_id = ca.id
  left join extensions ex on ex.complex_id = ca.id
  left join public.complex_settlements cs
    on cs.complex_id = ca.id
    and cs.period_year = v_year
    and cs.period_month = v_month
  order by
    coalesce(rs.gross_revenue, 0) + coalesce(ex.extension_revenue, 0) desc,
    ca.name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_revenue(integer, integer) from public;
grant execute on function public.get_super_admin_revenue(integer, integer) to authenticated;

-- ── get_admin_sales_summary — 동일 월 차량 대수 ─────────────────
drop function if exists public.get_admin_sales_summary(uuid, integer, integer);

create or replace function public.get_admin_sales_summary(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_gross bigint := 0;
  v_extension bigint := 0;
  v_count bigint := 0;
  v_vehicle_count integer := 0;
  v_fee_estimate boolean := false;
  v_rows jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_vehicle_count := public.platform_fee_vehicle_count_for_month(
    p_complex_id, v_year, v_month
  );
  v_fee_estimate := public.platform_fee_is_estimate_month(v_year, v_month);

  v_count := public.sales_count_reservations(p_complex_id, v_period_start, v_period_end);
  v_gross := public.sales_sum_gross(p_complex_id, v_period_start, v_period_end);
  v_extension := public.sales_sum_extension(p_complex_id, v_period_start, v_period_end);

  v_counts := public.settlement_sheet_counts(
    p_complex_id, v_period_start, v_period_end, v_year, v_month
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vehicle_name', row_data.vehicle_name,
        'amount', row_data.amount,
        'count', row_data.cnt
      )
      order by row_data.amount desc nulls last
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      s.vehicle_name,
      coalesce(sum(s.gross_amount), 0)::bigint as amount,
      count(*)::bigint as cnt
    from public.sales_completed_reservations_v s
    where s.complex_id = p_complex_id
      and s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.vehicle_name
  ) row_data;

  select
    cs.settled_at is not null,
    cs.requested_at is not null and cs.settled_at is null
  into v_is_settled, v_is_requested
  from public.complex_settlements cs
  where cs.complex_id = p_complex_id
    and cs.period_year = v_year
    and cs.period_month = v_month;

  return jsonb_build_object(
    'gross_revenue', coalesce(v_gross, 0),
    'extension_revenue', coalesce(v_extension, 0),
    'total_revenue', coalesce(v_gross, 0) + coalesce(v_extension, 0),
    'reservation_count', coalesce(v_count, 0),
    'vehicle_count', coalesce(v_vehicle_count, 0),
    'is_fee_estimate', v_fee_estimate,
    'payment_count', coalesce((v_counts->>'payment_count')::bigint, 0),
    'cancel_count', coalesce((v_counts->>'cancel_count')::bigint, 0),
    'rental_count', coalesce((v_counts->>'rental_count')::bigint, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_admin_sales_summary(uuid, integer, integer) from public;
grant execute on function public.get_admin_sales_summary(uuid, integer, integer) to authenticated;

-- 해지 시각 기록 (최고관리자 차량 삭제 → soft deactivate)
create or replace function public.delete_super_admin_vehicle(p_vehicle_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();

  update public.vehicles
  set
    deactivated_at = coalesce(deactivated_at, now()),
    is_available = false,
    updated_at = now()
  where id::text = trim(p_vehicle_id);

  if not found then
    raise exception 'vehicle_not_found';
  end if;
end;
$$;

-- 해지된 차량은 목록에서 제외
drop function if exists public.get_super_admin_vehicles();

create or replace function public.get_super_admin_vehicles()
returns table (
  vehicle_id text,
  complex_id uuid,
  complex_name text,
  model_name text,
  car_number text,
  vehicle_type text,
  fuel_type text,
  price_per_hour integer,
  daily_price integer,
  monthly_price integer,
  rental_types text[],
  is_available boolean,
  in_use boolean,
  current_reservation_status text,
  current_renter_name text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();

  return query
  select
    v.id::text as vehicle_id,
    v.complex_id,
    c.name as complex_name,
    coalesce(v.model_name, '차량') as model_name,
    v.car_number,
    v.vehicle_type,
    v.fuel_type,
    coalesce(v.price_per_hour, 0) as price_per_hour,
    v.daily_price,
    v.monthly_price,
    coalesce(v.rental_types, array['hourly']::text[]) as rental_types,
    coalesce(v.is_available, false) as is_available,
    (cur.id is not null) as in_use,
    cur.status as current_reservation_status,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      null
    ) as current_renter_name,
    v.created_at
  from public.vehicles v
  join public.complexes c on c.id = v.complex_id
  left join lateral (
    select r.id, r.status, r.user_id
    from public.reservations r
    where r.vehicle_id = v.id
      and r.status = 'in_use'
    order by coalesce(r.start_at, r.start_time) desc
    limit 1
  ) cur on true
  left join public.user_profiles up on up.user_id = cur.user_id
  where v.deactivated_at is null
  order by c.name asc nulls last, v.model_name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_vehicles() from public;
grant execute on function public.get_super_admin_vehicles() to authenticated;
