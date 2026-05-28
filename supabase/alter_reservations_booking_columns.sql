-- ============================================================
-- reservations: booking_screen 연동 컬럼 추가 (스키마 자동 감지)
-- Supabase SQL Editor → Run
-- ============================================================
-- start_time/end_time 만 있는 DB, start_at/end_at 만 있는 DB 모두 지원
-- ============================================================

-- 1) booking_screen 필수 컬럼
alter table public.reservations
  add column if not exists start_time timestamptz;

alter table public.reservations
  add column if not exists end_time timestamptz;

alter table public.reservations
  add column if not exists total_price integer not null default 0;

-- total_price check (이미 있으면 skip)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reservations_total_price_nonneg'
  ) then
    alter table public.reservations
      add constraint reservations_total_price_nonneg
      check (total_price >= 0);
  end if;
exception when others then
  null;
end $$;

-- 2) 앱/RLS 호환용 start_at/end_at (없을 때만 추가)
alter table public.reservations
  add column if not exists start_at timestamptz;

alter table public.reservations
  add column if not exists end_at timestamptz;

-- 3) 양쪽 컬럼명 동기화 (있는 컬럼만 사용)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'start_at'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'start_time'
  ) then
    update public.reservations
    set
      start_time = coalesce(start_time, start_at),
      start_at = coalesce(start_at, start_time)
    where start_time is null or start_at is null;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'end_at'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'end_time'
  ) then
    update public.reservations
    set
      end_time = coalesce(end_time, end_at),
      end_at = coalesce(end_at, end_time)
    where end_time is null or end_at is null;
  end if;
end $$;

-- 4) 확인
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'reservations'
-- order by ordinal_position;
