-- ============================================================
-- 이용 종료(end_time) 경과 예약 자동 반납 (returned)
-- Supabase SQL Editor → Run
--
-- 1) auto_return_expired_reservations — 전체 예약 (pg_cron / service_role)
-- 2) auto_complete_expired_reservations_for_me — 로그인 사용자 (앱 새로고침)
-- ============================================================

alter table public.reservations
  add column if not exists returned_at timestamptz;

alter table public.reservations
  add column if not exists actual_end_at timestamptz;

alter table public.reservations
  add column if not exists return_type text;

alter table public.reservations
  drop constraint if exists reservations_return_type_check;

alter table public.reservations
  add constraint reservations_return_type_check
  check (
    return_type is null
    or return_type in ('normal', 'early', 'auto')
  );

-- ---------------------------------------------------------------------------
-- 전체 만료 예약 → returned (매일 cron)
-- ---------------------------------------------------------------------------

create or replace function public.auto_return_expired_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_count integer;
begin
  update public.reservations r
  set
    status = 'returned',
    returned_at = coalesce(r.returned_at, v_now),
    actual_end_at = coalesce(
      r.actual_end_at,
      r.returned_at,
      coalesce(r.end_at, r.end_time),
      v_now
    ),
    return_type = coalesce(r.return_type, 'auto'),
    updated_at = v_now
  where r.status in ('confirmed', 'in_use')
    and coalesce(r.end_at, r.end_time) is not null
    and coalesce(r.end_at, r.end_time) < v_now;

  get diagnostics v_count = row_count;

  return jsonb_build_object(
    'updatedCount', v_count,
    'processedAt', v_now
  );
end;
$$;

revoke all on function public.auto_return_expired_reservations() from public;
grant execute on function public.auto_return_expired_reservations() to service_role;

-- ---------------------------------------------------------------------------
-- 로그인 사용자 만료 예약 → returned (홈/내예약 새로고침)
-- ---------------------------------------------------------------------------

create or replace function public.auto_complete_expired_reservations_for_me()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count integer;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  update public.reservations r
  set
    status = 'returned',
    returned_at = coalesce(r.returned_at, v_now),
    actual_end_at = coalesce(
      r.actual_end_at,
      r.returned_at,
      coalesce(r.end_at, r.end_time),
      v_now
    ),
    return_type = coalesce(r.return_type, 'auto'),
    updated_at = v_now
  where r.user_id = v_user
    and r.status in ('confirmed', 'in_use')
    and coalesce(r.end_at, r.end_time) is not null
    and coalesce(r.end_at, r.end_time) < v_now;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.auto_complete_expired_reservations_for_me() from public;
grant execute on function public.auto_complete_expired_reservations_for_me() to authenticated;
grant execute on function public.auto_complete_expired_reservations_for_me() to service_role;

-- ---------------------------------------------------------------------------
-- pg_cron — 매일 03:00 KST (18:00 UTC) 자동 실행
-- Supabase Dashboard → Database → Extensions → pg_cron 활성화 후 실행
-- ---------------------------------------------------------------------------

-- create extension if not exists pg_cron with schema pg_catalog;
--
-- select cron.unschedule(jobid)
-- from cron.job
-- where jobname = 'daily-auto-return-expired-reservations';
--
-- select cron.schedule(
--   'daily-auto-return-expired-reservations',
--   '0 18 * * *',
--   $$ select public.auto_return_expired_reservations(); $$
-- );
