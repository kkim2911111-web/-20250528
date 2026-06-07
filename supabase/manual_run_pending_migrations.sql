-- ============================================================
-- Supabase Dashboard -> SQL Editor -> New query -> Run
-- 28270000 + 28280000 + 28290000 + 28300000
-- ============================================================

-- ===== 20260628270000_billing_retry_blacklist_insurance.sql =====

-- 결제 재시도 · 블랙리스트 예약취소 · 보험 만료 예약 차단

-- ── 1) billing_charge_retries ─────────────────────────────────
create table if not exists public.billing_charge_retries (
  id uuid primary key default gen_random_uuid(),
  charge_type text not null check (charge_type in ('deductible', 'extension')),
  reservation_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  complex_id uuid references public.complexes(id) on delete set null,
  amount integer not null check (amount >= 0),
  extension_hours integer check (extension_hours is null or extension_hours >= 1),
  retry_count integer not null default 0 check (retry_count >= 0),
  max_retries integer not null default 3 check (max_retries >= 1),
  next_retry_at timestamptz not null,
  last_error text,
  status text not null default 'pending'
    check (status in ('pending', 'succeeded', 'exhausted', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists billing_charge_retries_pending_idx
  on public.billing_charge_retries (status, next_retry_at)
  where status = 'pending';

create unique index if not exists billing_charge_retries_active_uniq
  on public.billing_charge_retries (charge_type, reservation_id, coalesce(extension_hours, 0))
  where status = 'pending';

alter table public.billing_charge_retries enable row level security;

-- ── 2) vehicles — 보험 만료 7일 전 알림 기록 ─────────────────
alter table public.vehicles
  add column if not exists insurance_warn_7d_sent_at date;

comment on column public.vehicles.insurance_warn_7d_sent_at is
  '보험 만료 7일 전 관리자 경고 푸시 발송일 (중복 방지)';

-- ── 3) 예약 가능 여부 검사 ───────────────────────────────────
create or replace function public.assert_user_not_blacklisted(p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.user_profiles up
    where up.user_id = p_user_id
      and coalesce(up.is_blacklisted, false) = true
  ) then
    raise exception 'user_blacklisted';
  end if;
end;
$$;

create or replace function public.assert_vehicle_bookable(p_vehicle_id text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  select
    v.id,
    coalesce(v.is_available, true) as is_available,
    v.insurance_expires_at
  into v_row
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  if not found then
    raise exception 'vehicle_not_found';
  end if;

  if v_row.is_available is not true then
    raise exception 'vehicle_unavailable';
  end if;

  if v_row.insurance_expires_at is not null
     and v_row.insurance_expires_at < (now() at time zone 'Asia/Seoul')::date then
    raise exception 'insurance_expired';
  end if;
end;
$$;

revoke all on function public.assert_user_not_blacklisted(uuid) from public;
revoke all on function public.assert_vehicle_bookable(text) from public;
grant execute on function public.assert_user_not_blacklisted(uuid) to authenticated, service_role;
grant execute on function public.assert_vehicle_bookable(text) to authenticated, service_role;

-- ── 4) prepare_payment_order — 블랙리스트·보험·가용성 ────────
create or replace function public.prepare_payment_order(
  p_vehicle_id text,
  p_vehicle_name text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer,
  p_user_coupon_id text default null,
  p_points_used integer default 0,
  p_original_price integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_name text;
  v_order_id text;
  v_order_name text;
  v_coupon_uuid uuid;
  v_orig integer;
  v_pts integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_user_not_blacklisted(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if p_total_price is null or p_total_price < 0 then
    raise exception 'invalid_price';
  end if;

  v_pts := greatest(coalesce(p_points_used, 0), 0);
  v_orig := coalesce(p_original_price, p_total_price + v_pts);

  if p_user_coupon_id is not null and trim(p_user_coupon_id) <> '' then
    v_coupon_uuid := trim(p_user_coupon_id)::uuid;
    if not exists (
      select 1
      from public.user_coupons uc
      where uc.id = v_coupon_uuid
        and uc.user_id = v_user
        and coalesce(uc.is_used, false) = false
    ) then
      raise exception 'invalid_coupon';
    end if;
  else
    v_coupon_uuid := null;
  end if;

  if v_pts > 0 then
    if not exists (
      select 1
      from public.user_profiles up
      where up.user_id = v_user
        and coalesce(up.points, 0) >= v_pts
    ) then
      raise exception 'insufficient_points';
    end if;
  end if;

  select r.complex_id into v_complex_id
  from public.residents r
  where r.user_id = v_user and r.approved = true;

  if v_complex_id is null then
    raise exception 'not_approved';
  end if;

  if not exists (
    select 1
    from public.vehicles v
    where v.id::text = p_vehicle_id
      and v.complex_id = v_complex_id
  ) then
    raise exception 'vehicle_not_in_complex';
  end if;

  perform public.assert_vehicle_bookable(p_vehicle_id);

  if exists (
    select 1 from public.reservations r
    where r.vehicle_id::text = p_vehicle_id
      and coalesce(r.status, 'pending') in ('pending', 'confirmed', 'in_use')
      and coalesce(r.start_time, r.start_at) < p_end_time
      and coalesce(r.end_time, r.end_at) > p_start_time
  ) then
    raise exception 'time_overlap';
  end if;

  select coalesce(p_vehicle_name, v.model_name, '단지카') into v_vehicle_name
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  v_order_id := 'danji_' || floor(extract(epoch from now()) * 1000)::bigint
    || '_' || substr(md5(random()::text), 1, 8);
  v_order_name := v_vehicle_name || ' 예약';

  insert into public.payment_orders (
    order_id, user_id, vehicle_id, vehicle_name,
    start_time, end_time, total_price, status,
    user_coupon_id, points_used, original_price
  ) values (
    v_order_id, v_user, p_vehicle_id, v_vehicle_name,
    p_start_time, p_end_time, p_total_price, 'pending',
    v_coupon_uuid, v_pts, v_orig
  );

  return jsonb_build_object(
    'orderId', v_order_id,
    'amount', p_total_price,
    'orderName', v_order_name,
    'customerKey', v_user::text
  );
end;
$$;

-- ── 5) create_reservation_for_me — 동일 검사 ─────────────────
create or replace function public.create_reservation_for_me(
  p_vehicle_id text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_id_type text;
  v_res_id text;
  v_sql text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_user_not_blacklisted(v_user);
  perform public.assert_booking_license_verified(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  select r.complex_id into v_complex_id
  from public.residents r
  where r.user_id = v_user and r.approved = true;

  if v_complex_id is null then
    raise exception 'not_approved';
  end if;

  if not public.is_vehicle_in_my_complex(p_vehicle_id) then
    raise exception 'vehicle_not_in_complex';
  end if;

  perform public.assert_vehicle_bookable(p_vehicle_id);

  if public.reservations_overlap_exists(
    p_vehicle_id, p_start_time, p_end_time, null, null
  ) then
    raise exception 'time_overlap';
  end if;

  select c.data_type into v_vehicle_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'vehicles'
    and c.column_name = 'id';

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id, vehicle_id, start_time, end_time, start_at, end_at, total_price, status
    ) values (
      $1, $2::%s, $3, $4, $5, $6, $7, 'pending'
    ) returning id::text
    $f$,
    v_vehicle_id_type
  );

  execute v_sql
    using v_user, p_vehicle_id, p_start_time, p_end_time,
          p_start_time, p_end_time, coalesce(p_total_price, 0)
    into v_res_id;

  return jsonb_build_object('id', v_res_id, 'status', 'pending');
end;
$$;

-- ── 6) 블랙리스트 시 confirmed 예약 목록 (Edge Function용) ────
create or replace function public.list_confirmed_reservations_for_user(
  p_user_id uuid
)
returns table (
  reservation_id text,
  vehicle_name text,
  complex_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id::text,
    coalesce(v.model_name, '차량'),
    v.complex_id
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where r.user_id = p_user_id
    and r.status in ('confirmed', 'pending');
$$;

revoke all on function public.list_confirmed_reservations_for_user(uuid) from public;
grant execute on function public.list_confirmed_reservations_for_user(uuid) to service_role;

comment on function public.assert_vehicle_bookable(text) is
  '신규 예약 차단 — is_available=false 또는 보험 만료';

comment on function public.assert_user_not_blacklisted(uuid) is
  '블랙리스트 사용자 예약 차단';


-- ===== 20260628280000_extension_service_role_finalize_guards.sql =====

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


-- ===== 20260628290000_auto_no_show_processing.sql =====

-- 미대여 확정 예약 종료 시각 경과 → 노쇼 자동 완료 (completed + is_no_show, 환불 없음)
-- in_use 종료 시각 경과 → 기존대로 returned (return_type = auto)

comment on column public.reservations.is_no_show is
  '노쇼 처리 여부 (관리자 강제 반납·종료 시각 경과 미대여 자동 처리)';

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
    and coalesce(r.end_at, r.end_time) < v_now;

  get diagnostics v_auto_return_count = row_count;

  return jsonb_build_object(
    'autoReturnCount', v_auto_return_count,
    'noShowCount', v_no_show_count,
    'noShows', v_no_shows,
    'processedAt', v_now
  );
end;
$$;

revoke all on function public.auto_return_expired_reservations() from public;
grant execute on function public.auto_return_expired_reservations() to service_role;

create or replace function public.auto_complete_expired_reservations_for_me()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count integer := 0;
  v_part integer;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

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
    and coalesce(r.end_at, r.end_time) < v_now;

  get diagnostics v_part = row_count;
  v_count := v_count + v_part;

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
    and coalesce(r.end_at, r.end_time) < v_now;

  get diagnostics v_part = row_count;
  v_count := v_count + v_part;

  return v_count;
end;
$$;

revoke all on function public.auto_complete_expired_reservations_for_me() from public;
grant execute on function public.auto_complete_expired_reservations_for_me() to authenticated;
grant execute on function public.auto_complete_expired_reservations_for_me() to service_role;


-- ===== 20260628300000_billing_exhausted_handling.sql =====

-- 결제 재시도 exhausted — 면책금 미수금 · 연장 취소

alter table public.reservations
  add column if not exists deductible_unpaid boolean not null default false,
  add column if not exists deductible_unpaid_at timestamptz;

comment on column public.reservations.deductible_unpaid is
  '면책금 자동결제 재시도 소진 — 미수금(수동 처리 필요)';
comment on column public.reservations.deductible_unpaid_at is
  '면책금 미수금 등록 시각';

-- service_role — 면책금 미수금 표시
create or replace function public.mark_deductible_unpaid_for_service(
  p_reservation_id text,
  p_amount integer default 500000
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_amount integer := greatest(coalesce(p_amount, 0), 0);
begin
  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if coalesce(v_row.deductible_charged, false) = true then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_charged');
  end if;

  if coalesce(v_row.deductible_waived, false) = true then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'waived');
  end if;

  update public.reservations
  set
    deductible_unpaid = true,
    deductible_unpaid_at = now(),
    deductible_amount = case when v_amount > 0 then v_amount else deductible_amount end,
    updated_at = now()
  where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_id,
    'deductibleUnpaid', true,
    'amount', case when v_amount > 0 then v_amount else v_row.deductible_amount end
  );
end;
$$;

-- service_role — 연장 결제 실패 시 미결제 연장 롤백(있을 경우)
create or replace function public.cancel_extension_charge_exhausted_for_service(
  p_reservation_id text,
  p_extension_hours integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := nullif(trim(p_reservation_id), '');
  v_hours integer := greatest(coalesce(p_extension_hours, 1), 1);
  v_row public.reservations%rowtype;
  v_ext record;
  v_reverted boolean := false;
begin
  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  select
    re.id,
    re.extension_hours,
    re.previous_end_at,
    re.new_end_at,
    coalesce(re.added_price, 0) as added_price,
    re.extension_seq,
    re.payment_status
  into v_ext
  from public.reservation_extensions re
  where re.reservation_id::text = v_id
    and re.extension_hours = v_hours
    and coalesce(re.payment_status, '') <> 'paid'
  order by re.extension_seq desc, re.created_at desc
  limit 1;

  if found then
    update public.reservations
    set
      end_at = v_ext.previous_end_at,
      end_time = v_ext.previous_end_at,
      extension_count = greatest(0, extension_count - 1),
      extension_price_total = greatest(0, extension_price_total - v_ext.added_price),
      total_price = greatest(0, total_price - v_ext.added_price),
      updated_at = now()
    where id = v_row.id;

    update public.reservation_extensions
    set payment_status = 'cancelled'
    where id = v_ext.id;

    v_reverted := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_id,
    'extensionHours', v_hours,
    'reverted', v_reverted
  );
end;
$$;

revoke all on function public.mark_deductible_unpaid_for_service(text, integer) from public;
revoke all on function public.cancel_extension_charge_exhausted_for_service(text, integer) from public;
grant execute on function public.mark_deductible_unpaid_for_service(text, integer) to service_role;
grant execute on function public.cancel_extension_charge_exhausted_for_service(text, integer) to service_role;

-- 면제 시 미수금 해제
create or replace function public.waive_reservation_deductible_for_staff(
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
  where r.id::text = trim(p_reservation_id)
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if coalesce(v_res.is_accident, false) = false then
    raise exception 'not_accident_reservation';
  end if;

  if coalesce(v_res.deductible_charged, false) = true then
    raise exception 'deductible_already_charged';
  end if;

  if coalesce(v_res.deductible_waived, false) = true then
    raise exception 'deductible_already_waived';
  end if;

  update public.reservations
  set
    deductible_waived = true,
    deductible_waived_at = now(),
    deductible_unpaid = false,
    deductible_unpaid_at = null,
    updated_at = now()
  where id = v_res.id;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_res.id::text,
    'deductibleWaived', true
  );
end;
$$;

