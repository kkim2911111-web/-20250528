-- FCM 토큰 — 로그아웃 시 본인·기기 토큰 삭제, 로그인 upsert 시 타 계정 동일 토큰 선삭제

create index if not exists fcm_tokens_token_idx
  on public.fcm_tokens (token);

create or replace function public.delete_my_fcm_tokens(
  p_token text default null
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

  if p_token is not null and length(trim(p_token)) > 0 then
    delete from public.fcm_tokens
    where user_id = auth.uid()
      and token = trim(p_token);
  else
    delete from public.fcm_tokens
    where user_id = auth.uid();
  end if;
end;
$$;

create or replace function public.upsert_fcm_token(
  p_token text,
  p_platform text default 'web'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text := trim(p_token);
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if v_token is null or length(v_token) = 0 then
    raise exception 'invalid_token';
  end if;

  -- 동일 기기 토큰이 다른 user_id에 남아 있으면 선삭제
  delete from public.fcm_tokens
  where token = v_token
    and user_id <> auth.uid();

  insert into public.fcm_tokens (user_id, token, platform, updated_at)
  values (
    auth.uid(),
    v_token,
    coalesce(nullif(trim(p_platform), ''), 'web'),
    now()
  )
  on conflict (user_id, token)
  do update set
    platform = excluded.platform,
    updated_at = now();
end;
$$;

revoke all on function public.delete_my_fcm_tokens(text) from public;
grant execute on function public.delete_my_fcm_tokens(text) to authenticated;

revoke all on function public.upsert_fcm_token(text, text) from public;
grant execute on function public.upsert_fcm_token(text, text) to authenticated;

comment on function public.delete_my_fcm_tokens(text) is
  '로그아웃 — fcm_tokens에서 user_id=auth.uid() 및 token(선택) 삭제';

comment on function public.upsert_fcm_token(text, text) is
  'FCM 토큰 저장 — 동일 token의 타 계정 레코드 선삭제 후 upsert';
