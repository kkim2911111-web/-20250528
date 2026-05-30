-- ============================================================
-- payment_orders status 제약 정리 (실제 DB 기준)
-- Supabase SQL Editor → Run
-- 허용값: pending | paid | failed | cancelled
-- ============================================================

-- 구버전 confirmed → paid
update public.payment_orders
set status = 'paid', updated_at = now()
where status = 'confirmed';

alter table public.payment_orders drop constraint if exists payment_orders_status_check;

alter table public.payment_orders add constraint payment_orders_status_check
  check (status in ('pending', 'paid', 'failed', 'cancelled'));

-- has_payment_key 컬럼 없으면 추가
alter table public.payment_orders
  add column if not exists has_payment_key boolean default false;

-- 제약 확인 쿼리:
-- select conname, pg_get_constraintdef(oid)
-- from pg_constraint
-- where conrelid = 'public.payment_orders'::regclass
--   and conname = 'payment_orders_status_check';

-- finalize RPC 재배포: finalize_reservation_after_payment.sql 실행
