-- ============================================================
-- 결제됐지만 예약 없음 — 진단 + 복구 (SQL Editor → Run)
-- ============================================================

-- 1) 문제 주문 확인
select
  po.order_id,
  po.status,
  po.payment_key is not null as has_payment_key,
  po.vehicle_id,
  po.vehicle_name,
  po.total_price,
  po.start_time,
  po.end_time,
  u.email,
  r.id as reservation_id,
  (select c.data_type from information_schema.columns c
   where c.table_schema='public' and c.table_name='vehicles' and c.column_name='id') as vehicles_id_type,
  (select c.data_type from information_schema.columns c
   where c.table_schema='public' and c.table_name='reservations' and c.column_name='vehicle_id') as reservations_vehicle_id_type
from public.payment_orders po
left join auth.users u on u.id = po.user_id
left join public.reservations r on r.order_id = po.order_id
where po.status in ('failed', 'paid', 'pending')
order by po.created_at desc
limit 20;

-- 2) 진단 해석
--    status=pending + has_payment_key=false → 결제 완료 화면(/payment/success) 콜백 미실행
--    → 앱 Hot Restart 후 다시 결제하거나, 결제 완료 URL에서 [예약 저장 재시도]
--    status=failed/paid + reservation_id null → finalize_reservation_after_payment.sql 재실행 후 재시도

-- 3) 필수 SQL (아직 안 했다면 순서대로 Run)
--    fix_reservation_insert.sql
--    finalize_reservation_after_payment.sql
--    fix_payment_orders_rls.sql
-- select public.finalize_reservation_after_payment(
--   'PAYMENT_KEY',
--   'ORDER_ID',
--   8000,
--   'USER_UUID'::uuid
-- );
