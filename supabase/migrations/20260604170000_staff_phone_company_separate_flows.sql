-- 관리자(staff_users) / 입주민(user_profiles 온보딩) 플로우 분리
-- register_staff_for_me: staff_users만 갱신 (signup_completed·role admin 미설정)

alter table public.staff_users add column if not exists phone text;
alter table public.staff_users add column if not exists company_name text;

drop function if exists public.register_staff_for_me(text, text);

create or replace function public.register_staff_for_me(
  p_display_name text,
  p_admin_invite_code text,
  p_phone text default null,
  p_company_name text default null
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
  v_phone text := nullif(trim(p_phone), '');
  v_company text := nullif(trim(p_company_name), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_name is null then
    raise exception 'invalid_display_name';
  end if;

  if v_phone is null then
    raise exception 'invalid_phone';
  end if;

  if v_company is null then
    raise exception 'invalid_company_name';
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

  insert into public.staff_users (
    user_id,
    complex_id,
    display_name,
    phone,
    company_name,
    approved
  )
  values (v_user, v_complex_id, v_name, v_phone, v_company, false);

  return jsonb_build_object(
    'userId', v_user,
    'complexId', v_complex_id,
    'complexName', v_complex_name,
    'displayName', v_name,
    'phone', v_phone,
    'companyName', v_company,
    'approved', false,
    'role', 'branch_admin',
    'matchedInviteCode', v_code
  );
exception
  when undefined_table then
    raise exception 'schema_missing: staff_users 테이블이 없습니다. create_admin_staff.sql 실행 필요';
  when undefined_column then
    raise exception 'column_missing: staff_users.phone/company_name 또는 complexes.admin_invite_code 확인';
end;
$$;

revoke all on function public.register_staff_for_me(text, text, text, text) from public;
grant execute on function public.register_staff_for_me(text, text, text, text) to authenticated;
