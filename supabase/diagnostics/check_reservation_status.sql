-- 현재 로그인 사용자 예약 상태 (SQL Editor에서 auth.uid() 사용)
select
  id,
  status,
  photos_uploaded,
  license_verified,
  rental_started_at,
  coalesce(cardinality(pickup_photos), 0) as pickup_photo_count,
  order_id,
  payment_status
from public.reservations
where user_id = auth.uid()
order by coalesce(start_at, start_time) desc nulls last;

-- ── 상태 꼬임 복구 (결제 직후 in_use 로 잘못 올라간 경우) ──
-- 아래 결과를 확인한 뒤 필요할 때만 실행하세요.
--
-- select id, status, photos_uploaded, license_verified, rental_started_at
-- from public.reservations
-- where status = 'in_use'
--   and (photos_uploaded = false or license_verified = false);
--
-- update public.reservations
-- set
--   status = 'confirmed',
--   rental_started_at = null,
--   photos_uploaded = coalesce(photos_uploaded, pickup_photos is not null and cardinality(pickup_photos) >= 6),
--   license_verified = false
-- where status = 'in_use'
--   and coalesce(photos_uploaded, false) = false
--   and coalesce(license_verified, false) = false;
