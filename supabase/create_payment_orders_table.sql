-- ============================================================
-- 결제 대기 주문 (토스페이먼츠 연동)
-- Supabase SQL Editor → Run
-- ============================================================

create table if not exists public.payment_orders (
  id uuid primary key default gen_random_uuid(),
  order_id text not null unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  vehicle_id text not null,
  vehicle_name text,
  start_time timestamptz not null,
  end_time timestamptz not null,
  total_price integer not null check (total_price > 0),
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'failed', 'cancelled')),
  payment_key text,
  reservation_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payment_orders_user_id_idx
  on public.payment_orders (user_id);

create index if not exists payment_orders_status_idx
  on public.payment_orders (status);

alter table public.payment_orders enable row level security;

drop policy if exists "payment_orders_select_own" on public.payment_orders;
create policy "payment_orders_select_own"
on public.payment_orders for select to authenticated
using (user_id = auth.uid());

-- insert/update는 Supabase Edge Function(service role)에서 처리

alter table public.reservations add column if not exists payment_key text;
alter table public.reservations add column if not exists order_id text;
alter table public.reservations add column if not exists payment_status text;
