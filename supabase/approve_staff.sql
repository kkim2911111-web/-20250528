-- ============================================================
-- 지점 관리자 승인 (Supabase SQL Editor → Run)
-- ============================================================

-- 1) 승인 대기 목록
select
  s.user_id,
  u.email,
  s.display_name,
  s.approved,
  c.name as complex_name,
  c.admin_invite_code,
  s.created_at
from public.staff_users s
left join auth.users u on u.id = s.user_id
left join public.complexes c on c.id = s.complex_id
order by s.created_at desc;

-- 2) 이메일로 승인 (이메일을 실제 값으로 바꾸세요)
-- update public.staff_users s
-- set approved = true
-- from auth.users u
-- where s.user_id = u.id
--   and u.email = 'admin@example.com';

-- 3) user_id(UUID)로 승인
-- update public.staff_users
-- set approved = true
-- where user_id = 'YOUR-USER-UUID-HERE';
