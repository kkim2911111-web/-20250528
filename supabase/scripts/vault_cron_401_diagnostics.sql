-- pg_cron scheduled-push-reminders 401 진단 (값 노출 없이)
-- SQL Editor에서 순서대로 실행

-- 1) 동일 name secret 중복 여부
select id, name, created_at, updated_at
from vault.secrets
where name in ('danjicar_service_role_key', 'danjicar_supabase_url')
order by name, updated_at desc nulls last, created_at desc;

-- 2) invoke_supabase_edge_function 이 실제로 고르는 행 (키 prefix·길이만)
select
  ds.id,
  ds.name,
  ds.updated_at,
  left(trim(ds.decrypted_secret), 10) as key_prefix,
  length(trim(ds.decrypted_secret)) as key_length
from vault.decrypted_secrets ds
where ds.name = 'danjicar_service_role_key'
order by ds.updated_at desc nulls last, ds.created_at desc;

-- 3) cron job이 Vault 경로를 쓰는지 (app.settings 직접 호출이면 401 원인)
select jobid, jobname, schedule, command
from cron.job
where jobname in (
  'danjicar-push-reminders',
  'process-billing-retries-hourly',
  'scheduled-auto-return-hourly',
  'scheduled-vehicle-insurance-daily'
)
order by jobname;

-- 4) 수동 호출 테스트 (request id 반환)
select public.invoke_supabase_edge_function('scheduled-push-reminders');

-- 5) 최근 HTTP 응답 확인 (pg_net)
select
  id,
  status_code,
  left(content::text, 200) as body_preview,
  created
from net._http_response
order by created desc
limit 10;

-- 6) 중복 secret 정리 (최신 1건만 남기고 삭제 — 실행 전 1)·2) 결과 확인)
-- delete from vault.secrets
-- where name = 'danjicar_service_role_key'
--   and id not in (
--     select id
--     from vault.secrets
--     where name = 'danjicar_service_role_key'
--     order by updated_at desc nulls last, created_at desc
--     limit 1
--   );
