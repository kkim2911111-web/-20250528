-- ============================================================
-- 최고관리자(Super Admin) — 스키마 + 전용 RPC
-- ============================================================
-- 1) user_profiles.is_super_admin
-- 2) 자가 승격 방지 트리거
-- 3) assert_is_super_admin() 보안 헬퍼
-- 4) 플랫폼 전역 조회 RPC (is_super_admin = true 만 허용)
-- ============================================================

-- ── 1) is_super_admin 컬럼 ──────────────────────────────────
alter table public.user_profiles
  add column if not exists is_super_admin boolean not null default false;

comment on column public.user_profiles.is_super_admin is
  '플랫폼 최고관리자. SQL Editor / service_role 로만 부여 권장';

create index if not exists user_profiles_super_admin_idx
  on public.user_profiles (user_id)
  where is_super_admin = true;

-- ── 2) 자가 승격 방지 ───────────────────────────────────────
create or replace function public.guard_user_profiles_super_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_is_super boolean;
begin
  if current_setting('role', true) = 'service_role' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if coalesce(new.is_super_admin, false) then
      new.is_super_admin := false;
    end if;
    return new;
  end if;

  if new.is_super_admin is distinct from old.is_super_admin then
    select up.is_super_admin
    into v_caller_is_super
    from public.user_profiles up
    where up.user_id = auth.uid();

    if coalesce(v_caller_is_super, false) is not true then
      raise exception 'cannot_modify_super_admin_flag';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists user_profiles_guard_super_admin on public.user_profiles;
create trigger user_profiles_guard_super_admin
before insert or update on public.user_profiles
for each row execute function public.guard_user_profiles_super_admin();

-- ── 3) 보안 헬퍼 ────────────────────────────────────────────
create or replace function public.assert_is_super_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1
    from public.user_profiles up
    where up.user_id = auth.uid()
      and up.is_super_admin = true
  ) then
    raise exception 'super_admin_required';
  end if;
end;
$$;

revoke all on function public.assert_is_super_admin() from public;
grant execute on function public.assert_is_super_admin() to authenticated;

-- ── 4) get_super_admin_dashboard() — 전체 통계 ───────────────
drop function if exists public.get_super_admin_dashboard();

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
  sales_status as (
    select unnest(
      array['confirmed', 'in_use', 'returning', 'returned', 'completed']::text[]
    ) as status
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
    join sales_status ss on ss.status = r.status
    where coalesce(r.start_at, r.start_time) >= v_day_start
      and coalesce(r.start_at, r.start_time) < v_day_end
  ),
  month_rev as (
    select coalesce(sum(r.total_price), 0)::bigint as amt
    from public.reservations r
    join sales_status ss on ss.status = r.status
    where coalesce(r.start_at, r.start_time) >= v_month_start
  ),
  total_rev as (
    select coalesce(sum(r.total_price), 0)::bigint as amt
    from public.reservations r
    join sales_status ss on ss.status = r.status
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

-- ── 5) get_super_admin_complexes() — 단지 목록 ───────────────
drop function if exists public.get_super_admin_complexes();

