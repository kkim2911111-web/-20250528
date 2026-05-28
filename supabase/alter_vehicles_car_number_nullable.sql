-- ============================================================
-- vehicles.car_number NOT NULL → nullable 변경
-- Supabase SQL Editor에 붙여넣고 Run
-- ============================================================

alter table public.vehicles
  alter column car_number drop not null;

-- 확인
-- select column_name, is_nullable
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name = 'vehicles'
--   and column_name = 'car_number';
