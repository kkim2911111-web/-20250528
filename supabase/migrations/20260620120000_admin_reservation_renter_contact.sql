-- 관리자 예약 목록: 임차인 이름·전화번호·결제금액 (renter_phone 추가, conflict RPC 필드 복원)

drop function if exists public.get_admin_reservations_with_conflict();

create or replace function public.get_admin_reservations_with_conflict()
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
  rental_started_at timestamptz,
  updated_at timestamptz,
  next_start_at timestamptz,
  is_conflict_risk boolean
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
      r.rental_started_at,
      r.updated_at,
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
    s.rental_started_at,
    s.updated_at,
    (
      select min(coalesce(n.start_at, n.start_time))
      from public.reservations n
      where n.vehicle_id = s.vehicle_id
        and n.id <> s.id
        and n.status in ('confirmed', 'in_use')
        and coalesce(n.start_at, n.start_time) > s.end_at
    ) as next_start_at,
    (
      exists (
        select 1
        from public.reservations n
        where n.vehicle_id = s.vehicle_id
          and n.id <> s.id
          and n.status in ('confirmed', 'in_use')
          and coalesce(n.start_at, n.start_time) > s.end_at
      )
      or exists (
        select 1
        from public.reservations n
        where n.vehicle_id = s.vehicle_id
          and n.id <> s.id
          and n.status in ('pending', 'confirmed', 'in_use')
          and coalesce(n.start_at, n.start_time) < s.end_at
          and coalesce(n.end_at, n.end_time) > s.start_at
      )
    ) as is_conflict_risk
  from scoped s
  order by s.start_at desc nulls last;
$$;

drop function if exists public.get_admin_completed_reservations();

create or replace function public.get_admin_completed_reservations()
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
  sort_at timestamptz
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
  )
  select
    r.id::text as reservation_id,
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
    coalesce(
      r.returned_at,
      r.actual_end_at,
      r.updated_at,
      r.end_at,
      r.end_time,
      r.start_at,
      r.start_time
    ) as sort_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join staff_complex sc on sc.complex_id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  where r.status in ('completed', 'returned', 'cancelled')
  order by sort_at desc nulls last;
$$;

revoke all on function public.get_admin_reservations_with_conflict() from public;
grant execute on function public.get_admin_reservations_with_conflict() to authenticated;

revoke all on function public.get_admin_completed_reservations() from public;
grant execute on function public.get_admin_completed_reservations() to authenticated;
