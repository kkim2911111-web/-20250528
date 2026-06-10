-- notifications RLS — 본인 SELECT 유지 + 지점관리자(단지) + 최고관리자(전체)

alter table public.notifications
  add column if not exists complex_id uuid references public.complexes(id) on delete set null;

create index if not exists notifications_complex_created_idx
  on public.notifications (complex_id, created_at desc)
  where complex_id is not null;

comment on column public.notifications.complex_id is
  '알림 발생 단지 — 지점관리자 단지별 조회용';

alter table public.notifications enable row level security;

-- 입주민·수신자: 본인 알림
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications
for select
to authenticated
using (user_id = auth.uid());

-- 지점관리자: 승인된 staff + 동일 complex_id 알림 (같은 단지 이용자 알림 조회)
drop policy if exists "notifications_select_staff_complex" on public.notifications;
create policy "notifications_select_staff_complex"
on public.notifications
for select
to authenticated
using (
  notifications.complex_id is not null
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = notifications.complex_id
  )
);

-- 최고관리자: 전체 알림 조회
drop policy if exists "notifications_select_super_admin" on public.notifications;
create policy "notifications_select_super_admin"
on public.notifications
for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.user_id = auth.uid()
      and up.is_super_admin = true
  )
);
