-- 예약번호 마이그레이션 전·후 백업 CSV 추출용
-- Supabase SQL Editor 또는 psql에서 실행
--
-- 마이그레이션 적용 전(현재 번호):
--   아래 1번 쿼리 결과를 CSV로 저장
--
-- 마이그레이션 적용 후(변경 로그):
--   2번 쿼리로 old/new 매핑 확인

-- 1) 적용 전 스냅샷 (수동 백업 — 마이그레이션 전 1회)
select
  r.id::text as reservation_id,
  v.complex_id::text as complex_id,
  c.short_code,
  r.reservation_number as old_reservation_number,
  r.created_at as reservation_created_at,
  coalesce(r.start_at, r.start_time) as rental_start_at,
  r.status
from public.reservations r
join public.vehicles v on v.id = r.vehicle_id
join public.complexes c on c.id = v.complex_id
where c.short_code is not null
  and trim(c.short_code) <> ''
order by r.created_at, r.id;

-- 2) 마이그레이션 후 change_log 확인
select
  reservation_id,
  complex_id::text,
  old_reservation_number,
  new_reservation_number,
  reservation_created_at,
  recorded_at
from public.reservation_number_change_log
where migration_batch = 'created_at_baseline_20260631900000'
order by reservation_created_at, reservation_id;

-- 3) 번호가 바뀐 건만
select *
from public.reservation_number_change_log
where migration_batch = 'created_at_baseline_20260631900000'
  and old_reservation_number is distinct from new_reservation_number
order by reservation_created_at;
