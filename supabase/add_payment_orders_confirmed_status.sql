-- ============================================================
-- payment_orders: confirmed 상태 + has_payment_key 컬럼
-- Supabase SQL Editor → Run
-- ============================================================

alter table public.payment_orders
  add column if not exists has_payment_key boolean not null default false;

alter table public.payment_orders drop constraint if exists payment_orders_status_check;
alter table public.payment_orders add constraint payment_orders_status_check
  check (status in ('pending', 'paid', 'confirmed', 'failed', 'cancelled'));

-- 기존 paid + payment_key → confirmed 마이그레이션 (선택)
update public.payment_orders
set
  status = 'confirmed',
  has_payment_key = true
where status = 'paid'
  and payment_key is not null
  and payment_key <> '';
