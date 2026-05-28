-- ============================================================
-- reservations: 대여·반납 컬럼 및 status 확장
-- Supabase SQL Editor → Run
-- ============================================================

-- 1) 대여·반납 컬럼
alter table public.reservations
  add column if not exists rental_started_at timestamptz;

alter table public.reservations
  add column if not exists returned_at timestamptz;

alter table public.reservations
  add column if not exists pickup_photos text[] default '{}';

alter table public.reservations
  add column if not exists return_photos text[] default '{}';

alter table public.reservations
  add column if not exists mileage_start integer;

alter table public.reservations
  add column if not exists mileage_end integer;

alter table public.reservations
  add column if not exists fuel_level_start text;

alter table public.reservations
  add column if not exists fuel_level_end text;

alter table public.reservations
  add column if not exists is_accident boolean not null default false;

alter table public.reservations
  add column if not exists accident_note text;

-- 2) status 값 확장: pending | confirmed | in_use | returned | completed
alter table public.reservations
  drop constraint if exists reservations_status_check;

alter table public.reservations
  add constraint reservations_status_check
  check (status in ('pending', 'confirmed', 'in_use', 'returned', 'completed'));

-- 3) 주유상태 check
alter table public.reservations
  drop constraint if exists reservations_fuel_level_start_check;

alter table public.reservations
  add constraint reservations_fuel_level_start_check
  check (
    fuel_level_start is null
    or fuel_level_start in ('full', '3quarter', 'half', 'quarter', 'empty')
  );

alter table public.reservations
  drop constraint if exists reservations_fuel_level_end_check;

alter table public.reservations
  add constraint reservations_fuel_level_end_check
  check (
    fuel_level_end is null
    or fuel_level_end in ('full', '3quarter', 'half', 'quarter', 'empty')
  );

-- 4) 사진 최대 10장
alter table public.reservations
  drop constraint if exists reservations_pickup_photos_max;

alter table public.reservations
  add constraint reservations_pickup_photos_max
  check (pickup_photos is null or cardinality(pickup_photos) <= 10);

alter table public.reservations
  drop constraint if exists reservations_return_photos_max;

alter table public.reservations
  add constraint reservations_return_photos_max
  check (return_photos is null or cardinality(return_photos) <= 10);

-- 5) 시간 겹침 gist 제약은 vehicle_id 타입(bigint/uuid)에 따라 오류가 날 수 있어
--    이 마이그레이션에서는 수정하지 않습니다.
--    겹침 검사는 prepare_payment_order / finalize_reservation_after_payment RPC에서 처리됩니다.

-- 6) 확인
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'reservations'
-- order by ordinal_position;
