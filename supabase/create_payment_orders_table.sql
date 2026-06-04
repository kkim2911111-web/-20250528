-- ============================================================
-- payment_orders (Supabase 실제 구조 기준)
-- Supabase SQL Editor → Run
-- ============================================================

create table if not exists public.payment_orders (
  id uuid primary key default gen_random_uuid(),
  order_id text,
  user_id uuid references auth.users(id) on delete cascade,
  vehicle_id text,
  vehicle_name text,
  start_time timestamptz,
  end_time timestamptz,
  total_price integer,
  status text default 'pending',
  payment_key text,
  reservation_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  has_payment_key boolean default false
);

alter table public.payment_orders drop constraint if exists payment_orders_status_check;
alter table public.payment_orders add constraint payment_orders_status_check
  check (status in ('pending', 'paid', 'failed', 'cancelled'));

create unique index if not exists payment_orders_order_id_key
  on public.payment_orders (order_id);

create index if not exists payment_orders_user_id_idx
  on public.payment_orders (user_id);

create index if not exists payment_orders_status_idx
  on public.payment_orders (status);

alter table public.payment_orders enable row level security;

drop policy if exists "payment_orders_select_own" on public.payment_orders;
create policy "payment_orders_select_own"
on public.payment_orders for select to authenticated
using (user_id = auth.uid());

-- 제약 확인:
-- select conname, pg_get_constraintdef(oid)
-- from pg_constraint
-- where conrelid = 'public.payment_orders'::regclass
--   and conname = 'payment_orders_status_check';
