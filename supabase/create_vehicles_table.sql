-- ============================================================
-- 단지카: vehicles 테이블 (Supabase SQL Editor에 붙여넣기)
-- ============================================================
-- 선행 조건: create_residents_table.sql 실행 완료
-- (complexes, residents, set_updated_at 함수 필요)
-- ============================================================

-- updated_at 함수 (create_residents_table.sql 미실행 시 대비)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 1) vehicles 테이블 생성
create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  complex_id uuid not null references public.complexes(id) on delete cascade,
  name text not null,
  vehicle_type text not null,
  price_per_hour integer not null default 0 check (price_per_hour >= 0),
  parking_location text,
  parking_photo_url text,
  car_number text,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) 컬럼 누락/불일치 보정 (이미 테이블이 있어도 안전)
alter table public.vehicles add column if not exists name text;
alter table public.vehicles add column if not exists vehicle_type text;
alter table public.vehicles add column if not exists price_per_hour integer not null default 0;
alter table public.vehicles add column if not exists parking_location text;
alter table public.vehicles add column if not exists parking_photo_url text;
alter table public.vehicles add column if not exists car_number text;
alter table public.vehicles add column if not exists is_available boolean not null default true;
alter table public.vehicles add column if not exists created_at timestamptz not null default now();
alter table public.vehicles add column if not exists updated_at timestamptz not null default now();

-- NOT NULL 제약 (nullable로 생성된 경우 보정)
update public.vehicles set name = '미등록' where name is null;
update public.vehicles set vehicle_type = '기타' where vehicle_type is null;
update public.vehicles set price_per_hour = 0 where price_per_hour is null;
update public.vehicles set is_available = true where is_available is null;

alter table public.vehicles alter column name set not null;
alter table public.vehicles alter column vehicle_type set not null;

-- car_number: nullable (번호 미등록 차량 허용)
alter table public.vehicles alter column car_number drop not null;

-- 3) 인덱스 / 트리거 / RLS
create index if not exists vehicles_complex_id_idx
  on public.vehicles (complex_id);

create index if not exists vehicles_available_idx
  on public.vehicles (complex_id, is_available);

drop trigger if exists vehicles_set_updated_at on public.vehicles;
create trigger vehicles_set_updated_at
before update on public.vehicles
for each row execute function public.set_updated_at();

alter table public.vehicles enable row level security;

drop policy if exists "vehicles_select_own_complex" on public.vehicles;
create policy "vehicles_select_own_complex"
on public.vehicles
for select to authenticated
using (
  exists (
    select 1
    from public.residents r
    where r.user_id = auth.uid()
      and r.approved = true
      and r.complex_id = vehicles.complex_id
  )
);

-- 4) 테스트 데이터 (DANJI2026 단지) — 중복 시 건너뜀
insert into public.vehicles (
  complex_id,
  model_name,
  vehicle_type,
  price_per_hour,
  parking_location,
  parking_photo_url,
  is_available
)
select
  c.id,
  v.model_name,
  v.vehicle_type,
  v.price_per_hour,
  v.parking_location,
  v.parking_photo_url,
  v.is_available
from public.complexes c
cross join (
  values
    (
      'BYD 아토3',
      '전기 SUV',
      8000,
      'B1-12',
      'https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=800&q=80',
      true
    ),
    (
      '더 뉴 스타리아',
      'MPV',
      12000,
      'B1-08',
      'https://images.unsplash.com/photo-1519641471654-76ce0107ad1b?w=800&q=80',
      true
    )
) as v(model_name, vehicle_type, price_per_hour, parking_location, parking_photo_url, is_available)
where c.invite_code = 'DANJI2026'
  and not exists (
    select 1
    from public.vehicles ve
    where ve.complex_id = c.id
      and ve.model_name = v.model_name
  );

-- 5) 확인 쿼리
-- select column_name, data_type, is_nullable
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'vehicles'
-- order by ordinal_position;
--
-- select name, vehicle_type, price_per_hour, parking_location, is_available
-- from public.vehicles;
