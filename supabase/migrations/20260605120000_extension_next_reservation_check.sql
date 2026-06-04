-- 연장 — 종료 시각 이후 동일 차량 confirmed/in_use 예약 충돌 (next_reservation_exists)

create or replace function public.reservation_blocks_extension_window(
  p_vehicle_id text,
  p_exclude_reservation_id bigint,
  p_window_start timestamptz,
  p_window_end timestamptz
)
returns table (
  blocking_reservation_id bigint,
  blocking_start_at timestamptz,
  blocking_end_at timestamptz,
  blocking_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    coalesce(r.start_at, r.start_time),
    public.reservation_effective_end(
      r.status,
      coalesce(r.end_at, r.end_time),
      r.actual_end_at,
      r.returned_at
    ),
    r.status
  from public.reservations r
  where r.vehicle_id::text = p_vehicle_id::text
    and r.id <> p_exclude_reservation_id
    and coalesce(r.status, 'pending') in ('confirmed', 'in_use')
    and coalesce(r.start_at, r.start_time) < p_window_end
    and public.reservation_effective_end(
          r.status,
          coalesce(r.end_at, r.end_time),
          r.actual_end_at,
          r.returned_at
        ) > p_window_start
  order by coalesce(r.start_at, r.start_time)
  limit 1;
$$;

create or replace function public.check_rental_extension_for_me(
  p_reservation_id text,
  p_extension_hours integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_end timestamptz;
  v_new_end timestamptz;
  v_window_start timestamptz;
  v_block record;
  v_next_id text;
  v_next_start timestamptz;
  v_next_status text;
  v_price_per_hour integer;
  v_added_price integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_extension_hours is null or p_extension_hours < 1 then
    raise exception 'invalid_extension_hours';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
    and user_id = v_user;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status <> 'in_use' then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'invalid_status',
      'message', '대여 중(in_use)인 예약만 연장할 수 있습니다.',
      'status', v_row.status,
      'emergencyPhone', public.get_emergency_phone()
    );
  end if;

  v_end := coalesce(v_row.end_at, v_row.end_time);
  if v_end is null then
    raise exception 'invalid_end_time';
  end if;

  v_window_start := v_end - interval '1 hour';

  if now() < v_window_start then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'too_early',
      'message', '대여 종료 1시간 전부터 연장 신청이 가능합니다.',
      'scheduledEndAt', v_end,
      'extensionWindowStartAt', v_window_start,
      'emergencyPhone', public.get_emergency_phone()
    );
  end if;

  if now() >= v_end then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'too_late',
      'message', '예약 종료 시각이 지나 연장할 수 없습니다.',
      'scheduledEndAt', v_end,
      'emergencyPhone', public.get_emergency_phone()
    );
  end if;

  v_new_end := v_end + (p_extension_hours || ' hours')::interval;

  select
    r.id::text,
    coalesce(r.start_at, r.start_time),
    r.status
  into v_next_id, v_next_start, v_next_status
  from public.reservations r
  where r.vehicle_id = v_row.vehicle_id
    and r.id is distinct from v_row.id
    and r.status in ('confirmed', 'in_use')
    and coalesce(r.start_at, r.start_time) > v_end
  order by coalesce(r.start_at, r.start_time)
  limit 1;

  if v_next_id is not null then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'next_reservation_exists',
      'message', '다음 예약이 있어 연장할 수 없습니다.',
      'blockingReservationId', v_next_id,
      'blockingStartAt', v_next_start,
      'blockingStatus', v_next_status,
      'scheduledEndAt', v_end,
      'requestedNewEndAt', v_new_end,
      'extensionHours', p_extension_hours,
      'emergencyPhone', public.get_emergency_phone(),
      'showEmergencyConsultation', false
    );
  end if;

  select *
  into v_block
  from public.reservation_blocks_extension_window(
    v_row.vehicle_id::text,
    v_row.id,
    v_end,
    v_new_end
  )
  limit 1;

  if found then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'next_reservation_exists',
      'message', '다음 예약이 있어 연장할 수 없습니다.',
      'blockingReservationId', v_block.blocking_reservation_id::text,
      'blockingStartAt', v_block.blocking_start_at,
      'blockingEndAt', v_block.blocking_end_at,
      'blockingStatus', v_block.blocking_status,
      'scheduledEndAt', v_end,
      'requestedNewEndAt', v_new_end,
      'extensionHours', p_extension_hours,
      'emergencyPhone', public.get_emergency_phone(),
      'showEmergencyConsultation', false
    );
  end if;

  select coalesce(v.price_per_hour, 0)::integer
  into v_price_per_hour
  from public.vehicles v
  where v.id::text = v_row.vehicle_id::text;

  v_added_price := v_price_per_hour * p_extension_hours;

  return jsonb_build_object(
    'eligible', true,
    'reason', null,
    'reservationId', v_row.id::text,
    'extensionHours', p_extension_hours,
    'scheduledEndAt', v_end,
    'newEndAt', v_new_end,
    'addedPrice', v_added_price,
    'currentTotalPrice', v_row.total_price,
    'newTotalPrice', v_row.total_price + v_added_price,
    'extensionCount', v_row.extension_count,
    'emergencyPhone', public.get_emergency_phone()
  );
end;
$$;

revoke all on function public.check_rental_extension_for_me(text, integer) from public;
grant execute on function public.check_rental_extension_for_me(text, integer) to authenticated;
