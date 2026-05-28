-- ============================================================
-- 단지카: reservations 테이블 (Supabase SQL Editor에 붙여넣기)
-- ============================================================
-- 선행 조건:
--   create_residents_table.sql
--   create_vehicles_table.sql (또는 vehicles 테이블 존재)
-- ============================================================

-- updated_at 함수 (없으면 생성)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 1) reservations 테이블
create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),

  -- 예약한 사용자 (auth.uid()와 동일)
  user_id uuid not null references auth.users(id) on delete cascade,

  -- 예약 차량 (단지카 앱 연동용 — 어떤 차량인지 식별)
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,

  -- 예약 시작/종료 시각
  start_at timestamptz not null,
  end_at timestamptz not null,

  -- booking_screen 연동 컬럼 (start_at/end_at 과 동일 값 저장)
  start_time timestamptz,
  end_time timestamptz,
  total_price integer not null default 0 check (total_price >= 0),

  -- 상태: pending(대기) | confirmed(확정)
  status text not null default 'pending'
    check (status in ('pending', 'confirmed')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint reservations_end_after_start
    check (end_at > start_at)
);

-- 2) 인덱스
create index if not exists reservations_user_id_idx
  on public.reservations (user_id);

create index if not exists reservations_vehicle_id_idx
  on public.reservations (vehicle_id);

create index if not exists reservations_status_start_idx
  on public.reservations (status, start_at);

create index if not exists reservations_vehicle_time_idx
  on public.reservations (vehicle_id, start_at, end_at);

-- 3) updated_at 자동 갱신
drop trigger if exists reservations_set_updated_at on public.reservations;
create trigger reservations_set_updated_at
before update on public.reservations
for each row execute function public.set_updated_at();

-- 4) 확정(confirmed) 예약끼리 시간 겹침 방지
create extension if not exists btree_gist;

alter table public.reservations
  drop constraint if exists reservations_no_overlap_confirmed;

alter table public.reservations
  add constraint reservations_no_overlap_confirmed
  exclude using gist (
    vehicle_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  )
  where (status = 'confirmed');

-- 5) RLS
alter table public.reservations enable row level security;

-- 본인 예약만 조회
drop policy if exists "reservations_select_own" on public.reservations;
create policy "reservations_select_own"
on public.reservations
for select to authenticated
using (user_id = auth.uid());

-- 같은 단지 차량의 모든 예약 조회 (중복 체크·캘린더용)
drop policy if exists "reservations_select_same_complex" on public.reservations;
create policy "reservations_select_same_complex"
on public.reservations
for select to authenticated
using (
  exists (
    select 1
    from public.vehicles v
    join public.residents r on r.complex_id = v.complex_id
    where v.id = reservations.vehicle_id
      and r.user_id = auth.uid()
      and r.approved = true
  )
);

-- 승인된 입주민만 예약 생성 (본인 user_id만)
drop policy if exists "reservations_insert_own" on public.reservations;
create policy "reservations_insert_own"
on public.reservations
for insert to authenticated
with check (
  user_id = auth.uid()
  and status = 'pending'
  and exists (
    select 1
    from public.residents r
    where r.user_id = auth.uid()
      and r.approved = true
  )
  and exists (
    select 1
    from public.vehicles v
    join public.residents r on r.complex_id = v.complex_id
    where v.id = vehicle_id
      and r.user_id = auth.uid()
      and r.approved = true
  )
);

-- 본인 예약만 수정 (상태 변경은 앱/관리자 정책에 맞게 확장 가능)
drop policy if exists "reservations_update_own" on public.reservations;
create policy "reservations_update_own"
on public.reservations
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- 본인 pending 예약만 삭제(취소)
drop policy if exists "reservations_delete_own_pending" on public.reservations;
create policy "reservations_delete_own_pending"
on public.reservations
for delete to authenticated
using (user_id = auth.uid() and status = 'pending');

-- ============================================================
-- 확인 쿼리
-- select column_name, data_type, is_nullable
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'reservations'
-- order by ordinal_position;
-- ============================================================
