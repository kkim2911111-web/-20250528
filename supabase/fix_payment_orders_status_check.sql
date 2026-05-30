-- ============================================================
-- payment_orders status 제약 정리
-- Supabase SQL Editor → Run
-- 허용값: pending | paid | failed | cancelled
-- ============================================================

-- 구버전 confirmed → paid (결제 완료)
update public.payment_orders
set status = 'paid', updated_at = now()
where status = 'confirmed';

alter table public.payment_orders drop constraint if exists payment_orders_status_check;

alter table public.payment_orders add constraint payment_orders_status_check
  check (status in ('pending', 'paid', 'failed', 'cancelled'));

-- finalize RPC도 paid 사용 (finalize_reservation_after_payment.sql 재실행 권장)
