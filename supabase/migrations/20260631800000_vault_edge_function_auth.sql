-- pg_cron HTTP · DB 푸시 — Supabase Vault 기반 Edge Function 인증
--
-- ■ 선행 작업 (마이그레이션 적용 전/후 SQL Editor에서 1회 실행)
--   Dashboard → Database → Vault UI 로 넣어도 됩니다. name 은 아래와 동일해야 합니다.
--
--   select vault.create_secret(
--     'https://knxkmngonkzchwelpdjn.supabase.co',
--     'danjicar_supabase_url',
--     '단지카 Edge Function base URL'
--   );
--
--   select vault.create_secret(
--     '<Settings → API → service_role key>',
--     'danjicar_service_role_key',
--     '단지카 pg_cron·DB push service_role JWT'
--   );
--
--   -- 이미 같은 name 이 있으면 create 대신 update:
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'danjicar_supabase_url' limit 1),
--     'https://knxkmngonkzchwelpdjn.supabase.co',
--     'danjicar_supabase_url',
--     '단지카 Edge Function base URL'
--   );
--
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'danjicar_service_role_key' limit 1),
--     '<service_role key>',
--     'danjicar_service_role_key',
--     '단지카 pg_cron·DB push service_role JWT'
--   );
--
--   -- 등록 확인 (값은 출력하지 말 것):
--   select name, created_at
--   from vault.secrets
--   where name in ('danjicar_supabase_url', 'danjicar_service_role_key');

create extension if not exists supabase_vault with schema vault;

-- ── Vault → pg_net Edge Function 호출 (공통) ─────────────────────
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

-- ── dispatch_push_scenario_async — Vault 경유 ───────────────────
create or replace function public.dispatch_push_scenario_async(
  p_scenario text,
  p_payload jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns void
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
declare
  v_body jsonb;
  v_dedupe text;
begin
  v_dedupe := coalesce(nullif(trim(p_dedupe_key), ''), p_scenario);

  insert into public.push_scenario_dispatch_log (scenario, dedupe_key)
  values (p_scenario, v_dedupe)
  on conflict (scenario, dedupe_key) do nothing;

  if not found then
    return;
  end if;

  v_body := jsonb_build_object('scenario', p_scenario) || coalesce(p_payload, '{}'::jsonb);

  perform public.invoke_supabase_edge_function('dispatch-push-scenario', v_body);
exception
  when others then
    raise warning 'dispatch_push_scenario_async failed (%): %', p_scenario, sqlerrm;
end;
$$;

revoke all on function public.dispatch_push_scenario_async(text, jsonb, text) from public;
grant execute on function public.dispatch_push_scenario_async(text, jsonb, text) to postgres;

-- ── pg_cron HTTP 4건 — current_setting → Vault ─────────────────
select public.reschedule_cron_job(
  'danjicar-push-reminders',
  '*/5 * * * *',
  $$select public.invoke_supabase_edge_function('scheduled-push-reminders');$$
);

select public.reschedule_cron_job(
  'process-billing-retries-hourly',
  '0 * * * *',
  $$select public.invoke_supabase_edge_function('process-billing-retries');$$
);

select public.reschedule_cron_job(
  'scheduled-auto-return-hourly',
  '0 * * * *',
  $$select public.invoke_supabase_edge_function('scheduled-auto-return');$$
);

select public.reschedule_cron_job(
  'scheduled-vehicle-insurance-daily',
  '5 15 * * *',
  $$select public.invoke_supabase_edge_function('scheduled-vehicle-insurance');$$
);
