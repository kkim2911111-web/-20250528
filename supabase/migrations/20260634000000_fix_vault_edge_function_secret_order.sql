-- pg_cron → Edge Function 401 방지
-- vault.decrypted_secrets 동일 name 중복 시 limit 1 만으로는 비결정적(구 JWT 등) → 최신 updated_at 우선

create or replace function public.invoke_supabase_edge_function(
  p_function_name text,
  p_body jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
declare
  v_url text;
  v_key text;
  v_path text;
begin
  select trim(ds.decrypted_secret)
  into v_url
  from vault.decrypted_secrets ds
  where ds.name = 'danjicar_supabase_url'
  order by ds.updated_at desc nulls last, ds.created_at desc
  limit 1;

  select trim(ds.decrypted_secret)
  into v_key
  from vault.decrypted_secrets ds
  where ds.name = 'danjicar_service_role_key'
  order by ds.updated_at desc nulls last, ds.created_at desc
  limit 1;

  if coalesce(v_url, '') = '' or coalesce(v_key, '') = '' then
    raise exception
      'vault secrets missing: danjicar_supabase_url / danjicar_service_role_key';
  end if;

  v_path := trim(both '/' from coalesce(p_function_name, ''));

  if v_path = '' then
    raise exception 'edge function name is required';
  end if;

  return net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/' || v_path,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := coalesce(p_body, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.invoke_supabase_edge_function(text, jsonb) from public;
grant execute on function public.invoke_supabase_edge_function(text, jsonb) to postgres;
