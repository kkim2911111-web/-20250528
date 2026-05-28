-- ============================================================
-- 입주민 승인 (Supabase SQL Editor에서 실행)
-- ============================================================
-- Table Editor에서 approved 체크만 해도 되지만,
-- user_id / complex_id 가 맞는지 먼저 확인하세요.
-- ============================================================

-- 1) 승인 대기 목록 확인
select
  r.user_id,
  u.email,
  r.building,
  r.unit,
  r.approved,
  c.name as complex_name,
  c.invite_code
from public.residents r
left join auth.users u on u.id = r.user_id
left join public.complexes c on c.id = r.complex_id
order by r.created_at desc;

-- 2) 이메일로 승인 (아래 이메일을 실제 값으로 바꾸세요)
-- update public.residents r
-- set approved = true
-- from auth.users u
-- where r.user_id = u.id
--   and u.email = 'kkim291@naver.com';

-- 3) user_id(UUID)로 승인
-- update public.residents
-- set approved = true
-- where user_id = 'YOUR-USER-UUID-HERE';
