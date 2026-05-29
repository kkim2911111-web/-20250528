-- ============================================================
-- 마이페이지: user_profiles 테이블
-- Supabase SQL Editor → Run
-- ============================================================

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  email text,
  address text,
  license_number text,
  license_expiry text,
  payment_card_registered boolean not null default false,
  payment_card_last4 text,
  points integer not null default 0 check (points >= 0),
  coupon_count integer not null default 0 check (coupon_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own"
on public.user_profiles for select to authenticated
using (user_id = auth.uid());

drop policy if exists "user_profiles_insert_own" on public.user_profiles;
create policy "user_profiles_insert_own"
on public.user_profiles for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "user_profiles_update_own" on public.user_profiles;
create policy "user_profiles_update_own"
on public.user_profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
