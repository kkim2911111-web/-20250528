-- 반납검수 완료·신규 입주민 가입 푸시 (서비스 롤 → dispatch-push-scenario)
-- 선행: pg_net 확장, app.settings.supabase_url · app.settings.service_role_key

create extension if not exists pg_net with schema extensions;

-- 중복 발송 방지 (클라이언트·DB 양쪽 호출 대비)
create table if not exists public.push_scenario_dispatch_log (
  scenario text not null,
  dedupe_key text not null,
  sent_at timestamptz not null default now(),
  primary key (scenario, dedupe_key)
);

alter table public.push_scenario_dispatch_log enable row level security;

comment on table public.push_scenario_dispatch_log is
  'FCM 시나리오 멱등 발송 로그 (Edge Function service-role 호출 전 기록)';

-- ── 비동기 푸시 발송 헬퍼 ───────────────────────────────────────
create or replace function public.dispatch_push_scenario_async(
  p_scenario text,
  p_payload jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_key text;
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

  v_url := current_setting('app.settings.supabase_url', true);
  v_key := current_setting('app.settings.service_role_key', true);

  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'dispatch_push_scenario_async: app.settings 미설정 (%)', p_scenario;
    return;
  end if;

  v_body := jsonb_build_object('scenario', p_scenario) || coalesce(p_payload, '{}'::jsonb);

  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/dispatch-push-scenario',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := v_body
  );
exception
  when others then
    raise warning 'dispatch_push_scenario_async failed (%): %', p_scenario, sqlerrm;
end;
$$;

revoke all on function public.dispatch_push_scenario_async(text, jsonb, text) from public;
grant execute on function public.dispatch_push_scenario_async(text, jsonb, text) to postgres;

-- ── 반납 검수 완료 → 고객 알림 ─────────────────────────────────
create or replace function public.complete_return_inspection_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_res public.reservations%rowtype;
  v_return_completed timestamptz;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = p_reservation_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status = 'completed' then
    return jsonb_build_object(
      'reservationId', p_reservation_id,
      'status', 'completed',
      'alreadyCompleted', true
    );
  end if;

  if v_res.status <> 'returned' then
    raise exception 'invalid_status';
  end if;

  v_return_completed := public.sales_return_completed_at(
    v_res.returned_at,
    v_res.actual_end_at,
    coalesce(v_res.end_at, v_res.end_time)
  );

  update public.reservations
  set
    status = 'completed',
    returned_at = coalesce(v_res.returned_at, v_return_completed, v_now),
    actual_end_at = coalesce(
      v_res.actual_end_at,
      v_res.returned_at,
      v_return_completed,
      v_now
    ),
    updated_at = v_now
  where id = v_res.id;

  if v_res.user_id is not null then
    perform public.dispatch_push_scenario_async(
      'customer_return_inspection_complete',
      jsonb_build_object(
        'userId', v_res.user_id::text,
        'reservationId', p_reservation_id
      ),
      p_reservation_id
    );
  end if;

  return jsonb_build_object(
    'reservationId', p_reservation_id,
    'status', 'completed'
  );
end;
$$;

-- ── 신규 입주민 가입 완료 → 단지 관리자 알림 ───────────────────
create or replace function public.trg_user_profiles_staff_new_signup_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex_id text;
  v_was_completed boolean;
begin
  v_was_completed := coalesce(
    case tg_op
      when 'UPDATE' then old.signup_completed
      else false
    end,
    false
  );

  if coalesce(new.signup_completed, false) is not true then
    return new;
  end if;

  if v_was_completed is true then
    return new;
  end if;

  select r.complex_id::text
  into v_complex_id
  from public.residents r
  where r.user_id = new.user_id
  order by r.created_at desc nulls last
  limit 1;

  if v_complex_id is null or v_complex_id = '' then
    return new;
  end if;

  perform public.dispatch_push_scenario_async(
    'staff_new_signup',
    jsonb_build_object('complexId', v_complex_id),
    new.user_id::text
  );

  return new;
end;
$$;

drop trigger if exists user_profiles_staff_new_signup_push on public.user_profiles;

create trigger user_profiles_staff_new_signup_push
after insert or update of signup_completed on public.user_profiles
for each row
execute function public.trg_user_profiles_staff_new_signup_push();
