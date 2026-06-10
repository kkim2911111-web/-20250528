-- 최고관리자 스태프 — 담당 단지 사업자정보 조회 + 삭제 가드

drop function if exists public.get_super_admin_staff();

create or replace function public.get_super_admin_staff()
returns table (
  user_id uuid,
  complex_id uuid,
  complex_name text,
  display_name text,
  phone text,
  company_name text,
  approved boolean,
  email text,
  created_at timestamptz,
  business_name text,
  business_registration_number text,
  business_address text,
  business_representative text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();

  return query
  select
    s.user_id,
    s.complex_id,
    c.name as complex_name,
    s.display_name,
    s.phone,
    s.company_name,
    s.approved,
    coalesce(up.email, au.email::text) as email,
    s.created_at,
    c.business_name,
    c.business_registration_number,
    c.business_address,
    c.business_representative
  from public.staff_users s
  join public.complexes c on c.id = s.complex_id
  left join public.user_profiles up on up.user_id = s.user_id
  left join auth.users au on au.id = s.user_id
  order by c.name asc nulls last, s.display_name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_staff() from public;
grant execute on function public.get_super_admin_staff() to authenticated;

comment on function public.get_super_admin_staff() is
  '최고관리자 스태프 목록 (담당 단지 complexes 사업자정보 포함)';

-- 담당 단지 소속(동일 단지 유일 스태프) 시 삭제 차단
create or replace function public.delete_super_admin_staff(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
  v_peer_count integer;
begin
  perform public.assert_is_super_admin();

  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = p_user_id;

  if not found then
    raise exception 'staff_not_found';
  end if;

  if v_complex_id is not null then
    select count(*)::integer
    into v_peer_count
    from public.staff_users s
    where s.complex_id = v_complex_id;

    if v_peer_count <= 1 then
      raise exception 'staff_has_assigned_complex';
    end if;
  end if;

  delete from public.staff_users where user_id = p_user_id;
  if not found then
    raise exception 'staff_not_found';
  end if;
end;
$$;

revoke all on function public.delete_super_admin_staff(uuid) from public;
grant execute on function public.delete_super_admin_staff(uuid) to authenticated;

comment on function public.delete_super_admin_staff(uuid) is
  '최고관리자 스태프 삭제 — 담당 단지에 유일 스태프면 차단';
