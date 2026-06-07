-- 연장 RPC service_role 재시도 지원 · 결제 확정 시 블랙리스트·보험 검사

create or replace function public.resolve_extension_actor(p_user_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is not null then
    return v_actor;
  end if;
  if p_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), '') <> 'service_role' then
    raise exception 'forbidden';
  end if;
  return p_user_id;
end;
$$;

revoke all on function public.resolve_extension_actor(uuid) from public;
grant execute on function public.resolve_extension_actor(uuid) to authenticated, service_role;

drop function if exists public.check_rental_extension_for_me(text, integer);

create or replace function public.check_rental_extension_for_me(
  p_reservation_id text,
  p_extension_hours integer default 1,
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
  v_window_start timestamptz;
  v_block record;
  v_next_id text;
  v_next_start timestamptz;
  v_next_status text;
  v_price_per_hour integer;
  v_added_price integer;
begin
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

drop function if exists public.apply_rental_extension_for_me(text, integer, text, text);

create or replace function public.apply_rental_extension_for_me(
  p_reservation_id text,
  p_extension_hours integer default 1,
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
begin
  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  v_check := public.check_rental_extension_for_me(v_id, p_extension_hours, v_user);
  if coalesce((v_check->>'eligible')::boolean, false) is not true then
    raise exception '%', coalesce(v_check->>'reason', 'extension_not_eligible');
  end if;

  v_added_price := coalesce((v_check->>'addedPrice')::integer, 0);

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
  v_new_end := v_end + (p_extension_hours || ' hours')::interval;
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
    p_extension_hours,
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
    'extensionHours', p_extension_hours,
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

revoke all on function public.check_rental_extension_for_me(text, integer, uuid) from public;
revoke all on function public.apply_rental_extension_for_me(text, integer, text, text, uuid) from public;
grant execute on function public.check_rental_extension_for_me(text, integer, uuid) to authenticated, service_role;
grant execute on function public.apply_rental_extension_for_me(text, integer, text, text, uuid) to authenticated, service_role;

-- finalize_reservation_after_payment — 블랙리스트·보험·가용성 검사 추가
create or replace function public.finalize_reservation_after_payment(
  p_payment_key text,
  p_order_id text,
  p_amount integer,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_order record;
  v_res_id text;
  v_vehicle_id_type text;
  v_sql text;
  v_has_start_time boolean;
  v_has_start_at boolean;
  v_has_payment_key boolean;
  v_has_order_id boolean;
  v_has_payment_status boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_user_not_blacklisted(v_user);

  if p_payment_key is null or length(trim(p_payment_key)) = 0 then
    raise exception 'invalid_payment_key';
  end if;

  if p_order_id is null or length(trim(p_order_id)) = 0 then
    raise exception 'invalid_order_id';
  end if;

  select r.id::text
  into v_res_id
  from public.reservations r
  where r.order_id = p_order_id
    and r.user_id = v_user
  limit 1;

  if v_res_id is not null then
    return jsonb_build_object(
      'reservationId', v_res_id,
      'orderId', p_order_id,
      'paymentKey', p_payment_key,
      'alreadyPaid', true
    );
  end if;

  select *
  into v_order
  from public.payment_orders
  where order_id = p_order_id
    and user_id = v_user
  for update;

  if not found then
    raise exception 'order_not_found';
  end if;

  if v_order.status in ('paid', 'confirmed') and v_order.reservation_id is not null then
    return jsonb_build_object(
      'reservationId', v_order.reservation_id::text,
      'orderId', p_order_id,
      'paymentKey', coalesce(v_order.payment_key, p_payment_key),
      'alreadyPaid', true
    );
  end if;

  if v_order.status not in ('pending', 'failed', 'paid', 'confirmed') then
    raise exception 'invalid_order_status';
  end if;

  if v_order.total_price <> p_amount then
    raise exception 'amount_mismatch';
  end if;

  perform public.assert_vehicle_bookable(v_order.vehicle_id::text);

  if public.reservations_overlap_exists(
    v_order.vehicle_id::text,
    v_order.start_time,
    v_order.end_time,
    null,
    p_order_id
  ) then
    update public.payment_orders
    set status = 'cancelled', updated_at = now()
    where order_id = p_order_id;
    raise exception 'time_overlap';
  end if;

  select c.data_type
  into v_vehicle_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'reservations'
    and c.column_name = 'vehicle_id';

  if v_vehicle_id_type is null then
    select c.data_type
    into v_vehicle_id_type
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'vehicles'
      and c.column_name = 'id';
  end if;

  if v_vehicle_id_type is null then
    v_vehicle_id_type := 'text';
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'start_time'
  ) into v_has_start_time;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'start_at'
  ) into v_has_start_at;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'payment_key'
  ) into v_has_payment_key;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'order_id'
  ) into v_has_order_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'payment_status'
  ) into v_has_payment_status;

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id,
      vehicle_id,
      total_price,
      status
      %s%s%s%s%s
    ) values (
      %L,
      %L::%s,
      %s,
      'confirmed'
      %s%s%s%s%s
    )
    returning id::text
    $f$,
    case when v_has_start_time then ', start_time, end_time' else '' end,
    case when v_has_start_at then ', start_at, end_at' else '' end,
    case when v_has_payment_key then ', payment_key' else '' end,
    case when v_has_order_id then ', order_id' else '' end,
    case when v_has_payment_status then ', payment_status' else '' end,
    v_user,
    v_order.vehicle_id,
    v_vehicle_id_type,
    v_order.total_price,
    case when v_has_start_time then format(', %L, %L', v_order.start_time, v_order.end_time) else '' end,
    case when v_has_start_at then format(', %L, %L', v_order.start_time, v_order.end_time) else '' end,
    case when v_has_payment_key then format(', %L', p_payment_key) else '' end,
    case when v_has_order_id then format(', %L', p_order_id) else '' end,
    case when v_has_payment_status then format(', %L', 'paid') else '' end
  );

  execute v_sql into v_res_id;

  update public.payment_orders
  set
    status = 'paid',
    payment_key = p_payment_key,
    has_payment_key = true,
    updated_at = now()
  where order_id = p_order_id;

  begin
    update public.payment_orders
    set reservation_id = v_res_id::uuid
    where order_id = p_order_id
      and v_res_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  exception
    when others then
      null;
  end;

  return jsonb_build_object(
    'reservationId', v_res_id,
    'orderId', p_order_id,
    'paymentKey', p_payment_key,
    'vehicleName', v_order.vehicle_name,
    'totalPrice', v_order.total_price
  );
end;
$$;
