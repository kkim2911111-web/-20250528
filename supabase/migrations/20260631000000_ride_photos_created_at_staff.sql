-- 관리자 검수 사진 조회: ride_photos.created_at 포함

drop function if exists public.get_ride_photos_for_staff(text, text);

create or replace function public.get_ride_photos_for_staff(
  p_reservation_id text,
  p_photo_type text
)
returns table (photo_url text, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select rp.photo_url, rp.created_at
  from public.ride_photos rp
  join public.reservations r on r.id::text = rp.reservation_id
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = auth.uid()
    and s.approved = true
  where rp.reservation_id = nullif(trim(p_reservation_id), '')
    and (
      rp.photo_type = nullif(trim(p_photo_type), '')
      or (
        rp.photo_type is null
        and rp.phase = case nullif(trim(p_photo_type), '')
          when 'before' then 'pickup'
          when 'after' then 'return'
          else nullif(trim(p_photo_type), '')
        end
      )
    )
  order by rp.photo_order asc, rp.id asc;
$$;

revoke all on function public.get_ride_photos_for_staff(text, text) from public;
grant execute on function public.get_ride_photos_for_staff(text, text) to authenticated;
