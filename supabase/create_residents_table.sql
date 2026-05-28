-- ============================================================
-- 단지카: residents 테이블 생성 (Supabase SQL Editor에 붙여넣기)
-- ============================================================
-- 실행 순서:
--   1) 이 파일 (create_residents_table.sql)
--   2) lookup_complex_by_invite_code.sql
-- 이미 1)만 실행했다면 harden_residents_approved_rls.sql 도 실행 가능
-- ============================================================

-- 1) complexes 테이블 (residents가 참조하므로 먼저 생성)
create table if not exists public.complexes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text,
  created_at timestamptz not null default now()
);

create unique index if not exists complexes_invite_code_uniq
  on public.complexes (invite_code)
  where invite_code is not null;

-- 2) residents 테이블 (앱 코드와 동일한 컬럼명)
create table if not exists public.residents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  complex_id uuid not null references public.complexes(id) on delete restrict,
  building text,
  unit text,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists residents_complex_id_idx
  on public.residents (complex_id);

create index if not exists residents_approved_idx
  on public.residents (approved);

-- updated_at 자동 갱신
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists residents_set_updated_at on public.residents;
create trigger residents_set_updated_at
before update on public.residents
for each row execute function public.set_updated_at();

-- 3) RLS 활성화
alter table public.complexes enable row level security;
alter table public.residents enable row level security;

-- complexes: 로그인 사용자 조회 허용 (초대코드 RPC 쓰면 select 차단해도 됨)
drop policy if exists "complexes_select_authenticated" on public.complexes;
create policy "complexes_select_authenticated"
on public.complexes
for select to authenticated
using (true);

-- residents: 본인 row만 SELECT
drop policy if exists "residents_select_own" on public.residents;
create policy "residents_select_own"
on public.residents
for select to authenticated
using (user_id = auth.uid());

-- residents: 본인 row만 INSERT (approved=false만 허용, 자가 승인 방지)
drop policy if exists "residents_insert_own" on public.residents;
create policy "residents_insert_own"
on public.residents
for insert to authenticated
with check (user_id = auth.uid() and approved = false);

-- residents: 본인 row만 UPDATE (approved 값 변경 불가)
drop policy if exists "residents_update_own" on public.residents;
create policy "residents_update_own"
on public.residents
for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and approved = (
    select r.approved
    from public.residents r
    where r.user_id = auth.uid()
  )
);

-- 4) (선택) 테스트용 단지 1개 + 초대코드
-- 이미 있으면 건너뜀
insert into public.complexes (name, invite_code)
select '테스트 아파트 단지', 'DANJI2026'
where not exists (
  select 1 from public.complexes where invite_code = 'DANJI2026'
);

-- ============================================================
-- 관리자 승인 예시 (Supabase Table Editor 또는 SQL)
-- update public.residents set approved = true where user_id = 'USER_UUID';
-- ============================================================
