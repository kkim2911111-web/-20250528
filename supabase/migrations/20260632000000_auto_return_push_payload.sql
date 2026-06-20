-- 자동반납·노쇼 RPC — 푸시 발송용 처리 건 목록 반환

create or replace function public.auto_return_expired_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_auto_return_count integer := 0;
  v_no_show_count integer := 0;
  v_no_shows jsonb := '[]'::jsonb;
  v_auto_returns jsonb := '[]'::jsonb;
begin
  with no_show_updated as (
    update public.reservations r
    set
      status = 'completed',
      is_no_show = true,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_no_shows, v_no_show_count
  from no_show_updated;

  with auto_return_updated as (
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
      return_type = 'auto',
      updated_at = v_now
    where r.status = 'in_use'
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_auto_returns, v_auto_return_count
  from auto_return_updated;

  return jsonb_build_object(
    'autoReturnCount', v_auto_return_count,
    'noShowCount', v_no_show_count,
    'autoReturns', v_auto_returns,
    'noShows', v_no_shows,
    'processedAt', v_now
  );
end;
$$;

-- 이전 마이그레이션(20260628290000)은 returns integer — jsonb로 바꾸려면 DROP 필요
drop function if exists public.auto_complete_expired_reservations_for_me();

create or replace function public.auto_complete_expired_reservations_for_me()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_no_show_count integer := 0;
  v_auto_return_count integer := 0;
  v_no_shows jsonb := '[]'::jsonb;
  v_auto_returns jsonb := '[]'::jsonb;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  with no_show_updated as (
    update public.reservations r
    set
      status = 'completed',
      is_no_show = true,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.user_id = v_user
      and r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_no_shows, v_no_show_count
  from no_show_updated;

  with auto_return_updated as (
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
      return_type = 'auto',
      updated_at = v_now
    where r.user_id = v_user
      and r.status = 'in_use'
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_auto_returns, v_auto_return_count
  from auto_return_updated;

  return jsonb_build_object(
    'autoReturnCount', v_auto_return_count,
    'noShowCount', v_no_show_count,
    'autoReturns', v_auto_returns,
    'noShows', v_no_shows,
    'processedAt', v_now
  );
end;
$$;

revoke all on function public.auto_return_expired_reservations() from public;
grant execute on function public.auto_return_expired_reservations() to service_role;

revoke all on function public.auto_complete_expired_reservations_for_me() from public;
grant execute on function public.auto_complete_expired_reservations_for_me() to authenticated;
grant execute on function public.auto_complete_expired_reservations_for_me() to service_role;
