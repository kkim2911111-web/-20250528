-- 관리자 예약 타임라인 — 월별 차량×예약 조회

drop function if exists public.get_admin_reservation_timeline(integer, integer);

create or replace function public.get_admin_reservation_timeline(
  p_year integer,
  p_month integer
)
returns table (
  reservation_id text,
  reservation_number text,
  vehicle_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  is_no_show boolean,
  start_at timestamptz,
  end_at timestamptz,
  rental_started_at timestamptz,
  returned_at timestamptz,
  total_price integer
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid() and s.approved = true
    limit 1
  ),
  bounds as (
    select
      b.period_start,
      b.period_end
    from public.sales_month_bounds(p_year, p_month) as b
  )
  select
    r.id::text as reservation_id,
    r.reservation_number,
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
    coalesce(r.is_no_show, false) as is_no_show,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    r.rental_started_at,
    r.returned_at,
    coalesce(r.total_price, 0) as total_price
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join staff_complex sc on sc.complex_id = v.complex_id
  cross join bounds b
  left join public.user_profiles up on up.user_id = r.user_id
  where coalesce(r.start_at, r.start_time) < b.period_end
    and coalesce(r.end_at, r.end_time) > b.period_start
    and (
      r.status in ('confirmed', 'in_use', 'returned', 'completed')
      or coalesce(r.is_no_show, false) = true
    )
  order by coalesce(r.start_at, r.start_time);
$$;

revoke all on function public.get_admin_reservation_timeline(integer, integer) from public;
grant execute on function public.get_admin_reservation_timeline(integer, integer) to authenticated;