create or replace function public.get_super_admin_complexes()
returns table (
  complex_id uuid,
  complex_name text,
  invite_code text,
  admin_invite_code text,
  business_name text,
  business_phone text,
  vehicle_count bigint,
  staff_count bigint,
  resident_count bigint,
  in_use_count bigint,
  month_revenue bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_month_start timestamptz;
begin
  perform public.assert_is_super_admin();

  v_month_start := date_trunc('month', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';

  return query
  select
    c.id as complex_id,
    c.name as complex_name,
    c.invite_code,
    c.admin_invite_code,
    c.business_name,
    c.business_phone,
    (
      select count(*)::bigint
      from public.vehicles v
      where v.complex_id = c.id
    ) as vehicle_count,
    (
      select count(*)::bigint
      from public.staff_users s
      where s.complex_id = c.id
    ) as staff_count,
    (
      select count(*)::bigint
      from public.residents res
      where res.complex_id = c.id
    ) as resident_count,
    (
      select count(distinct r.vehicle_id)::bigint
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = c.id
        and r.status = 'in_use'
    ) as in_use_count,
    (
      select coalesce(sum(r.total_price), 0)::bigint
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = c.id
        and r.status in (
          'confirmed', 'in_use', 'returning', 'returned', 'completed'
        )
        and coalesce(r.start_at, r.start_time) >= v_month_start
    ) as month_revenue,
    c.created_at
  from public.complexes c
  order by c.name asc nulls last, c.created_at desc;
end;
$$;

-- ── 6) get_super_admin_vehicles() — 차량 목록 ────────────────
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
  order by c.name asc nulls last, v.model_name asc nulls last;
end;
$$;

-- ── 7) get_super_admin_staff() — 스태프 목록 ─────────────────
drop function if exists public.get_super_admin_staff();

create or replace function public.get_super_admin_staff()
returns table (
  user_id uuid,
  complex_id uuid,
  complex_name text,
  display_name text,
  phone text,
  company_name text,
  approved boolean,
  email text,
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
    s.user_id,
    s.complex_id,
    c.name as complex_name,
    s.display_name,
    s.phone,
    s.company_name,
    s.approved,
    coalesce(up.email, au.email::text) as email,
    s.created_at
  from public.staff_users s
  join public.complexes c on c.id = s.complex_id
  left join public.user_profiles up on up.user_id = s.user_id
  left join auth.users au on au.id = s.user_id
  order by c.name asc nulls last, s.display_name asc nulls last;
end;
$$;

-- ── 8) get_super_admin_residents() — 입주민 목록 ─────────────
drop function if exists public.get_super_admin_residents();

create or replace function public.get_super_admin_residents()
returns table (
  user_id uuid,
  complex_id uuid,
  complex_name text,
  building text,
  unit text,
  approved boolean,
  full_name text,
  phone text,
  email text,
  license_verified boolean,
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
    res.user_id,
    res.complex_id,
    c.name as complex_name,
    res.building,
    res.unit,
    res.approved,
    up.full_name,
    up.phone,
    coalesce(up.email, au.email::text) as email,
    coalesce(up.license_verified, false) as license_verified,
    res.created_at
  from public.residents res
  join public.complexes c on c.id = res.complex_id
  left join public.user_profiles up on up.user_id = res.user_id
  left join auth.users au on au.id = res.user_id
  order by c.name asc nulls last, res.created_at desc;
end;
$$;

-- ── 9) get_super_admin_reservations() — 전체 예약 ────────────
drop function if exists public.get_super_admin_reservations();

create or replace function public.get_super_admin_reservations()
returns table (
  reservation_id text,
  complex_id uuid,
  complex_name text,
  vehicle_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_started_at timestamptz,
  returned_at timestamptz,
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
    r.id::text as reservation_id,
    v.complex_id,
    c.name as complex_name,
    r.vehicle_id::text as vehicle_id,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone,
    r.status,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    r.rental_started_at,
    r.returned_at,
    r.created_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.complexes c on c.id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  order by coalesce(r.start_at, r.start_time) desc nulls last;
end;
$$;

-- ── 10) get_super_admin_revenue() — 정산/매출 ────────────────
drop function if exists public.get_super_admin_revenue(integer, integer);

