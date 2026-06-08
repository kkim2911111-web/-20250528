-- 관리자 반납 검수 — ride_photos 조회 (reservations 배열 비어 있을 때 폴백)

drop function if exists public.get_ride_photos_for_staff(text, text);

create or replace function public.get_ride_photos_for_staff(
  p_reservation_id text,
  p_phase text
)
returns table (photo_url text)
language sql
stable
security definer
set search_path = public
as $$
  select rp.photo_url
  from public.ride_photos rp
  join public.reservations r on r.id::text = rp.reservation_id
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = auth.uid()
    and s.approved = true
  where rp.reservation_id = nullif(trim(p_reservation_id), '')
    and rp.phase = nullif(trim(p_phase), '')
  order by rp.photo_order asc, rp.id asc;
$$;

revoke all on function public.get_ride_photos_for_staff(text, text) from public;
grant execute on function public.get_ride_photos_for_staff(text, text) to authenticated;
