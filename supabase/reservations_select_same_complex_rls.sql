-- ============================================================
-- 중복 예약 체크용 RLS (이미 create_reservations_table.sql 실행한 DB)
-- ============================================================
-- 같은 단지 입주민이 해당 차량의 기존 예약을 조회할 수 있어야
-- 앱에서 시간 겹침 확인이 가능합니다.
-- ============================================================

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
