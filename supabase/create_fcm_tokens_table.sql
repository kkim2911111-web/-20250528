-- ============================================================
-- FCM 푸시 토큰 저장
-- Supabase SQL Editor → Run
-- ============================================================

create table if not exists public.fcm_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'web',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists fcm_tokens_user_id_idx
  on public.fcm_tokens (user_id);

alter table public.fcm_tokens enable row level security;

drop policy if exists "fcm_tokens_select_own" on public.fcm_tokens;
create policy "fcm_tokens_select_own"
on public.fcm_tokens for select to authenticated
using (user_id = auth.uid());

drop policy if exists "fcm_tokens_insert_own" on public.fcm_tokens;
create policy "fcm_tokens_insert_own"
on public.fcm_tokens for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "fcm_tokens_update_own" on public.fcm_tokens;
create policy "fcm_tokens_update_own"
on public.fcm_tokens for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "fcm_tokens_delete_own" on public.fcm_tokens;
create policy "fcm_tokens_delete_own"
on public.fcm_tokens for delete to authenticated
using (user_id = auth.uid());

-- 클라이언트에서 토큰 upsert
create or replace function public.upsert_fcm_token(
  p_token text,
  p_platform text default 'web'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'invalid_token';
  end if;

  insert into public.fcm_tokens (user_id, token, platform, updated_at)
  values (auth.uid(), trim(p_token), coalesce(nullif(trim(p_platform), ''), 'web'), now())
  on conflict (user_id, token)
  do update set
    platform = excluded.platform,
    updated_at = now();
end;
$$;

revoke all on function public.upsert_fcm_token(text, text) from public;
grant execute on function public.upsert_fcm_token(text, text) to authenticated;
