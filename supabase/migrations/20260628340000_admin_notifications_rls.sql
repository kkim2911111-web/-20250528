-- ============================================================
-- 관리자 앱내 알림 — complex_id + RLS (최고관리자·단지관리자)
-- ============================================================

alter table public.notifications
  add column if not exists complex_id uuid references public.complexes(id) on delete set null;

create index if not exists notifications_complex_created_idx
  on public.notifications (complex_id, created_at desc)
  where complex_id is not null;

comment on column public.notifications.complex_id is
  '관리자 알림 단지 (staff/super_admin 시나리오 insert 시 기록)';

-- 관리자 알림 type 판별 (admin_*, staff_* 시나리오)
create or replace function public.is_admin_notification_type(p_type text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_type, '') like 'admin%'
      or coalesce(p_type, '') like 'staff_%';
$$;

revoke all on function public.is_admin_notification_type(text) from public;
grant execute on function public.is_admin_notification_type(text) to authenticated;

-- 입주민: 본인 알림 (기존)
-- notifications_select_own 유지

-- 최고관리자: 본인 수신분 + 플랫폼 관리자 알림 전체 조회 (입주민 개인 알림 제외)
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
  and (
    user_id = auth.uid()
    or (
      public.is_admin_notification_type(type)
      and complex_id is not null
    )
  )
);

-- 단지관리자: 본인 수신분 + 담당 단지 관리자 알림 (단지 필터)
drop policy if exists "notifications_select_staff_complex" on public.notifications;
create policy "notifications_select_staff_complex"
on public.notifications
for select
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (
        notifications.user_id = auth.uid()
        or (
          notifications.complex_id = s.complex_id
          and public.is_admin_notification_type(notifications.type)
        )
      )
  )
);

-- 최고관리자: 본인 알림 읽음 처리
drop policy if exists "notifications_update_super_admin" on public.notifications;
create policy "notifications_update_super_admin"
on public.notifications
for update
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.user_id = auth.uid()
      and up.is_super_admin = true
  )
  and user_id = auth.uid()
)
with check (user_id = auth.uid());

-- 단지관리자: 본인 알림 읽음 처리 (complex_id 검증)
drop policy if exists "notifications_update_staff_complex" on public.notifications;
create policy "notifications_update_staff_complex"
on public.notifications
for update
to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (
        notifications.complex_id is null
        or notifications.complex_id = s.complex_id
      )
  )
)
with check (user_id = auth.uid());
