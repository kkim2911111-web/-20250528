-- ============================================================
-- 단지카: residents.approved 자가 승인 방지 RLS 보강
-- ============================================================
-- 이미 create_residents_table.sql 을 실행한 DB에 적용
-- (신규 설치는 create_residents_table.sql 에 이미 반영됨)
--
-- 효과:
--   - 사용자는 approved = false 로만 가입/수정 가능
--   - approved 변경은 Supabase SQL Editor(service role)에서만 가능
-- ============================================================

alter table public.residents enable row level security;

drop policy if exists "residents_insert_own" on public.residents;
create policy "residents_insert_own"
on public.residents
for insert to authenticated
with check (user_id = auth.uid() and approved = false);

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

-- ============================================================
-- 관리자 승인 (Supabase SQL Editor에서 service role로 실행)
-- update public.residents
-- set approved = true
-- where user_id = 'USER_UUID_HERE';
-- ============================================================
