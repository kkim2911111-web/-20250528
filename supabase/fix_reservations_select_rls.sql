-- ============================================================
-- reservations SELECT RLS 재적용 (관리자·취소 기능 추가 후 목록 안 보일 때)
-- Supabase SQL Editor → Run
-- ============================================================

alter table public.reservations enable row level security;

-- 본인 예약 조회 (내 예약 목록 — 최우선)
drop policy if exists "reservations_select_own" on public.reservations;
create policy "reservations_select_own"
on public.reservations
for select to authenticated
using (user_id = auth.uid());

-- 같은 단지 차량 예약 조회 (중복 체크용)
drop policy if exists "reservations_select_same_complex" on public.reservations;
create policy "reservations_select_same_complex"
on public.reservations
for select to authenticated
using (
  exists (
    select 1
    from public.vehicles v
    join public.residents r on r.complex_id = v.complex_id
    where v.id = reservations.vehicle_id
      and r.user_id = auth.uid()
      and r.approved = true
  )
);

-- 관리자 — 지점 예약 조회 (create_admin_staff.sql 과 동일)
drop policy if exists "reservations_staff_select_complex" on public.reservations;
create policy "reservations_staff_select_complex"
on public.reservations
for select to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    join public.vehicles v on v.complex_id = s.complex_id
    where s.user_id = auth.uid()
      and s.approved = true
      and v.id = reservations.vehicle_id
  )
);

-- 확인: 본인 예약 건수
-- select count(*) from public.reservations where user_id = auth.uid();
