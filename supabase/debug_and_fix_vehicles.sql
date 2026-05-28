-- ============================================================
-- 차량이 앱에 안 보일 때: 원인 확인 + 수정 (SQL Editor → Run)
-- ============================================================

-- 1) 내 입주민 / 단지 연결 확인
select
  u.email,
  r.approved,
  r.complex_id as my_complex_id,
  c.name as complex_name,
  c.invite_code
from public.residents r
join auth.users u on u.id = r.user_id
left join public.complexes c on c.id = r.complex_id
order by r.created_at desc;

-- 2) 단지별 차량 수 (complex_id 불일치 여부 확인)
select
  c.invite_code,
  c.name,
  c.id as complex_id,
  count(v.id) as vehicle_count
from public.complexes c
left join public.vehicles v on v.complex_id = c.id
group by c.id, c.invite_code, c.name
order by c.invite_code;

-- 3) complex_id 없는 차량 (있으면 문제)
select id, model_name, complex_id
from public.vehicles
where complex_id is null;

-- 4) RLS 정책 확인 (vehicles_select_own_complex 있어야 함)
select policyname, cmd, qual
from pg_policies
where schemaname = 'public' and tablename = 'vehicles';

-- ============================================================
-- 5) 수정: DANJI2026 단지 차량 complex_id 맞추기 + RLS 재적용
-- ============================================================
alter table public.vehicles enable row level security;

drop policy if exists "vehicles_select_own_complex" on public.vehicles;
create policy "vehicles_select_own_complex"
on public.vehicles
for select to authenticated
using (
  exists (
    select 1
    from public.residents r
    where r.user_id = auth.uid()
      and r.approved = true
      and r.complex_id = vehicles.complex_id
  )
);

-- complex_id가 비어 있는 차량 → DANJI2026 단지로 연결
update public.vehicles v
set complex_id = c.id
from public.complexes c
where c.invite_code = 'DANJI2026'
  and v.complex_id is null;

-- 6) 테스트 차량 없으면 seed_vehicles_test_data.sql 실행 후 아래로 확인
-- select * from public.vehicles
-- where complex_id = (select id from public.complexes where invite_code = 'DANJI2026');
