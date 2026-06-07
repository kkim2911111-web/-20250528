-- ============================================================
-- 공지사항(notices) + 앱내 알림함(notifications)
-- ============================================================

-- ── 1) notices ──────────────────────────────────────────────
create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  complex_id uuid references public.complexes(id) on delete cascade,
  title text not null,
  content text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists notices_active_complex_created_idx
  on public.notices (is_active, complex_id, created_at desc)
  where is_active = true;

comment on table public.notices is '단지·전체 공지사항';
comment on column public.notices.complex_id is 'NULL이면 전체 단지 공지';

-- ── 2) notifications ────────────────────────────────────────
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null default '',
  type text not null default '',
  reservation_id text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id, created_at desc)
  where is_read = false;

comment on table public.notifications is '앱내 알림함 (푸시 발송 시 동시 저장)';

-- ── 3) RLS ──────────────────────────────────────────────────
alter table public.notices enable row level security;
alter table public.notifications enable row level security;

-- notices: 입주민 — 활성 공지 + (전체 또는 본인 단지)
drop policy if exists "notices_resident_select" on public.notices;
create policy "notices_resident_select"
on public.notices
for select
to authenticated
using (
  is_active = true
  and (
    complex_id is null
    or exists (
      select 1
      from public.residents r
      where r.user_id = auth.uid()
        and r.complex_id = notices.complex_id
    )
  )
);

-- notices: 관리자 — 본인 단지 + 전체 공지 조회·관리
drop policy if exists "notices_staff_select" on public.notices;
create policy "notices_staff_select"
on public.notices
for select
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (notices.complex_id is null or notices.complex_id = s.complex_id)
  )
);

drop policy if exists "notices_staff_insert" on public.notices;
create policy "notices_staff_insert"
on public.notices
for insert
to authenticated
with check (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (notices.complex_id is null or notices.complex_id = s.complex_id)
  )
);

drop policy if exists "notices_staff_update" on public.notices;
create policy "notices_staff_update"
on public.notices
for update
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (notices.complex_id is null or notices.complex_id = s.complex_id)
  )
)
with check (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (notices.complex_id is null or notices.complex_id = s.complex_id)
  )
);

drop policy if exists "notices_staff_delete" on public.notices;
create policy "notices_staff_delete"
on public.notices
for delete
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (notices.complex_id is null or notices.complex_id = s.complex_id)
  )
);

-- notifications: 본인 알림만 조회·읽음 처리 (insert는 service role / Edge Function)
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
on public.notifications
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
