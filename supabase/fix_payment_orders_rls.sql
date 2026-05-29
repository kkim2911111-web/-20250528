-- ============================================================
-- payment_orders RLS 보완 (결제 완료 후 클라이언트 fallback)
-- Supabase SQL Editor → Run
-- ============================================================

alter table public.payment_orders enable row level security;

drop policy if exists "payment_orders_update_own" on public.payment_orders;
create policy "payment_orders_update_own"
on public.payment_orders for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- 오래된 pending 주문 정리 (선택 — 24시간 지난 pending)
-- delete from public.payment_orders
-- where status = 'pending'
--   and payment_key is null
--   and created_at < now() - interval '24 hours';
