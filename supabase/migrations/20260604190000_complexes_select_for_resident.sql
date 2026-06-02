-- 입주민/관리자: 본인 단지(complex_id) complexes.name 조회 허용
-- (lookup_complex_by_invite_code 의 complexes_select_authenticated using(false) 와 병행)

drop policy if exists "complexes_select_own_resident" on public.complexes;
create policy "complexes_select_own_resident"
on public.complexes
for select
to authenticated
using (
  exists (
    select 1
    from public.residents r
    where r.user_id = auth.uid()
      and r.complex_id = complexes.id
  )
);

drop policy if exists "complexes_select_own_staff" on public.complexes;
create policy "complexes_select_own_staff"
on public.complexes
for select
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.complex_id = complexes.id
  )
);

-- RLS 미적용 DB·조인 실패 시 앱 폴백용
create or replace function public.get_my_resident_complex_name()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select c.name
  from public.residents r
  join public.complexes c on c.id = r.complex_id
  where r.user_id = auth.uid()
  limit 1;
$$;

revoke all on function public.get_my_resident_complex_name() from public;
grant execute on function public.get_my_resident_complex_name() to authenticated;
