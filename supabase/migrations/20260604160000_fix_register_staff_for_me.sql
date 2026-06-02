-- register_staff_for_me 실패 수정
-- 1) complexes.admin_invite_code 백필
-- 2) auth.users 직접 조회 제거 (권한 오류 방지) → auth.jwt() 이메일
-- 3) 초대코드 공백 제거 후 대소문자 무시 비교
-- 4) EXECUTE 권한 재부여

alter table public.complexes
  add column if not exists admin_invite_code text;

-- 단지별 관리자 초대코드 없으면 기본값 (DANJI2026 단지 우선, 없으면 전체)
update public.complexes
set admin_invite_code = 'ADMIN-DANJI2026'
where invite_code = 'DANJI2026'
  and (admin_invite_code is null or trim(admin_invite_code) = '');

update public.complexes
set admin_invite_code = 'ADMIN-DANJI2026'
where admin_invite_code is null
  and not exists (
    select 1 from public.complexes c2 where c2.admin_invite_code = 'ADMIN-DANJI2026'
  );

create unique index if not exists complexes_admin_invite_code_uniq
  on public.complexes (admin_invite_code)
  where admin_invite_code is not null;

alter table public.user_profiles
  add column if not exists role text not null default 'resident';

alter table public.user_profiles
  drop constraint if exists user_profiles_role_check;

alter table public.user_profiles
  add constraint user_profiles_role_check
  check (role in ('resident', 'admin'));

create or replace function public.normalize_admin_invite_code(p_code text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));
$$;

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
  v_code text;
  v_name text := nullif(trim(p_display_name), '');
  v_email text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_name is null then
    raise exception 'invalid_display_name';
  end if;

  v_code := public.normalize_admin_invite_code(p_admin_invite_code);
  if v_code is null or v_code = '' then
    raise exception 'invalid_admin_invite_code';
  end if;

  if exists (select 1 from public.staff_users where user_id = v_user) then
    raise exception 'staff_already_registered';
  end if;

  select c.id, c.name
  into v_complex_id, v_complex_name
  from public.complexes c
  where public.normalize_admin_invite_code(c.admin_invite_code) = v_code
  limit 1;

  if v_complex_id is null then
    raise exception 'admin_invite_not_found'
      using hint = format(
        '입력코드=%s. complexes.admin_invite_code 확인 (기본 ADMIN-DANJI2026)',
        v_code
      );
  end if;

  v_email := coalesce(auth.jwt() ->> 'email', '');

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
    nullif(v_email, ''),
    'admin',
    true,
    now()
  )
  on conflict (user_id) do update
  set
    full_name = excluded.full_name,
    email = coalesce(nullif(excluded.email, ''), public.user_profiles.email),
    role = 'admin',
    signup_completed = true,
    updated_at = now();

  return jsonb_build_object(
    'userId', v_user,
    'complexId', v_complex_id,
    'complexName', v_complex_name,
    'displayName', v_name,
    'approved', false,
    'role', 'admin',
    'matchedInviteCode', v_code
  );
exception
  when undefined_table then
    raise exception 'schema_missing: staff_users 또는 user_profiles 테이블이 없습니다. create_admin_staff.sql 실행 필요';
  when undefined_column then
    raise exception 'column_missing: complexes.admin_invite_code 또는 user_profiles.role 컬럼 확인';
end;
$$;

revoke all on function public.register_staff_for_me(text, text) from public;
grant execute on function public.register_staff_for_me(text, text) to authenticated;

-- 진단용 (SQL Editor에서 실행)
-- select id, name, invite_code, admin_invite_code from public.complexes;
-- select public.normalize_admin_invite_code('ADMIN-DANJI2026');
