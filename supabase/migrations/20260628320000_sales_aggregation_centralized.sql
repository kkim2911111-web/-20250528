-- 매출·정산 집계 기준 중앙화
-- 기준 변경 시 sales_return_completed_at / sales_completed_reservations_v 만 수정하면 전 RPC 반영

-- ── 1) 반납 완료일 (단일 정의) ─────────────────────────────────
create or replace function public.sales_return_completed_at(
  p_returned_at timestamptz,
  p_actual_end_at timestamptz
)
returns timestamptz
language sql
immutable
parallel safe
as $$
  select coalesce(p_returned_at, p_actual_end_at);
$$;

comment on function public.sales_return_completed_at(timestamptz, timestamptz) is
  '매출 집계 반납 완료일 — coalesce(returned_at, actual_end_at). 기준 변경 시 이 함수만 수정.';

-- ── 2) 기간 경계 (Asia/Seoul) ───────────────────────────────────
create or replace function public.sales_month_bounds(
  p_year integer,
  p_month integer,
  out period_start timestamptz,
  out period_end timestamptz
)
returns record
language sql
immutable
parallel safe
as $$
  select
    make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul'),
    make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul') + interval '1 month';
$$;

create or replace function public.sales_current_month_bounds(
  out period_start timestamptz,
  out period_end timestamptz
)
returns record
language sql
stable
parallel safe
as $$
  select
    date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul',
    (date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
      + interval '1 month';
$$;

create or replace function public.sales_today_bounds(
  out period_start timestamptz,
  out period_end timestamptz
)
returns record
language sql
stable
parallel safe
as $$
  select
    date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul',
    (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
      + interval '1 day';
$$;

-- ── 3) 매출 대상 View (completed + 반납 완료일 존재) ─────────────
create or replace view public.sales_completed_reservations_v as
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
  public.sales_return_completed_at(r.returned_at, r.actual_end_at) as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  coalesce(r.is_no_show, false) as is_no_show
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'completed'
  and public.sales_return_completed_at(r.returned_at, r.actual_end_at) is not null;

comment on view public.sales_completed_reservations_v is
  '매출 집계 대상 예약 — status=completed, 반납 완료일 기준. 정상 반납·노쇼 포함.';

-- ── 4) 연장 매출 View (위 View 기준 동일 기간 필터) ─────────────
create or replace view public.sales_extension_lines_v as
select
  scr.reservation_id_text,
  scr.complex_id,
  scr.return_completed_at,
  coalesce(re.added_price, 0)::bigint as extension_amount
from public.reservation_extensions re
inner join public.sales_completed_reservations_v scr
  on scr.reservation_id_text = re.reservation_id::text;

comment on view public.sales_extension_lines_v is
  '매출 집계 대상 연장 요금 — sales_completed_reservations_v와 동일 예약만.';

-- ── 5) 집계 헬퍼 (RPC 공통) ─────────────────────────────────────
create or replace function public.sales_sum_gross(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(s.gross_amount), 0)::bigint
  from public.sales_completed_reservations_v s
  where (p_complex_id is null or s.complex_id = p_complex_id)
    and (p_period_start is null or s.return_completed_at >= p_period_start)
    and (p_period_end is null or s.return_completed_at < p_period_end);
$$;

create or replace function public.sales_sum_extension(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(e.extension_amount), 0)::bigint
  from public.sales_extension_lines_v e
  where (p_complex_id is null or e.complex_id = p_complex_id)
    and (p_period_start is null or e.return_completed_at >= p_period_start)
    and (p_period_end is null or e.return_completed_at < p_period_end);
$$;