create or replace function public.get_super_admin_revenue(
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
  extension_revenue bigint
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

  v_year := coalesce(
    p_year,
    extract(year from now() at time zone 'Asia/Seoul')::integer
  );
  v_month := coalesce(
    p_month,
    extract(month from now() at time zone 'Asia/Seoul')::integer
  );

  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'Asia/Seoul');
  v_period_end := v_period_start + interval '1 month';

  return query
  with complexes_all as (
    select c.id, c.name from public.complexes c
  ),
  res_sales as (
    select
      v.complex_id,
      count(*)::bigint as reservation_count,
      coalesce(sum(r.total_price), 0)::bigint as gross_revenue
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where r.status in (
      'confirmed', 'in_use', 'returning', 'returned', 'completed'
    )
      and coalesce(r.start_at, r.start_time) >= v_period_start
      and coalesce(r.start_at, r.start_time) < v_period_end
    group by v.complex_id
  ),
  paid_orders as (
    select
      v.complex_id,
      count(*)::bigint as paid_order_count,
      coalesce(sum(po.total_price), 0)::bigint as paid_order_amount
    from public.payment_orders po
    join public.vehicles v on v.id::text = po.vehicle_id::text
    where po.status = 'paid'
      and po.created_at >= v_period_start
      and po.created_at < v_period_end
    group by v.complex_id
  ),
  extensions as (
    select
      v.complex_id,
      coalesce(sum(re.added_price), 0)::bigint as extension_revenue
    from public.reservation_extensions re
    join public.reservations r on r.id::text = re.reservation_id::text
    join public.vehicles v on v.id = r.vehicle_id
    where re.created_at >= v_period_start
      and re.created_at < v_period_end
    group by v.complex_id
  )
  select
    ca.id as complex_id,
    ca.name as complex_name,
    v_year as period_year,
    v_month as period_month,
    coalesce(rs.reservation_count, 0)::bigint as reservation_count,
    coalesce(rs.gross_revenue, 0)::bigint as gross_revenue,
    coalesce(po.paid_order_count, 0)::bigint as paid_order_count,
    coalesce(po.paid_order_amount, 0)::bigint as paid_order_amount,
    coalesce(ex.extension_revenue, 0)::bigint as extension_revenue
  from complexes_all ca
  left join res_sales rs on rs.complex_id = ca.id
  left join paid_orders po on po.complex_id = ca.id
  left join extensions ex on ex.complex_id = ca.id
  order by coalesce(rs.gross_revenue, 0) desc, ca.name asc nulls last;
end;
$$;

-- ── 11) 권한 ────────────────────────────────────────────────
revoke all on function public.get_super_admin_dashboard() from public;
revoke all on function public.get_super_admin_complexes() from public;
revoke all on function public.get_super_admin_vehicles() from public;
revoke all on function public.get_super_admin_staff() from public;
revoke all on function public.get_super_admin_residents() from public;
revoke all on function public.get_super_admin_reservations() from public;
revoke all on function public.get_super_admin_revenue(integer, integer) from public;

grant execute on function public.get_super_admin_dashboard() to authenticated;
grant execute on function public.get_super_admin_complexes() to authenticated;
grant execute on function public.get_super_admin_vehicles() to authenticated;
grant execute on function public.get_super_admin_staff() to authenticated;
grant execute on function public.get_super_admin_residents() to authenticated;
grant execute on function public.get_super_admin_reservations() to authenticated;
grant execute on function public.get_super_admin_revenue(integer, integer) to authenticated;

comment on function public.get_super_admin_dashboard() is
  '최고관리자 대시보드 — 플랫폼 전체 집계 통계';
comment on function public.get_super_admin_complexes() is
  '최고관리자 — 단지 목록 + 단지별 요약';
comment on function public.get_super_admin_vehicles() is
  '최고관리자 — 전체 차량 목록';
comment on function public.get_super_admin_staff() is
  '최고관리자 — 전체 스태프 목록';
comment on function public.get_super_admin_residents() is
  '최고관리자 — 전체 입주민 목록';
comment on function public.get_super_admin_reservations() is
  '최고관리자 — 전체 예약 목록';
comment on function public.get_super_admin_revenue(integer, integer) is
  '최고관리자 — 단지별 월간 정산/매출 (p_year, p_month 기본값: 이번 달)';
