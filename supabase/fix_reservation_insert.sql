-- ============================================================
-- 승인된 입주민 예약 insert 실패 수정 (SQL Editor → Run)
-- ============================================================

-- 1) reservations 컬럼 보정 (스키마 혼재 대비)
alter table public.reservations add column if not exists start_time timestamptz;
alter table public.reservations add column if not exists end_time timestamptz;
alter table public.reservations add column if not exists start_at timestamptz;
alter table public.reservations add column if not exists end_at timestamptz;
alter table public.reservations add column if not exists total_price integer not null default 0;
alter table public.reservations add column if not exists status text not null default 'pending';
alter table public.reservations add column if not exists vehicle_id uuid;
alter table public.reservations add column if not exists user_id uuid references auth.users(id);

-- vehicle_id가 bigint/serial 인 DB: reservations.vehicle_id 타입 확인
-- select column_name, data_type from information_schema.columns
-- where table_name = 'vehicles' and column_name = 'id';

-- 2) NOT NULL 완화 (insert 시 한쪽 시간 컬럼만 채워도 되게)
do $$
begin
  begin alter table public.reservations alter column start_at drop not null; exception when others then null; end;
  begin alter table public.reservations alter column end_at drop not null; exception when others then null; end;
  begin alter table public.reservations alter column start_time drop not null; exception when others then null; end;
  begin alter table public.reservations alter column end_time drop not null; exception when others then null; end;
end $$;

-- 3) RLS + insert 정책 재적용
alter table public.reservations enable row level security;

drop policy if exists "reservations_select_own" on public.reservations;
create policy "reservations_select_own"
on public.reservations for select to authenticated
using (user_id = auth.uid());

drop policy if exists "reservations_select_same_complex" on public.reservations;
create policy "reservations_select_same_complex"
on public.reservations for select to authenticated
using (
  exists (
    select 1 from public.vehicles v
    join public.residents r on r.complex_id = v.complex_id
    where v.id = reservations.vehicle_id
      and r.user_id = auth.uid()
      and r.approved = true
  )
);

drop policy if exists "reservations_insert_own" on public.reservations;
create policy "reservations_insert_own"
on public.reservations for insert to authenticated
with check (
  user_id = auth.uid()
  and coalesce(status, 'pending') = 'pending'
  and exists (
    select 1 from public.residents r
    where r.user_id = auth.uid()
      and r.approved = true
  )
  and exists (
    select 1 from public.vehicles v
    join public.residents r on r.complex_id = v.complex_id
    where v.id::text = vehicle_id::text
      and r.user_id = auth.uid()
      and r.approved = true
  )
);

-- 4) 진단: 승인 주민 + 차량 단지 매칭
select
  u.email,
  r.approved,
  c.name as my_complex,
  c.invite_code,
  v.id as vehicle_id,
  v.model_name,
  (r.complex_id = v.complex_id) as complex_match
from public.residents r
join auth.users u on u.id = r.user_id
join public.complexes c on c.id = r.complex_id
left join public.vehicles v on v.complex_id = r.complex_id
where r.approved = true
order by u.email, v.model_name;

-- 5) insert 정책 테스트 (특정 이메일 — 값 바꿔서 실행)
-- select
--   r.approved,
--   r.complex_id = v.complex_id as can_book
-- from public.residents r
-- join auth.users u on u.id = r.user_id
-- cross join public.vehicles v
-- where u.email = 'kkim291@naver.com'
--   and v.model_name = 'BYD 아토3';
