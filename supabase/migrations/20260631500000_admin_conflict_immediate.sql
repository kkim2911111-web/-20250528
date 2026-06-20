-- 충돌위험: 예약 생성 즉시 표시 (겹침 + 연속 예약, 30분 상한 제거)

drop function if exists public.get_admin_reservations_with_conflict();
drop function if exists public.get_admin_reservations_with_conflict(integer, integer);

create or replace function public.get_admin_reservations_with_conflict(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_type text,
  rental_started_at timestamptz,
  updated_at timestamptz,
  next_start_at timestamptz,
  next_renter_name text,
  next_renter_phone text,
  is_conflict_risk boolean,
  second_driver_name text,
  second_driver_license text
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
    limit 1
  ),
  scoped as (
    select
      r.id,
      r.vehicle_id,
      r.user_id,
      r.status,
      coalesce(r.start_at, r.start_time) as start_at,
      coalesce(r.end_at, r.end_time) as end_at,
      coalesce(r.total_price, 0) as total_price,
      coalesce(r.rental_type, 'hourly') as rental_type,
      r.rental_started_at,
      r.updated_at,
      nullif(trim(r.second_driver_name), '') as second_driver_name,
      nullif(trim(r.second_driver_license), '') as second_driver_license,
      coalesce(v.model_name, '차량') as vehicle_name,
      v.car_number,
      coalesce(
        nullif(trim(up.full_name), ''),
        nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as renter_name,
      coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    join staff_complex sc on sc.complex_id = v.complex_id
    left join public.user_profiles up on up.user_id = r.user_id
    where r.status in ('pending', 'confirmed', 'in_use', 'returning')
      and r.status not in ('returned', 'completed', 'cancelled')
  )
  select
    s.id::text as reservation_id,
    s.vehicle_name,
    s.car_number,
    s.renter_name,
    s.renter_phone,
    s.status,
    s.start_at,
    s.end_at,
    s.total_price,
    s.rental_type,
    s.rental_started_at,
    s.updated_at,
    next_res.next_start_at,
    next_res.next_renter_name,
    next_res.next_renter_phone,
    (
      s.status in ('pending', 'confirmed', 'in_use')
      and next_res.next_start_at is not null
    ) as is_conflict_risk,
    s.second_driver_name,
    s.second_driver_license
  from scoped s
  left join lateral (
    select
      coalesce(n.start_at, n.start_time) as next_start_at,
      coalesce(
        nullif(trim(nup.full_name), ''),
        nullif(split_part(nullif(trim(nup.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as next_renter_name,
      coalesce(nullif(trim(nup.phone), ''), '미등록') as next_renter_phone
    from public.reservations n
    left join public.user_profiles nup on nup.user_id = n.user_id
    where n.vehicle_id = s.vehicle_id
      and n.id <> s.id
      and n.status in ('pending', 'confirmed', 'in_use')
      and n.status not in ('returned', 'completed', 'cancelled')
      and (
        (
          coalesce(n.start_at, n.start_time) < s.end_at
          and coalesce(n.end_at, n.end_time) > s.start_at
        )
        or coalesce(n.start_at, n.start_time) >= s.end_at - interval '5 minutes'
      )
    order by coalesce(n.start_at, n.start_time)
    limit 1
  ) next_res on true
  order by s.start_at desc nulls last
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.get_admin_reservations_with_conflict(integer, integer) from public;
grant execute on function public.get_admin_reservations_with_conflict(integer, integer) to authenticated;
