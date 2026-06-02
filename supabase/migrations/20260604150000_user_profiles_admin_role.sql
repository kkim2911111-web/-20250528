-- user_profiles.role 로 관리자/입주민 분기

alter table public.user_profiles
  add column if not exists role text not null default 'resident';

alter table public.user_profiles
  drop constraint if exists user_profiles_role_check;

alter table public.user_profiles
  add constraint user_profiles_role_check
  check (role in ('resident', 'admin'));

comment on column public.user_profiles.role is
  'resident: 입주민, admin: 지점 관리자';

-- 기존 staff_users → admin 역할 백필
update public.user_profiles up
set role = 'admin',
    signup_completed = true,
    updated_at = now()
from public.staff_users s
where s.user_id = up.user_id;

create or replace function public.register_staff_for_me(
  p_display_name text,
  p_admin_invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_complex_name text;
  v_code text := nullif(trim(p_admin_invite_code), '');
  v_name text := nullif(trim(p_display_name), '');
  v_email text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_name is null then
    raise exception 'invalid_display_name';
  end if;

  if v_code is null then
    raise exception 'invalid_admin_invite_code';
  end if;

  if exists (select 1 from public.staff_users where user_id = v_user) then
    raise exception 'staff_already_registered';
  end if;

  select c.id, c.name
  into v_complex_id, v_complex_name
  from public.complexes c
  where upper(c.admin_invite_code) = upper(v_code)
  limit 1;

  if v_complex_id is null then
    raise exception 'admin_invite_not_found';
  end if;

  select u.email into v_email from auth.users u where u.id = v_user;

  insert into public.staff_users (user_id, complex_id, display_name, approved)
  values (v_user, v_complex_id, v_name, false);

  insert into public.user_profiles (
    user_id,
    full_name,
    email,
    role,
    signup_completed,
    updated_at
  )
  values (
    v_user,
    v_name,
    v_email,
    'admin',
    true,
    now()
  )
  on conflict (user_id) do update
  set
    full_name = excluded.full_name,
    email = coalesce(excluded.email, public.user_profiles.email),
    role = 'admin',
    signup_completed = true,
    updated_at = now();

  return jsonb_build_object(
    'userId', v_user,
    'complexId', v_complex_id,
    'complexName', v_complex_name,
    'displayName', v_name,
    'approved', false,
    'role', 'admin'
  );
end;
$$;