create or replace function public.sales_count_reservations(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::bigint
  from public.sales_completed_reservations_v s
  where (p_complex_id is null or s.complex_id = p_complex_id)
    and (p_period_start is null or s.return_completed_at >= p_period_start)
    and (p_period_end is null or s.return_completed_at < p_period_end);
$$;

create or replace function public.sales_total_revenue(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select
    public.sales_sum_gross(p_complex_id, p_period_start, p_period_end)
    + public.sales_sum_extension(p_complex_id, p_period_start, p_period_end);
$$;

revoke all on function public.sales_sum_gross(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_sum_extension(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_count_reservations(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_total_revenue(uuid, timestamptz, timestamptz) from public;

drop function if exists public.get_admin_sales_summary(uuid, integer, integer);
drop function if exists public.get_admin_branch_sales_stats(uuid);
drop function if exists public.get_super_admin_dashboard();
drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

-- ── 6) get_admin_sales_summary ───────────────────────────────────
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
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  select count(*)::integer
  into v_vehicle_count
  from public.vehicles v
  where v.complex_id = p_complex_id;

  v_count := public.sales_count_reservations(p_complex_id, v_period_start, v_period_end);
  v_gross := public.sales_sum_gross(p_complex_id, v_period_start, v_period_end);
  v_extension := public.sales_sum_extension(p_complex_id, v_period_start, v_period_end);

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

-- ── 7) get_admin_branch_sales_stats ─────────────────────────────
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
  v_month_end timestamptz;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  select b.period_start, b.period_end
  into v_day_start, v_day_end
  from public.sales_today_bounds() as b;

  select b.period_start, b.period_end
  into v_month_start, v_month_end
  from public.sales_current_month_bounds() as b;

  return jsonb_build_object(
    'today_sales',
      public.sales_total_revenue(p_complex_id, v_day_start, v_day_end),
    'month_sales',
      public.sales_total_revenue(p_complex_id, v_month_start, v_month_end)
  );
end;
$$;

-- ── 8) get_super_admin_revenue ──────────────────────────────────
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
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

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
    inner join public.payment_orders po
      on po.reservation_id = s.reservation_id_text
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
    (cs.id is not null),
    cs.settled_at
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

-- ── 9) get_super_admin_dashboard ────────────────────────────────
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
  v_month_end timestamptz;
begin
  perform public.assert_is_super_admin();

  select b.period_start, b.period_end
  into v_day_start, v_day_end
  from public.sales_today_bounds() as b;

  select b.period_start, b.period_end
  into v_month_start, v_month_end
  from public.sales_current_month_bounds() as b;

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
    public.sales_total_revenue(null, v_day_start, v_day_end),
    public.sales_total_revenue(null, v_month_start, v_month_end),
    public.sales_total_revenue(null, null, null);
end;
$$;

-- ── 10) get_super_admin_settlement_reservations ─────────────────
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
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  return query
  select
    s.reservation_id_text as reservation_id,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(s.gross_amount, 0)::integer as total_price,
    s.start_at,
    s.end_at,
    s.rental_started_at,
    s.returned_at,
    s.actual_end_at
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end
  order by s.return_completed_at desc nulls last;
end;
$$;

-- ── 권한·설명 ───────────────────────────────────────────────────
revoke all on function public.get_admin_branch_sales_stats(uuid) from public;
grant execute on function public.get_admin_branch_sales_stats(uuid) to authenticated;

revoke all on function public.get_admin_sales_summary(uuid, integer, integer) from public;
grant execute on function public.get_admin_sales_summary(uuid, integer, integer) to authenticated;

revoke all on function public.get_super_admin_revenue(integer, integer) from public;
grant execute on function public.get_super_admin_revenue(integer, integer) to authenticated;

revoke all on function public.get_super_admin_dashboard() from public;
grant execute on function public.get_super_admin_dashboard() to authenticated;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_admin_sales_summary(uuid, integer, integer) is
  '단지 관리자 매출 — sales_completed_reservations_v 기준 (completed·반납 완료일)';

comment on function public.get_admin_branch_sales_stats(uuid) is
  '단지 관리자 홈 매출 카드 — sales_total_revenue 기준 (gross+연장)';

comment on function public.get_super_admin_revenue(integer, integer) is
  '최고관리자 정산 — sales_completed_reservations_v / sales_extension_lines_v 기준';

comment on function public.get_super_admin_dashboard() is
  '최고관리자 대시보드 — 매출 카드는 sales_total_revenue 기준';

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '최고관리자 정산 상세 — sales_completed_reservations_v와 동일 집계 기준';
