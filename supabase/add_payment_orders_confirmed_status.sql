-- ============================================================
-- [구버전] payment_orders confirmed 상태 추가
-- → fix_payment_orders_status_check.sql 사용 권장
-- 결제 완료 status = paid (confirmed 아님)
-- ============================================================

alter table public.payment_orders
  add column if not exists has_payment_key boolean default false;

-- fix_payment_orders_status_check.sql 로 대체
