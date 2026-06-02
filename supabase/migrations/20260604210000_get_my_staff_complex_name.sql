-- 관리자: complexes RLS·조인 실패 시 단지명(한글) 폴백

create or replace function public.get_my_staff_complex_name()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select c.name
  from public.staff_users s
  join public.complexes c on c.id = s.complex_id
  where s.user_id = auth.uid()
  limit 1;
$$;

revoke all on function public.get_my_staff_complex_name() from public;
grant execute on function public.get_my_staff_complex_name() to authenticated;
