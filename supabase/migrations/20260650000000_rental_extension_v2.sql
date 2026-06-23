-- 연장 v2: in_use 중 언제든 연장, rental_type별 요금, new_end_at 기반 충돌만 차단

create or replace function public.calc_rental_extension_added_price(
  p_rental_type text,
  p_current_end timestamptz,
  p_new_end timestamptz,
  p_price_per_hour integer,
  p_daily_overage_hourly_rate integer,
  p_monthly_excess_daily_price integer
)
returns integer
language plpgsql
immutable
as $$
declare
  v_type text := lower(trim(coalesce(p_rental_type, 'hourly')));
  v_seconds numeric;
  v_units integer;
begin
  if p_new_end is null or p_current_end is null or p_new_end <= p_current_end then
    return 0;
  end if;

  v_seconds := extract(epoch from (p_new_end - p_current_end));

  if v_type = 'daily' then
    v_units := greatest(1, ceil(v_seconds / 86400.0)::integer);
    if p_daily_overage_hourly_rate is null or p_daily_overage_hourly_rate <= 0 then
      raise exception 'daily_overage_not_allowed';
    end if;
    return v_units * p_daily_overage_hourly_rate;
  end if;

  if v_type = 'monthly' then
    v_units := greatest(1, ceil(v_seconds / 86400.0)::integer);
    if p_monthly_excess_daily_price is null or p_monthly_excess_daily_price <= 0 then
      raise exception 'monthly_excess_not_allowed';
    end if;
    return v_units * p_monthly_excess_daily_price;
  end if;

  -- hourly (카셰어링)
  v_units := greatest(1, ceil(v_seconds / 3600.0)::integer);
  return v_units * greatest(coalesce(p_price_per_hour, 0), 0);
end;
$$;

comment on function public.calc_rental_extension_added_price(
  text, timestamptz, timestamptz, integer, integer, integer
) is '연장 추가 요금 — hourly: 시간 올림×시간요금, daily: 일 올림×daily_overage_hourly_rate, monthly: 일 올림×monthly_excess_daily_price';

drop function if exists public.check_rental_extension_for_me(text, integer, uuid);

