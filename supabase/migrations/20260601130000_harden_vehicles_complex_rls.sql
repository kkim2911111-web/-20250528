-- ============================================================
-- 1단계: vehicles RLS 단지 격리 강화 (complex_id)
-- Supabase SQL Editor → Run (또는 supabase db push)
-- ============================================================
-- 목표
--   • 승인된 입주민(residents.approved) → 본인 complex_id 차량만 SELECT
--   • 승인된 지점 관리자(staff_users.approved) → 본인 단지 차량 CRUD
--   • 타 단지 차량 · complex_id NULL 차량 → authenticated 에게 절대 노출 안 됨
--   • 입주민/관리자 외 역할 → vehicles 접근 불가
-- ============================================================

-- ── 0) 스키마 보정 ──────────────────────────────────────────
alter table public.vehicles
  add column if not exists complex_id uuid references public.complexes(id) on delete restrict;

-- complex_id 없는 차량 진단 (있으면 수동 매핑 후 재실행)
do $$
declare
  v_orphan_count bigint;
begin
  select count(*) into v_orphan_count
  from public.vehicles
  where complex_id is null;

  if v_orphan_count > 0 then
    raise notice 'WARNING: complex_id 가 NULL 인 차량 %대 — RLS 적용 전 단지 연결 필요', v_orphan_count;
    raise notice '  select id, model_name, complex_id from public.vehicles where complex_id is null;';
  end if;
end $$;

-- NOT NULL (NULL row 가 남아 있으면 실패 → orphan 먼저 처리)
alter table public.vehicles
  alter column complex_id set not null;

create index if not exists vehicles_complex_id_idx
  on public.vehicles (complex_id);

create index if not exists vehicles_available_idx
  on public.vehicles (complex_id, is_available);

-- ── 1) RLS 강제 활성화 ────────────────────────────────────
alter table public.vehicles enable row level security;
alter table public.vehicles force row level security;

-- ── 2) 기존·위험 정책 제거 (permissive public 정책 포함) ──
drop policy if exists "vehicles_select_own_complex" on public.vehicles;
drop policy if exists "vehicles_resident_select_own_complex" on public.vehicles;
drop policy if exists "vehicles_staff_manage" on public.vehicles;
drop policy if exists "vehicles_staff_select" on public.vehicles;
drop policy if exists "vehicles_staff_insert" on public.vehicles;
drop policy if exists "vehicles_staff_update" on public.vehicles;
drop policy if exists "vehicles_staff_delete" on public.vehicles;
drop policy if exists "vehicles_select_all" on public.vehicles;
drop policy if exists "vehicles_public_read" on public.vehicles;
drop policy if exists "Enable read access for all users" on public.vehicles;
drop policy if exists "Enable read for authenticated users only" on public.vehicles;

-- ── 3) 입주민: 본인 단지 차량 SELECT 만 ───────────────────
create policy "vehicles_resident_select_own_complex"
on public.vehicles
for select
to authenticated
using (
  exists (
    select 1
    from public.residents r
    where r.user_id = auth.uid()
      and r.approved = true
      and r.complex_id is not null
      and r.complex_id = vehicles.complex_id
  )
);

-- ── 4) 지점 관리자: 본인 단지 차량 CRUD ───────────────────
create policy "vehicles_staff_select"
on public.vehicles
for select
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = vehicles.complex_id
  )
);

create policy "vehicles_staff_insert"
on public.vehicles
for insert
to authenticated
with check (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = vehicles.complex_id
  )
);

create policy "vehicles_staff_update"
on public.vehicles
for update
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = vehicles.complex_id
  )
)
with check (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = vehicles.complex_id
  )
);

create policy "vehicles_staff_delete"
on public.vehicles
for delete
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = vehicles.complex_id
  )
);

-- ── 5) RPC/앱 공용 — 차량이 내 단지 소속인지 검증 헬퍼 ─────
create or replace function public.is_vehicle_in_my_complex(p_vehicle_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.vehicles v
    join public.residents r on r.complex_id = v.complex_id
    where v.id::text = p_vehicle_id
      and r.user_id = auth.uid()
      and r.approved = true
  )
  or exists (
    select 1
    from public.vehicles v
    join public.staff_users s on s.complex_id = v.complex_id
    where v.id::text = p_vehicle_id
      and s.user_id = auth.uid()
      and s.approved = true
  );
$$;

revoke all on function public.is_vehicle_in_my_complex(text) from public;
grant execute on function public.is_vehicle_in_my_complex(text) to authenticated;

-- ============================================================
-- 6) 적용 확인 쿼리 (SQL Editor에서 실행)
-- ============================================================
--
-- A) RLS·정책 목록
-- select tablename, rowsecurity, forcerowsecurity
-- from pg_tables
-- where schemaname = 'public' and tablename = 'vehicles';
--
-- select policyname, cmd, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'public' and tablename = 'vehicles'
-- order by policyname;
--
-- 기대 정책 5개:
--   vehicles_resident_select_own_complex (SELECT)
--   vehicles_staff_select / insert / update / delete
--
-- B) orphan 차량 0건
-- select count(*) as orphan_vehicles from public.vehicles where complex_id is null;
--
-- C) 단지별 차량 수 (service role / SQL Editor)
-- select c.name, c.invite_code, count(v.id) as vehicle_count
-- from public.complexes c
-- left join public.vehicles v on v.complex_id = c.id
-- group by c.id, c.name, c.invite_code
-- order by c.name;
--
-- D) 입주민 JWT로 테스트 (앱 로그인 후 PostgREST 또는 아래 RPC)
--    → 본인 단지 count 만, 타 단지 0
-- select count(*) from public.vehicles;
--
-- E) 헬퍼 함수
-- select public.is_vehicle_in_my_complex('차량UUID'::text);
