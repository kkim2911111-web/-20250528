-- 매출·정산 집계: completed만, 월 기준 = 반납 완료일(returned_at / actual_end_at)

-- ── 단지 관리자 매출 요약 ─────────────────────────────────────
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
  v_rows jsonb := '[]'::jsonb;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'Asia/Seoul');
  v_period_end := v_period_start + interval '1 month';

  select count(*)::integer
  into v_vehicle_count
  from public.vehicles v
  where v.complex_id = p_complex_id;

  select
    count(*)::bigint,
    coalesce(sum(r.total_price), 0)::bigint
  into v_count, v_gross
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_period_start
    and coalesce(r.returned_at, r.actual_end_at) < v_period_end;

  select coalesce(sum(re.added_price), 0)::bigint
  into v_extension
  from public.reservation_extensions re
  join public.reservations r on r.id::text = re.reservation_id::text
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_period_start
    and coalesce(r.returned_at, r.actual_end_at) < v_period_end;

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
      coalesce(v.model_name, '차량') as vehicle_name,
      coalesce(sum(r.total_price), 0)::bigint as amount,
      count(*)::bigint as cnt
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status = 'completed'
      and coalesce(r.returned_at, r.actual_end_at) >= v_period_start
      and coalesce(r.returned_at, r.actual_end_at) < v_period_end
    group by v.model_name
  ) row_data;

  return jsonb_build_object(
    'gross_revenue', coalesce(v_gross, 0),
    'extension_revenue', coalesce(v_extension, 0),
    'total_revenue', coalesce(v_gross, 0) + coalesce(v_extension, 0),
    'reservation_count', coalesce(v_count, 0),
    'vehicle_count', coalesce(v_vehicle_count, 0),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

-- ── 단지 관리자 홈 — 오늘/이번달 매출 ─────────────────────────
create or replace function public.get_admin_branch_sales_stats(p_complex_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_today bigint := 0;
  v_month bigint := 0;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_day_start := date_trunc('day', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';
  v_day_end := v_day_start + interval '1 day';
  v_month_start := date_trunc('month', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';

  select coalesce(sum(r.total_price), 0)::bigint
  into v_today
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_day_start
    and coalesce(r.returned_at, r.actual_end_at) < v_day_end;

  select coalesce(sum(r.total_price), 0)::bigint
  into v_month
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_month_start;

  return jsonb_build_object(
    'today_sales', coalesce(v_today, 0),
    'month_sales', coalesce(v_month, 0)
  );
end;
$$;

-- ── 최고관리자 정산 ───────────────────────────────────────────
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
  is_settled boolean,
  settled_at timestamptz
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
begin
  perform public.assert_is_super_admin();
  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'Asia/Seoul');
  v_period_end := v_period_start + interval '1 month';

  return query
  with complexes_all as (select c.id, c.name from public.complexes c),
  res_sales as (
    select v.complex_id, count(*)::bigint as reservation_count,
      coalesce(sum(r.total_price), 0)::bigint as gross_revenue
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where r.status = 'completed'
      and coalesce(r.returned_at, r.actual_end_at) >= v_period_start
      and coalesce(r.returned_at, r.actual_end_at) < v_period_end
    group by v.complex_id
  ),
  paid_orders as (
    select v.complex_id, count(*)::bigint as paid_order_count,
      coalesce(sum(po.total_price), 0)::bigint as paid_order_amount
    from public.payment_orders po
    join public.vehicles v on v.id::text = po.vehicle_id::text
    where po.status = 'paid'
      and po.created_at >= v_period_start and po.created_at < v_period_end
    group by v.complex_id
  ),
  extensions as (
    select v.complex_id, coalesce(sum(re.added_price), 0)::bigint as extension_revenue
    from public.reservation_extensions re
    join public.reservations r on r.id::text = re.reservation_id::text
    join public.vehicles v on v.id = r.vehicle_id
    where r.status = 'completed'
      and coalesce(r.returned_at, r.actual_end_at) >= v_period_start
      and coalesce(r.returned_at, r.actual_end_at) < v_period_end
    group by v.complex_id
  )
  select ca.id, ca.name, v_year, v_month,
    coalesce(rs.reservation_count, 0), coalesce(rs.gross_revenue, 0),
    coalesce(po.paid_order_count, 0), coalesce(po.paid_order_amount, 0),
    coalesce(ex.extension_revenue, 0),
    (cs.id is not null), cs.settled_at
  from complexes_all ca
  left join res_sales rs on rs.complex_id = ca.id
  left join paid_orders po on po.complex_id = ca.id
  left join extensions ex on ex.complex_id = ca.id
  left join public.complex_settlements cs
    on cs.complex_id = ca.id and cs.period_year = v_year and cs.period_month = v_month
  order by coalesce(rs.gross_revenue, 0) desc, ca.name asc nulls last;
end;
$$;

-- ── 최고관리자 대시보드 매출 카드 ─────────────────────────────
create or replace function public.get_super_admin_dashboard()
returns table (
  complex_count bigint,
  vehicle_count bigint,
  available_vehicle_count bigint,
  in_use_vehicle_count bigint,
  staff_count bigint,
  staff_approved_count bigint,
  resident_count bigint,
  resident_approved_count bigint,
  reservation_count_today bigint,
  reservation_active_count bigint,
  today_revenue bigint,
  month_revenue bigint,
  total_revenue bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
begin
  perform public.assert_is_super_admin();

  v_day_start := date_trunc('day', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';
  v_day_end := v_day_start + interval '1 day';
  v_month_start := date_trunc('month', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';

  return query
  with in_use as (
    select distinct r.vehicle_id
    from public.reservations r
    where r.status = 'in_use'
  ),
  today_res as (
    select count(*)::bigint as cnt
    from public.reservations r
    where coalesce(r.start_at, r.start_time) >= v_day_start
      and coalesce(r.start_at, r.start_time) < v_day_end
  ),
  active_res as (
    select count(*)::bigint as cnt
    from public.reservations r
    where r.status in ('pending', 'confirmed', 'in_use', 'returning')
  ),
  today_rev as (
    select coalesce(sum(r.total_price), 0)::bigint as amt
    from public.reservations r
    where r.status = 'completed'
      and coalesce(r.returned_at, r.actual_end_at) >= v_day_start
      and coalesce(r.returned_at, r.actual_end_at) < v_day_end
  ),
  month_rev as (
    select coalesce(sum(r.total_price), 0)::bigint as amt
    from public.reservations r
    where r.status = 'completed'
      and coalesce(r.returned_at, r.actual_end_at) >= v_month_start
  ),
  total_rev as (
    select coalesce(sum(r.total_price), 0)::bigint as amt
    from public.reservations r
    where r.status = 'completed'
  )
  select
    (select count(*)::bigint from public.complexes),
    (select count(*)::bigint from public.vehicles),
    (
      select count(*)::bigint
      from public.vehicles v
      where v.is_available = true
        and not exists (
          select 1 from in_use iu where iu.vehicle_id = v.id
        )
    ),
    (select count(*)::bigint from in_use),
    (select count(*)::bigint from public.staff_users),
    (
      select count(*)::bigint
      from public.staff_users s
      where s.approved = true
    ),
    (select count(*)::bigint from public.residents),
    (
      select count(*)::bigint
      from public.residents res
      where res.approved = true
    ),
    (select cnt from today_res),
    (select cnt from active_res),
    (select amt from today_rev),
    (select amt from month_rev),
    (select amt from total_rev);
end;
$$;

-- ── 정산 상세 예약 목록 (집계 기준 동일) ─────────────────────
create or replace function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns table (
  reservation_id text,
  renter_name text,
  total_price integer,
  start_at timestamptz,
  end_at timestamptz,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz
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
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'Asia/Seoul');
  v_period_end := v_period_start + interval '1 month';

  return query
  select
    r.id::text as reservation_id,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(r.total_price, 0)::integer as total_price,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    r.rental_started_at,
    r.returned_at,
    r.actual_end_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  left join public.user_profiles up on up.user_id = r.user_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_period_start
    and coalesce(r.returned_at, r.actual_end_at) < v_period_end
  order by coalesce(r.returned_at, r.actual_end_at) desc nulls last;
end;
$$;

revoke all on function public.get_admin_branch_sales_stats(uuid) from public;
grant execute on function public.get_admin_branch_sales_stats(uuid) to authenticated;

grant execute on function public.get_super_admin_revenue(integer, integer) to authenticated;

comment on function public.get_admin_sales_summary(uuid, integer, integer) is
  '단지 관리자 매출 — completed만, 반납 완료일(Asia/Seoul 월) 기준';

comment on function public.get_admin_branch_sales_stats(uuid) is
  '단지 관리자 홈 매출 카드 — completed만, 반납 완료일 기준';

comment on function public.get_super_admin_revenue(integer, integer) is
  '최고관리자 정산 — completed만, 반납 완료일(Asia/Seoul 월) 기준';

comment on function public.get_super_admin_dashboard() is
  '최고관리자 대시보드 — 매출 카드는 completed·반납 완료일 기준';

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '최고관리자 정산 상세 — get_super_admin_revenue와 동일 집계 기준';
