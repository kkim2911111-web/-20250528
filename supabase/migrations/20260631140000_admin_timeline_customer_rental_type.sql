-- 관리자 타임라인·고객 예약 이력에 rental_type 반환

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
  total_price integer,
  rental_type text
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
    coalesce(r.total_price, 0) as total_price,
    coalesce(r.rental_type, 'hourly') as rental_type
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

drop function if exists public.get_admin_customer_reservations(uuid);

create or replace function public.get_admin_customer_reservations(p_user_id uuid)
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  return_completed_at timestamptz,
  sort_at timestamptz,
  rental_type text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
begin
  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = auth.uid()
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    raise exception 'staff_not_found';
  end if;

  if not exists (
    select 1
    from public.residents r
    where r.user_id = p_user_id
      and r.complex_id = v_complex_id
  ) then
    raise exception 'resident_not_found';
  end if;

  return query
  select
    r.id::text as reservation_id,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    r.status,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    public.sales_return_completed_at(
      r.returned_at,
      r.actual_end_at,
      coalesce(r.end_at, r.end_time)
    ) as return_completed_at,
    coalesce(
      public.sales_return_completed_at(
        r.returned_at,
        r.actual_end_at,
        coalesce(r.end_at, r.end_time)
      ),
      r.updated_at,
      coalesce(r.end_at, r.end_time),
      coalesce(r.start_at, r.start_time),
      r.created_at
    ) as sort_at,
    coalesce(r.rental_type, 'hourly') as rental_type
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where r.user_id = p_user_id
    and v.complex_id = v_complex_id
  order by sort_at desc nulls last;
end;
$$;

revoke all on function public.get_admin_customer_reservations(uuid) from public;
grant execute on function public.get_admin_customer_reservations(uuid) to authenticated;
