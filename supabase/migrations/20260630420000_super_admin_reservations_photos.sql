-- 최고관리자 전체 예약 — 검수 사진 URL 배열 추가
drop function if exists public.get_super_admin_reservations();

create or replace function public.get_super_admin_reservations()
returns table (
  reservation_id text,
  reservation_number text,
  complex_id uuid,
  complex_name text,
  vehicle_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  is_no_show boolean,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz,
  created_at timestamptz,
  pickup_photos text[],
  return_photos text[]
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
    r.reservation_number,
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
    coalesce(r.is_no_show, false) as is_no_show,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    r.rental_started_at,
    r.returned_at,
    r.actual_end_at,
    r.created_at,
    coalesce(r.pickup_photos, '{}'::text[]) as pickup_photos,
    coalesce(r.return_photos, '{}'::text[]) as return_photos
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.complexes c on c.id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  order by coalesce(r.start_at, r.start_time) desc nulls last;
end;
$$;

revoke all on function public.get_super_admin_reservations() from public;
grant execute on function public.get_super_admin_reservations() to authenticated;

comment on function public.get_super_admin_reservations() is
  '최고관리자 전체 예약 목록 (검수 사진 URL 포함)';
