-- 운영 Dashboard pg_cron 7건 마이그레이션 (멱등: 존재 시 unschedule 후 schedule)
-- 선행: Database → Extensions → pg_cron, pg_net 활성화
-- HTTP 작업: app.settings.supabase_url · app.settings.service_role_key (Dashboard Database Settings)

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- ── 만료 처리 RPC (운영 cron이 호출하는 함수 — 레포에 없던 정의 보강) ──

create or replace function public.auto_expire_coupons()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  update public.coupons c
  set is_active = false
  where coalesce(c.is_active, true) = true
    and c.expires_at is not null
    and c.expires_at < now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.auto_expire_coupons() from public;
grant execute on function public.auto_expire_coupons() to service_role;

create or replace function public.auto_expire_points()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
  v_total integer := 0;
begin
  for v_row in
    select ph.id, ph.user_id, ph.amount
    from public.point_history ph
    where ph.expires_at is not null
      and ph.expires_at < now()
      and ph.amount > 0
      and coalesce(ph.type, '') <> 'expire'
  loop
    if exists (
      select 1
      from public.point_history ph2
      where ph2.type = 'expire'
        and ph2.description = 'auto_expire:' || v_row.id::text
    ) then
      continue;
    end if;

    update public.user_profiles up
    set points = greatest(coalesce(up.points, 0) - v_row.amount, 0)
    where up.user_id = v_row.user_id;

    insert into public.point_history (user_id, amount, type, description)
    values (
      v_row.user_id,
      -v_row.amount,
      'expire',
      'auto_expire:' || v_row.id::text
    );

    v_total := v_total + 1;
  end loop;

  return v_total;
end;
$$;

revoke all on function public.auto_expire_points() from public;
grant execute on function public.auto_expire_points() to service_role;

-- ── 멱등 스케줄 헬퍼 ──

create or replace function public.reschedule_cron_job(
  p_jobname text,
  p_schedule text,
  p_command text
)
returns void
language plpgsql
security definer
set search_path = public, cron
as $$
declare
  v_jobid bigint;
begin
  select j.jobid into v_jobid
  from cron.job j
  where j.jobname = p_jobname
  limit 1;

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(p_jobname, p_schedule, p_command);
end;
$$;

revoke all on function public.reschedule_cron_job(text, text, text) from public;
grant execute on function public.reschedule_cron_job(text, text, text) to postgres;

-- ── 7개 운영 cron 등록 ──

select public.reschedule_cron_job(
  'auto-complete-expired-reservations',
  '0 * * * *',
  $$select public.auto_return_expired_reservations();$$
);

select public.reschedule_cron_job(
  'auto-expire-coupons',
  '0 0 * * *',
  $$select public.auto_expire_coupons();$$
);

select public.reschedule_cron_job(
  'auto-expire-points',
  '0 0 * * *',
  $$select public.auto_expire_points();$$
);

select public.reschedule_cron_job(
  'danjicar-push-reminders',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url', true)
      || '/functions/v1/scheduled-push-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := '{}'::jsonb
  );
  $$
);

select public.reschedule_cron_job(
  'process-billing-retries-hourly',
  '0 * * * *',
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url', true)
      || '/functions/v1/process-billing-retries',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := '{}'::jsonb
  );
  $$
);

select public.reschedule_cron_job(
  'scheduled-auto-return-hourly',
  '0 * * * *',
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url', true)
      || '/functions/v1/scheduled-auto-return',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := '{}'::jsonb
  );
  $$
);

select public.reschedule_cron_job(
  'scheduled-vehicle-insurance-daily',
  '5 15 * * *',
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url', true)
      || '/functions/v1/scheduled-vehicle-insurance',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := '{}'::jsonb
  );
  $$
);
