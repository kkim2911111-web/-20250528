-- 최고관리자 보강: 입주민 블랙리스트 조회, 공지 목록, 면허 강제 거절

drop function if exists public.get_super_admin_residents();

create or replace function public.get_super_admin_residents()
returns table (
  user_id uuid,
  complex_id uuid,
  complex_name text,
  building text,
  unit text,
  approved boolean,
  full_name text,
  phone text,
  email text,
  license_verified boolean,
  is_blacklisted boolean,
  created_at timestamptz
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
    res.user_id,
    res.complex_id,
    c.name as complex_name,
    res.building,
    res.unit,
    res.approved,
    up.full_name,
    up.phone,
    coalesce(up.email, au.email::text) as email,
    coalesce(up.license_verified, false) as license_verified,
    coalesce(up.is_blacklisted, false) as is_blacklisted,
    res.created_at
  from public.residents res
  join public.complexes c on c.id = res.complex_id
  left join public.user_profiles up on up.user_id = res.user_id
  left join auth.users au on au.id = res.user_id
  order by c.name asc nulls last, res.created_at desc;
end;
$$;

create or replace function public.get_super_admin_notices()
returns table (
  notice_id uuid,
  complex_id uuid,
  complex_name text,
  title text,
  content text,
  is_active boolean,
  is_global boolean,
  created_at timestamptz
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
    n.id as notice_id,
    n.complex_id,
    c.name as complex_name,
    n.title,
    n.content,
    n.is_active,
    (n.complex_id is null) as is_global,
    n.created_at
  from public.notices n
  left join public.complexes c on c.id = n.complex_id
  order by n.created_at desc;
end;
$$;

create or replace function public.force_super_admin_license_rejected(
  p_user_id uuid,
  p_reason text default '최고관리자 거절'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();
  update public.user_profiles
  set
    license_verified = false,
    license_status = 'rejected',
    license_rejection_reason = coalesce(nullif(trim(p_reason), ''), '최고관리자 거절'),
    license_verified_at = null,
    license_verified_by = null,
    updated_at = now()
  where user_id = p_user_id;
  if not found then
    raise exception 'profile_not_found';
  end if;
end;
$$;

revoke all on function public.get_super_admin_notices() from public;
grant execute on function public.get_super_admin_notices() to authenticated;

revoke all on function public.force_super_admin_license_rejected(uuid, text) from public;
grant execute on function public.force_super_admin_license_rejected(uuid, text) to authenticated;
