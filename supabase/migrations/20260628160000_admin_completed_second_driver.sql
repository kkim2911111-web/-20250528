-- 대여 관리 완료 탭 — 제2운전자 정보 노출

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
  return_type text,
  is_no_show boolean,
  second_driver_name text,
  second_driver_license text,
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
    r.return_type,
    coalesce(r.is_no_show, false) as is_no_show,
    nullif(trim(r.second_driver_name), '') as second_driver_name,
    nullif(trim(r.second_driver_license), '') as second_driver_license,
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
  where r.status = 'completed'
     or (r.status = 'cancelled' and coalesce(r.is_no_show, false) = true)
  order by sort_at desc nulls last;
$$;

revoke all on function public.get_admin_completed_reservations() from public;
grant execute on function public.get_admin_completed_reservations() to authenticated;