create or replace function public.check_rental_extension_for_me(
  p_reservation_id text,
  p_new_end_at timestamptz default null,
  p_extension_hours integer default null,
  p_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := public.resolve_extension_actor(p_user_id);
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_end timestamptz;
  v_new_end timestamptz;
  v_block record;
  v_rental_type text;
  v_price_per_hour integer;
  v_daily_overage integer;
  v_monthly_excess integer;
  v_added_price integer;
  v_extension_hours integer;
begin
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
      'rentalType', v_row.rental_type,
      'emergencyPhone', public.get_emergency_phone()
    );
  end if;

  v_end := coalesce(v_row.end_at, v_row.end_time);
  if v_end is null then
    raise exception 'invalid_end_time';
  end if;

  v_rental_type := lower(trim(coalesce(v_row.rental_type, 'hourly')));

  if p_new_end_at is not null then
    v_new_end := p_new_end_at;
  elsif p_extension_hours is not null and p_extension_hours >= 1 then
    if v_rental_type = 'daily' or v_rental_type = 'monthly' then
      v_new_end := v_end + (p_extension_hours || ' days')::interval;
    else
      v_new_end := v_end + (p_extension_hours || ' hours')::interval;
    end if;
  else
    raise exception 'invalid_extension_target';
  end if;

  if v_new_end <= v_end then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'invalid_new_end',
      'message', '연장 종료 시각은 현재 종료 시각보다 이후여야 합니다.',
      'scheduledEndAt', v_end,
      'requestedNewEndAt', v_new_end,
      'rentalType', v_rental_type
    );
  end if;

  if v_rental_type = 'monthly' then
    if extract(epoch from (v_new_end - v_end)) < 86400.0 * 30 - 1 then
      return jsonb_build_object(
        'eligible', false,
        'reason', 'monthly_min_days',
        'message', '월렌트 연장은 30일 이상 선택해야 합니다.',
        'scheduledEndAt', v_end,
        'requestedNewEndAt', v_new_end,
        'rentalType', v_rental_type
      );
    end if;
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
      'reason', 'next_reservation_conflict',
      'message', '다음 예약과 겹쳐 연장할 수 없습니다.',
      'blockingReservationId', v_block.blocking_reservation_id::text,
      'blockingStartAt', v_block.blocking_start_at,
      'blockingEndAt', v_block.blocking_end_at,
      'blockingStatus', v_block.blocking_status,
      'scheduledEndAt', v_end,
      'requestedNewEndAt', v_new_end,
      'rentalType', v_rental_type,
      'emergencyPhone', public.get_emergency_phone(),
      'showEmergencyConsultation', false
    );
  end if;

  select
    coalesce(v.price_per_hour, 0)::integer,
    v.daily_overage_hourly_rate,
    v.monthly_excess_daily_price
  into v_price_per_hour, v_daily_overage, v_monthly_excess
  from public.vehicles v
  where v.id::text = v_row.vehicle_id::text;

  begin
    v_added_price := public.calc_rental_extension_added_price(
      v_rental_type,
      v_end,
      v_new_end,
      v_price_per_hour,
      v_daily_overage,
      v_monthly_excess
    );
  exception
    when others then
      return jsonb_build_object(
        'eligible', false,
        'reason', sqlerrm,
        'message', '연장 요금을 계산할 수 없습니다.',
        'scheduledEndAt', v_end,
        'requestedNewEndAt', v_new_end,
        'rentalType', v_rental_type
      );
  end;

  v_extension_hours := greatest(1, ceil(extract(epoch from (v_new_end - v_end)) / 3600.0)::integer);

  return jsonb_build_object(
    'eligible', true,
    'reason', null,
    'reservationId', v_row.id::text,
    'rentalType', v_rental_type,
    'extensionHours', v_extension_hours,
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

drop function if exists public.apply_rental_extension_for_me(text, integer, text, text, uuid);

create or replace function public.apply_rental_extension_for_me(
  p_reservation_id text,
  p_new_end_at timestamptz default null,
  p_extension_hours integer default null,
  p_payment_key text default null,
  p_payment_order_id text default null,
  p_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := public.resolve_extension_actor(p_user_id);
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_check jsonb;
  v_end timestamptz;
  v_new_end timestamptz;
  v_added_price integer;
  v_seq integer;
  v_now timestamptz := now();
  v_payment_key text := nullif(trim(p_payment_key), '');
  v_order_id text := nullif(trim(p_payment_order_id), '');
  v_extension_hours integer;
begin
  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  v_check := public.check_rental_extension_for_me(
    v_id,
    p_new_end_at,
    p_extension_hours,
    v_user
  );
  if coalesce((v_check->>'eligible')::boolean, false) is not true then
    raise exception '%', coalesce(v_check->>'reason', 'extension_not_eligible');
  end if;

  v_added_price := coalesce((v_check->>'addedPrice')::integer, 0);
  v_new_end := (v_check->>'newEndAt')::timestamptz;
  v_extension_hours := coalesce((v_check->>'extensionHours')::integer, 1);

  if v_added_price > 0 and v_payment_key is null then
    raise exception 'payment_required';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
    and user_id = v_user
  for update;

  v_end := coalesce(v_row.end_at, v_row.end_time);
  v_seq := v_row.extension_count + 1;

  update public.reservations
  set
    original_end_at = coalesce(original_end_at, v_end),
    end_at = v_new_end,
    end_time = v_new_end,
    extension_count = v_seq,
    extension_price_total = extension_price_total + v_added_price,
    total_price = total_price + v_added_price,
    updated_at = v_now
  where id::text = v_id;

  insert into public.reservation_extensions (
    reservation_id,
    user_id,
    vehicle_id,
    extension_hours,
    previous_end_at,
    new_end_at,
    added_price,
    extension_seq,
    payment_order_id,
    payment_key,
    payment_status
  ) values (
    v_row.id,
    v_user,
    v_row.vehicle_id::text,
    v_extension_hours,
    v_end,
    v_new_end,
    v_added_price,
    v_seq,
    v_order_id,
    v_payment_key,
    case when v_payment_key is not null then 'paid' else null end
  );

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_row.id::text,
    'rentalType', v_check->>'rentalType',
    'extensionHours', v_extension_hours,
    'previousEndAt', v_end,
    'newEndAt', v_new_end,
    'addedPrice', v_added_price,
    'extensionCount', v_seq,
    'newTotalPrice', v_row.total_price + v_added_price,
    'paymentKey', v_payment_key,
    'paymentOrderId', v_order_id
  );
end;
$$;

alter table public.billing_charge_retries
  add column if not exists extension_new_end_at timestamptz;

revoke all on function public.calc_rental_extension_added_price(
  text, timestamptz, timestamptz, integer, integer, integer
) from public;
grant execute on function public.calc_rental_extension_added_price(
  text, timestamptz, timestamptz, integer, integer, integer
) to authenticated, service_role;

revoke all on function public.check_rental_extension_for_me(text, timestamptz, integer, uuid) from public;
revoke all on function public.apply_rental_extension_for_me(text, timestamptz, integer, text, text, uuid) from public;
grant execute on function public.check_rental_extension_for_me(text, timestamptz, integer, uuid) to authenticated, service_role;
grant execute on function public.apply_rental_extension_for_me(text, timestamptz, integer, text, text, uuid) to authenticated, service_role;
