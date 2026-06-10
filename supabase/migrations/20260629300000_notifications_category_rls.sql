-- ============================================================
-- notifications — category 컬럼 + RLS (본인 SELECT, INSERT service_role)
-- ============================================================

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null default '',
  category text not null default 'user'
    check (category in ('admin', 'super_admin', 'user')),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- 기존 테이블( type 등 레거시 컬럼 보유 )에 category 추가
alter table public.notifications
  add column if not exists category text;

update public.notifications
set category = case
  when coalesce(type, '') like 'admin%' then 'super_admin'
  when coalesce(type, '') like 'staff_%' then 'admin'
  else 'user'
end
where category is null;

alter table public.notifications
  alter column category set default 'user';

update public.notifications
set category = 'user'
where category is null;

alter table public.notifications
  alter column category set not null;

alter table public.notifications
  drop constraint if exists notifications_category_check;

alter table public.notifications
  add constraint notifications_category_check
  check (category in ('admin', 'super_admin', 'user'));

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id, created_at desc)
  where is_read = false;

create index if not exists notifications_category_idx
  on public.notifications (category, created_at desc);

comment on table public.notifications is '앱내 알림함';
comment on column public.notifications.category is
  '수신 대상 역할 구분: admin | super_admin | user';

-- ── RLS ─────────────────────────────────────────────────────
alter table public.notifications enable row level security;

drop policy if exists "notifications_select_super_admin" on public.notifications;
drop policy if exists "notifications_select_staff_complex" on public.notifications;
drop policy if exists "notifications_update_super_admin" on public.notifications;
drop policy if exists "notifications_update_staff_complex" on public.notifications;
drop policy if exists "notifications_insert_service_role" on public.notifications;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications
for select
to authenticated
using (user_id = auth.uid());

-- 읽음 처리( is_read ) — 클라이언트 UPDATE
drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
on public.notifications
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- INSERT: service_role 전용 (Edge Function). authenticated/anon INSERT 금지
revoke insert on table public.notifications from anon;
revoke insert on table public.notifications from authenticated;
grant insert on table public.notifications to service_role;
