-- register_staff_for_me / 초대코드 진단 (Supabase SQL Editor)

-- 1) RPC 함수 존재 여부
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'register_staff_for_me';

-- 2) complexes + 관리자 초대코드
select
  id,
  name,
  invite_code,
  admin_invite_code,
  public.normalize_admin_invite_code(admin_invite_code) as normalized_admin_code
from public.complexes
order by name;

-- 3) 입력 코드 매칭 시뮬레이션 (앱 기본값)
select id, name, admin_invite_code
from public.complexes
where public.normalize_admin_invite_code(admin_invite_code)
    = public.normalize_admin_invite_code('ADMIN-DANJI2026');

-- 4) staff_users / user_profiles 테이블
select count(*) as staff_count from public.staff_users;
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'user_profiles'
  and column_name in ('role', 'signup_completed');

-- 5) RPC 실행 권한
select grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name = 'register_staff_for_me';
