-- 로그아웃 시 FCM 토큰 제거 (다른 계정에 푸시가 가지 않도록)

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

revoke all on function public.delete_my_fcm_tokens(text) from public;
grant execute on function public.delete_my_fcm_tokens(text) to authenticated;
