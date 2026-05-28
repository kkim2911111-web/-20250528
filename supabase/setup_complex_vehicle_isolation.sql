-- ============================================================
-- 아파트1 / 아파트2 단지별 차량 격리 설정 + 진단
-- Supabase SQL Editor → Run
-- ============================================================
-- vehicles 테이블은 model_name 컬럼 사용 (name 없음)
-- ============================================================

-- 0) 컬럼 보정 (진단/insert 전에 먼저 실행)
alter table public.vehicles add column if not exists complex_id uuid references public.complexes(id);
alter table public.vehicles add column if not exists model_name text;
alter table public.vehicles add column if not exists vehicle_type text;
alter table public.vehicles add column if not exists hourly_rate integer;
alter table public.vehicles add column if not exists price_per_hour integer;
alter table public.vehicles add column if not exists parking_location text;
alter table public.vehicles add column if not exists is_active boolean default true;
alter table public.vehicles add column if not exists is_available boolean default true;

-- ── 1) 진단: 입주민 ↔ 단지 ↔ 차량 매칭 ──
select
  u.email,
  r.approved,
  c.name as complex_name,
  c.invite_code,
  r.complex_id as resident_complex_id,
  (
    select count(*)
    from public.vehicles v
    where v.complex_id = r.complex_id
  ) as vehicles_in_my_complex
from public.residents r
join auth.users u on u.id = r.user_id
left join public.complexes c on c.id = r.complex_id
order by c.name, u.email;

-- ── 2) 단지별 차량 수 ──
select
  c.name,
  c.invite_code,
  c.id as complex_id,
  count(v.id) as vehicle_count
from public.complexes c
left join public.vehicles v on v.complex_id = c.id
group by c.id, c.name, c.invite_code
order by c.name;

-- ── 3) complex_id 없는 차량 ──
select id, model_name, complex_id
from public.vehicles
where complex_id is null;

-- ============================================================
-- 4) 아파트1 / 아파트2 단지 (초대코드 APT1, APT2)
-- ============================================================
insert into public.complexes (name, invite_code)
select '아파트1', 'APT1'
where not exists (select 1 from public.complexes where invite_code = 'APT1');

insert into public.complexes (name, invite_code)
select '아파트2', 'APT2'
where not exists (select 1 from public.complexes where invite_code = 'APT2');

-- ============================================================
-- 5) RLS: 승인된 입주민 → 자기 단지 차량만
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

-- ============================================================
-- 6) 아파트1·2 테스트 차량 (model_name 기준, 없을 때만 insert)
-- ============================================================
do $$
declare
  v_apt1 uuid;
  v_apt2 uuid;
begin
  select id into v_apt1 from public.complexes where invite_code = 'APT1' limit 1;
  select id into v_apt2 from public.complexes where invite_code = 'APT2' limit 1;

  if v_apt1 is not null then
    insert into public.vehicles (complex_id, model_name, vehicle_type, hourly_rate, parking_location, is_active)
    select v_apt1, 'BYD 아토3', '전기 SUV', 8000, 'B1-12', true
    where not exists (
      select 1 from public.vehicles where complex_id = v_apt1 and model_name = 'BYD 아토3'
    );

    insert into public.vehicles (complex_id, model_name, vehicle_type, hourly_rate, parking_location, is_active)
    select v_apt1, '더 뉴 스타리아', 'MPV', 12000, 'B1-08', true
    where not exists (
      select 1 from public.vehicles where complex_id = v_apt1 and model_name = '더 뉴 스타리아'
    );
  end if;

  if v_apt2 is not null then
    insert into public.vehicles (complex_id, model_name, vehicle_type, hourly_rate, parking_location, is_active)
    select v_apt2, '테슬라 모델3', '전기 세단', 9000, 'B2-05', true
    where not exists (
      select 1 from public.vehicles where complex_id = v_apt2 and model_name = '테슬라 모델3'
    );

    insert into public.vehicles (complex_id, model_name, vehicle_type, hourly_rate, parking_location, is_active)
    select v_apt2, '카니발', 'MPV', 11000, 'B2-03', true
    where not exists (
      select 1 from public.vehicles where complex_id = v_apt2 and model_name = '카니발'
    );
  end if;
end $$;

-- ── 7) 최종 확인 ──
select
  c.name as 단지,
  c.invite_code as 초대코드,
  v.model_name as 차량,
  v.complex_id
from public.complexes c
left join public.vehicles v on v.complex_id = c.id
where c.invite_code in ('APT1', 'APT2')
order by c.name, v.model_name;
