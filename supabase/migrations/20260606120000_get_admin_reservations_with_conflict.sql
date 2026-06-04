-- 관리자 예약 목록 + 동일 차량 충돌 위험 (다음 예약 / 시간 겹침)

create or replace function public.get_admin_reservations_with_conflict()
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
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
      r.status,
      coalesce(r.start_at, r.start_time) as start_at,
      coalesce(r.end_at, r.end_time) as end_at,
      coalesce(v.model_name, v.name, '차량') as vehicle_name,
      v.car_number
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    join staff_complex sc on sc.complex_id = v.complex_id
    where r.status in ('pending', 'confirmed', 'in_use')
  )
  select
    s.id::text as reservation_id,
    s.vehicle_name,
    s.car_number,
    s.status,
    s.start_at,
    s.end_at,
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

revoke all on function public.get_admin_reservations_with_conflict() from public;
grant execute on function public.get_admin_reservations_with_conflict() to authenticated;
