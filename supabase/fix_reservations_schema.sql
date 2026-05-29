-- ============================================================
-- reservations 스키마 보정 (updated_at, door_unlocked 등)
-- Supabase SQL Editor → Run
-- ============================================================

alter table public.reservations
  add column if not exists updated_at timestamptz not null default now();

alter table public.reservations
  add column if not exists door_unlocked boolean not null default false;

-- updated_at 컬럼 없이 트리거만 있으면 UPDATE 오류 → 트리거 재생성
drop trigger if exists reservations_set_updated_at on public.reservations;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'updated_at'
  ) then
    create trigger reservations_set_updated_at
    before update on public.reservations
    for each row execute function public.set_updated_at();
  end if;
exception when others then
  null;
end $$;

alter table public.reservations
  add column if not exists start_at timestamptz;

alter table public.reservations
  add column if not exists end_at timestamptz;

alter table public.reservations
  add column if not exists start_time timestamptz;

alter table public.reservations
  add column if not exists end_time timestamptz;

-- start_at/end_at ↔ start_time/end_time 동기화
update public.reservations
set
  start_time = coalesce(start_time, start_at),
  start_at = coalesce(start_at, start_time),
  end_time = coalesce(end_time, end_at),
  end_at = coalesce(end_at, end_time)
where start_at is null
   or start_time is null
   or end_at is null
   or end_time is null;
