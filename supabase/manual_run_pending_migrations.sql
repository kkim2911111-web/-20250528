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

-- ── 20260628310000_fix_branch_sales_stats ─────────────────────
-- 단지 관리자 홈 매출 카드 — get_admin_sales_summary(total_revenue)와 동일 집계 기준

create or replace function public.get_admin_branch_sales_stats(p_complex_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_month_end timestamptz;
  v_today_gross bigint := 0;
  v_today_extension bigint := 0;
  v_month_gross bigint := 0;
  v_month_extension bigint := 0;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_day_start := date_trunc('day', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';
  v_day_end := v_day_start + interval '1 day';
  v_month_start := date_trunc('month', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';
  v_month_end := v_month_start + interval '1 month';

  select coalesce(sum(r.total_price), 0)::bigint
  into v_today_gross
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_day_start
    and coalesce(r.returned_at, r.actual_end_at) < v_day_end;

  select coalesce(sum(re.added_price), 0)::bigint
  into v_today_extension
  from public.reservation_extensions re
  join public.reservations r on r.id::text = re.reservation_id::text
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_day_start
    and coalesce(r.returned_at, r.actual_end_at) < v_day_end;

  select coalesce(sum(r.total_price), 0)::bigint
  into v_month_gross
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_month_start
    and coalesce(r.returned_at, r.actual_end_at) < v_month_end;

  select coalesce(sum(re.added_price), 0)::bigint
  into v_month_extension
  from public.reservation_extensions re
  join public.reservations r on r.id::text = re.reservation_id::text
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_month_start
    and coalesce(r.returned_at, r.actual_end_at) < v_month_end;

  return jsonb_build_object(
    'today_sales', coalesce(v_today_gross, 0) + coalesce(v_today_extension, 0),
    'month_sales', coalesce(v_month_gross, 0) + coalesce(v_month_extension, 0)
  );
end;
$$;

comment on function public.get_admin_branch_sales_stats(uuid) is
  '단지 관리자 홈 매출 카드 — completed·반납 완료일 기준, gross+연장(get_admin_sales_summary total_revenue와 동일)';


-- ── 20260628320000_sales_aggregation_centralized ─────────────
-- 매출·정산 집계 기준 중앙화
-- 기준 변경 시 sales_return_completed_at / sales_completed_reservations_v 만 수정하면 전 RPC 반영

-- ── 1) 반납 완료일 (단일 정의) ─────────────────────────────────
create or replace function public.sales_return_completed_at(
  p_returned_at timestamptz,
  p_actual_end_at timestamptz
)
returns timestamptz
language sql
immutable
parallel safe
as $$
  select coalesce(p_returned_at, p_actual_end_at);
$$;

comment on function public.sales_return_completed_at(timestamptz, timestamptz) is
  '매출 집계 반납 완료일 — coalesce(returned_at, actual_end_at). 기준 변경 시 이 함수만 수정.';

-- ── 2) 기간 경계 (Asia/Seoul) ───────────────────────────────────
create or replace function public.sales_month_bounds(
  p_year integer,
  p_month integer,
  out period_start timestamptz,
  out period_end timestamptz
)
returns record
language sql
immutable
parallel safe
as $$
  select
    make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul'),
    make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul') + interval '1 month';
$$;

create or replace function public.sales_current_month_bounds(
  out period_start timestamptz,
  out period_end timestamptz
)
returns record
language sql
stable
parallel safe
as $$
  select
    date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul',
    (date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
      + interval '1 month';
$$;

create or replace function public.sales_today_bounds(
  out period_start timestamptz,
  out period_end timestamptz
)
returns record
language sql
stable
parallel safe
as $$
  select
    date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul',
    (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
      + interval '1 day';
$$;

-- ── 3) 매출 대상 View (completed + 반납 완료일 존재) ─────────────
create or replace view public.sales_completed_reservations_v as
select
  r.id,
  r.id::text as reservation_id_text,
  r.user_id,
  r.vehicle_id,
  v.complex_id,
  coalesce(v.model_name, '차량') as vehicle_name,
  coalesce(r.total_price, 0)::bigint as gross_amount,
  r.status,
  r.returned_at,
  r.actual_end_at,
  public.sales_return_completed_at(r.returned_at, r.actual_end_at) as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  coalesce(r.is_no_show, false) as is_no_show
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'completed'
  and public.sales_return_completed_at(r.returned_at, r.actual_end_at) is not null;

comment on view public.sales_completed_reservations_v is
  '매출 집계 대상 예약 — status=completed, 반납 완료일 기준. 정상 반납·노쇼 포함.';

-- ── 4) 연장 매출 View (위 View 기준 동일 기간 필터) ─────────────
create or replace view public.sales_extension_lines_v as
select
  scr.reservation_id_text,
  scr.complex_id,
  scr.return_completed_at,
  coalesce(re.added_price, 0)::bigint as extension_amount
from public.reservation_extensions re
inner join public.sales_completed_reservations_v scr
  on scr.reservation_id_text = re.reservation_id::text;

comment on view public.sales_extension_lines_v is
  '매출 집계 대상 연장 요금 — sales_completed_reservations_v와 동일 예약만.';

-- ── 5) 집계 헬퍼 (RPC 공통) ─────────────────────────────────────
create or replace function public.sales_sum_gross(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(s.gross_amount), 0)::bigint
  from public.sales_completed_reservations_v s
  where (p_complex_id is null or s.complex_id = p_complex_id)
    and (p_period_start is null or s.return_completed_at >= p_period_start)
    and (p_period_end is null or s.return_completed_at < p_period_end);
$$;

create or replace function public.sales_sum_extension(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(e.extension_amount), 0)::bigint
  from public.sales_extension_lines_v e
  where (p_complex_id is null or e.complex_id = p_complex_id)
    and (p_period_start is null or e.return_completed_at >= p_period_start)
    and (p_period_end is null or e.return_completed_at < p_period_end);
$$;

create or replace function public.sales_count_reservations(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::bigint
  from public.sales_completed_reservations_v s
  where (p_complex_id is null or s.complex_id = p_complex_id)
    and (p_period_start is null or s.return_completed_at >= p_period_start)
    and (p_period_end is null or s.return_completed_at < p_period_end);
$$;

create or replace function public.sales_total_revenue(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select
    public.sales_sum_gross(p_complex_id, p_period_start, p_period_end)
    + public.sales_sum_extension(p_complex_id, p_period_start, p_period_end);
$$;

revoke all on function public.sales_sum_gross(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_sum_extension(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_count_reservations(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_total_revenue(uuid, timestamptz, timestamptz) from public;

-- ── 6) get_admin_sales_summary ───────────────────────────────────
create or replace function public.get_admin_sales_summary(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_gross bigint := 0;
  v_extension bigint := 0;
  v_count bigint := 0;
  v_vehicle_count integer := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  select count(*)::integer
  into v_vehicle_count
  from public.vehicles v
  where v.complex_id = p_complex_id;

  v_count := public.sales_count_reservations(p_complex_id, v_period_start, v_period_end);
  v_gross := public.sales_sum_gross(p_complex_id, v_period_start, v_period_end);
  v_extension := public.sales_sum_extension(p_complex_id, v_period_start, v_period_end);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vehicle_name', row_data.vehicle_name,
        'amount', row_data.amount,
        'count', row_data.cnt
      )
      order by row_data.amount desc nulls last
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      s.vehicle_name,
      coalesce(sum(s.gross_amount), 0)::bigint as amount,
      count(*)::bigint as cnt
    from public.sales_completed_reservations_v s
    where s.complex_id = p_complex_id
      and s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.vehicle_name
  ) row_data;

  return jsonb_build_object(
    'gross_revenue', coalesce(v_gross, 0),
    'extension_revenue', coalesce(v_extension, 0),
    'total_revenue', coalesce(v_gross, 0) + coalesce(v_extension, 0),
    'reservation_count', coalesce(v_count, 0),
    'vehicle_count', coalesce(v_vehicle_count, 0),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

-- ── 7) get_admin_branch_sales_stats ─────────────────────────────
create or replace function public.get_admin_branch_sales_stats(p_complex_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_month_end timestamptz;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  select b.period_start, b.period_end
  into v_day_start, v_day_end
  from public.sales_today_bounds() as b;

  select b.period_start, b.period_end
  into v_month_start, v_month_end
  from public.sales_current_month_bounds() as b;

  return jsonb_build_object(
    'today_sales',
      public.sales_total_revenue(p_complex_id, v_day_start, v_day_end),
    'month_sales',
      public.sales_total_revenue(p_complex_id, v_month_start, v_month_end)
  );
end;
$$;

-- ── 8) get_super_admin_revenue ──────────────────────────────────
drop function if exists public.get_super_admin_revenue(integer, integer);

create function public.get_super_admin_revenue(
  p_year integer default null,
  p_month integer default null
)
returns table (
  complex_id uuid,
  complex_name text,
  period_year integer,
  period_month integer,
  reservation_count bigint,
  gross_revenue bigint,
  paid_order_count bigint,
  paid_order_amount bigint,
  extension_revenue bigint,
  is_settled boolean,
  settled_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
begin
  perform public.assert_is_super_admin();
  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  return query
  with complexes_all as (
    select c.id, c.name from public.complexes c
  ),
  res_sales as (
    select
      s.complex_id,
      count(*)::bigint as reservation_count,
      coalesce(sum(s.gross_amount), 0)::bigint as gross_revenue
    from public.sales_completed_reservations_v s
    where s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.complex_id
  ),
  extensions as (
    select
      e.complex_id,
      coalesce(sum(e.extension_amount), 0)::bigint as extension_revenue
    from public.sales_extension_lines_v e
    where e.return_completed_at >= v_period_start
      and e.return_completed_at < v_period_end
    group by e.complex_id
  ),
  paid_orders as (
    select
      s.complex_id,
      count(distinct po.order_id)::bigint as paid_order_count,
      coalesce(sum(po.total_price), 0)::bigint as paid_order_amount
    from public.sales_completed_reservations_v s
    inner join public.payment_orders po
      on po.reservation_id = s.reservation_id_text
      and po.status = 'paid'
    where s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.complex_id
  )
  select
    ca.id,
    ca.name,
    v_year,
    v_month,
    coalesce(rs.reservation_count, 0),
    coalesce(rs.gross_revenue, 0),
    coalesce(po.paid_order_count, 0),
    coalesce(po.paid_order_amount, 0),
    coalesce(ex.extension_revenue, 0),
    (cs.id is not null),
    cs.settled_at
  from complexes_all ca
  left join res_sales rs on rs.complex_id = ca.id
  left join paid_orders po on po.complex_id = ca.id
  left join extensions ex on ex.complex_id = ca.id
  left join public.complex_settlements cs
    on cs.complex_id = ca.id
    and cs.period_year = v_year
    and cs.period_month = v_month
  order by
    coalesce(rs.gross_revenue, 0) + coalesce(ex.extension_revenue, 0) desc,
    ca.name asc nulls last;
end;
$$;

-- ── 9) get_super_admin_dashboard ────────────────────────────────
create or replace function public.get_super_admin_dashboard()
returns table (
  complex_count bigint,
  vehicle_count bigint,
  available_vehicle_count bigint,
  in_use_vehicle_count bigint,
  staff_count bigint,
  staff_approved_count bigint,
  resident_count bigint,
  resident_approved_count bigint,
  reservation_count_today bigint,
  reservation_active_count bigint,
  today_revenue bigint,
  month_revenue bigint,
  total_revenue bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_month_end timestamptz;
begin
  perform public.assert_is_super_admin();

  select b.period_start, b.period_end
  into v_day_start, v_day_end
  from public.sales_today_bounds() as b;

  select b.period_start, b.period_end
  into v_month_start, v_month_end
  from public.sales_current_month_bounds() as b;

  return query
  with in_use as (
    select distinct r.vehicle_id
    from public.reservations r
    where r.status = 'in_use'
  ),
  today_res as (
    select count(*)::bigint as cnt
    from public.reservations r
    where coalesce(r.start_at, r.start_time) >= v_day_start
      and coalesce(r.start_at, r.start_time) < v_day_end
  ),
  active_res as (
    select count(*)::bigint as cnt
    from public.reservations r
    where r.status in ('pending', 'confirmed', 'in_use', 'returning')
  )
  select
    (select count(*)::bigint from public.complexes),
    (select count(*)::bigint from public.vehicles),
    (
      select count(*)::bigint
      from public.vehicles v
      where v.is_available = true
        and not exists (
          select 1 from in_use iu where iu.vehicle_id = v.id
        )
    ),
    (select count(*)::bigint from in_use),
    (select count(*)::bigint from public.staff_users),
    (
      select count(*)::bigint
      from public.staff_users s
      where s.approved = true
    ),
    (select count(*)::bigint from public.residents),
    (
      select count(*)::bigint
      from public.residents res
      where res.approved = true
    ),
    (select cnt from today_res),
    (select cnt from active_res),
    public.sales_total_revenue(null, v_day_start, v_day_end),
    public.sales_total_revenue(null, v_month_start, v_month_end),
    public.sales_total_revenue(null, null, null);
end;
$$;

-- ── 10) get_super_admin_settlement_reservations ─────────────────
create or replace function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns table (
  reservation_id text,
  renter_name text,
  total_price integer,
  start_at timestamptz,
  end_at timestamptz,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  return query
  select
    s.reservation_id_text as reservation_id,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(s.gross_amount, 0)::integer as total_price,
    s.start_at,
    s.end_at,
    s.rental_started_at,
    s.returned_at,
    s.actual_end_at
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end
  order by s.return_completed_at desc nulls last;
end;
$$;

-- ── 권한·설명 ───────────────────────────────────────────────────
revoke all on function public.get_admin_branch_sales_stats(uuid) from public;
grant execute on function public.get_admin_branch_sales_stats(uuid) to authenticated;

revoke all on function public.get_admin_sales_summary(uuid, integer, integer) from public;
grant execute on function public.get_admin_sales_summary(uuid, integer, integer) to authenticated;

revoke all on function public.get_super_admin_revenue(integer, integer) from public;
grant execute on function public.get_super_admin_revenue(integer, integer) to authenticated;

revoke all on function public.get_super_admin_dashboard() from public;
grant execute on function public.get_super_admin_dashboard() to authenticated;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_admin_sales_summary(uuid, integer, integer) is
  '단지 관리자 매출 — sales_completed_reservations_v 기준 (completed·반납 완료일)';

comment on function public.get_admin_branch_sales_stats(uuid) is
  '단지 관리자 홈 매출 카드 — sales_total_revenue 기준 (gross+연장)';

comment on function public.get_super_admin_revenue(integer, integer) is
  '최고관리자 정산 — sales_completed_reservations_v / sales_extension_lines_v 기준';

comment on function public.get_super_admin_dashboard() is
  '최고관리자 대시보드 — 매출 카드는 sales_total_revenue 기준';

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '최고관리자 정산 상세 — sales_completed_reservations_v와 동일 집계 기준';

-- ── 20260628330000_settlement_sheet_breakdown ─────────────────
drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

create function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_total_paid bigint := 0;
  v_cancel_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_total_paid := public.sales_total_revenue(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'refund_amount'
  )
  into v_has_refund_col;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.cancelled_at, r.updated_at) >= $2
          and coalesce(r.cancelled_at, r.updated_at) < $3
      $sql$
      into v_cancel_refund
      using p_complex_id, v_period_start, v_period_end;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and r.updated_at >= $2
          and r.updated_at < $3
      $sql$
      into v_cancel_refund
      using p_complex_id, v_period_start, v_period_end;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_cancel_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.cancelled_at, r.updated_at) >= v_period_start
        and coalesce(r.cancelled_at, r.updated_at) < v_period_end;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_cancel_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and r.updated_at >= v_period_start
        and r.updated_at < v_period_end;
    end if;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  return jsonb_build_object(
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '정산 상세 — total_paid(sales_total_revenue), cancel_refund(cancelled·refund_amount), items(sales_completed_reservations_v)';

-- ── 20260628340000_admin_notifications_rls.sql ─────────────────
alter table public.notifications
  add column if not exists complex_id uuid references public.complexes(id) on delete set null;

create index if not exists notifications_complex_created_idx
  on public.notifications (complex_id, created_at desc)
  where complex_id is not null;

comment on column public.notifications.complex_id is
  '관리자 알림 단지 (staff/super_admin 시나리오 insert 시 기록)';

create or replace function public.is_admin_notification_type(p_type text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_type, '') like 'admin%'
      or coalesce(p_type, '') like 'staff_%';
$$;

revoke all on function public.is_admin_notification_type(text) from public;
grant execute on function public.is_admin_notification_type(text) to authenticated;

drop policy if exists "notifications_select_super_admin" on public.notifications;
create policy "notifications_select_super_admin"
on public.notifications
for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.user_id = auth.uid()
      and up.is_super_admin = true
  )
  and (
    user_id = auth.uid()
    or (
      public.is_admin_notification_type(type)
      and complex_id is not null
    )
  )
);

drop policy if exists "notifications_select_staff_complex" on public.notifications;
create policy "notifications_select_staff_complex"
on public.notifications
for select
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (
        notifications.user_id = auth.uid()
        or (
          notifications.complex_id = s.complex_id
          and public.is_admin_notification_type(notifications.type)
        )
      )
  )
);

drop policy if exists "notifications_update_super_admin" on public.notifications;
create policy "notifications_update_super_admin"
on public.notifications
for update
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.user_id = auth.uid()
      and up.is_super_admin = true
  )
  and user_id = auth.uid()
)
with check (user_id = auth.uid());

drop policy if exists "notifications_update_staff_complex" on public.notifications;
create policy "notifications_update_staff_complex"
on public.notifications
for update
to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and (
        notifications.complex_id is null
        or notifications.complex_id = s.complex_id
      )
  )
)
with check (user_id = auth.uid());

-- ── 20260628350000_bulk_issue_coupon_issued_user_ids.sql ───────
create or replace function public.bulk_issue_coupon(
  p_coupon_id text,
  p_complex_id uuid default null,
  p_user_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coupon_id uuid;
  v_user_id uuid;
  v_issued integer := 0;
  v_skipped integer := 0;
  v_has_user_ids boolean;
  v_issued_user_ids uuid[] := '{}';
begin
  perform public.assert_is_super_admin();

  if p_coupon_id is null or trim(p_coupon_id) = '' then
    raise exception 'coupon_id_required';
  end if;

  v_coupon_id := trim(p_coupon_id)::uuid;

  if not exists (
    select 1 from public.coupons c where c.id = v_coupon_id
  ) then
    raise exception 'coupon_not_found';
  end if;

  v_has_user_ids := p_user_ids is not null and cardinality(p_user_ids) > 0;

  for v_user_id in
    select distinct r.user_id
    from public.residents r
    where case
      when v_has_user_ids then r.user_id = any(p_user_ids)
      when p_complex_id is not null then r.complex_id = p_complex_id
      else true
    end
  loop
    if exists (
      select 1
      from public.user_coupons uc
      where uc.user_id = v_user_id
        and uc.coupon_id = v_coupon_id
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into public.user_coupons (user_id, coupon_id, is_used)
    values (v_user_id, v_coupon_id, false);

    v_issued := v_issued + 1;
    v_issued_user_ids := array_append(v_issued_user_ids, v_user_id);
  end loop;

  return jsonb_build_object(
    'ok', true,
    'issued_count', v_issued,
    'skipped_count', v_skipped,
    'issued_user_ids', to_jsonb(v_issued_user_ids)
  );
end;
$$;

revoke all on function public.bulk_issue_coupon(text, uuid, uuid[]) from public;
grant execute on function public.bulk_issue_coupon(text, uuid, uuid[]) to authenticated;

-- ── 20260628360000_settlement_return_completed_end_at_order_dedup.sql ──
drop view if exists public.sales_extension_lines_v;
drop view if exists public.sales_completed_reservations_v;

drop function if exists public.sales_return_completed_at(timestamptz, timestamptz);
drop function if exists public.sales_return_completed_at(timestamptz, timestamptz, timestamptz);

create function public.sales_return_completed_at(
  p_returned_at timestamptz,
  p_actual_end_at timestamptz,
  p_end_at timestamptz default null
)
returns timestamptz
language sql
immutable
parallel safe
as $$
  select coalesce(p_returned_at, p_actual_end_at, p_end_at);
$$;

comment on function public.sales_return_completed_at(timestamptz, timestamptz, timestamptz) is
  '매출 집계 반납 완료일 — coalesce(returned_at, actual_end_at, end_at). 기준 변경 시 이 함수만 수정.';

create view public.sales_completed_reservations_v as
select
  r.id,
  r.id::text as reservation_id_text,
  r.user_id,
  r.vehicle_id,
  v.complex_id,
  coalesce(v.model_name, '차량') as vehicle_name,
  coalesce(r.total_price, 0)::bigint as gross_amount,
  r.status,
  r.returned_at,
  r.actual_end_at,
  public.sales_return_completed_at(
    r.returned_at,
    r.actual_end_at,
    coalesce(r.end_at, r.end_time)
  ) as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  coalesce(r.is_no_show, false) as is_no_show
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'completed'
  and public.sales_return_completed_at(
    r.returned_at,
    r.actual_end_at,
    coalesce(r.end_at, r.end_time)
  ) is not null;

comment on view public.sales_completed_reservations_v is
  '매출 집계 대상 예약 — status=completed, 반납 완료일(coalesce returned/actual_end/end) 기준.';

create view public.sales_extension_lines_v as
select
  scr.reservation_id_text,
  scr.complex_id,
  scr.return_completed_at,
  coalesce(re.added_price, 0)::bigint as extension_amount
from public.reservation_extensions re
inner join public.sales_completed_reservations_v scr
  on scr.reservation_id_text = re.reservation_id::text;

comment on view public.sales_extension_lines_v is
  '매출 집계 대상 연장 요금 — sales_completed_reservations_v와 동일 예약만.';

drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

create function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_month_start date;
  v_total_paid bigint := 0;
  v_cancel_refund bigint := 0;
  v_reservation_refund bigint := 0;
  v_payment_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_month_start := make_date(v_year, v_month, 1);

  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_total_paid := public.sales_total_revenue(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'refund_amount'
  )
  into v_has_refund_col;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc(
            'month',
            coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
          )::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc(
          'month',
          coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
        )::date = v_month_start;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = v_month_start;
    end if;
  end if;

  select coalesce(sum(coalesce(po.total_price, 0)), 0)::bigint
  into v_payment_refund
  from public.payment_orders po
  join public.vehicles veh on veh.id::text = po.vehicle_id::text
  where veh.complex_id = p_complex_id
    and po.status = 'cancelled'
    and date_trunc('month', po.updated_at at time zone 'Asia/Seoul')::date = v_month_start
    and not exists (
      select 1
      from public.reservations r2
      where r2.order_id = po.order_id
        and r2.status = 'cancelled'
    );

  v_cancel_refund := coalesce(v_reservation_refund, 0) + coalesce(v_payment_refund, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  return jsonb_build_object(
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '정산 상세 — total_paid, cancel_refund(reservations·payment_orders 취소, KST 월, order_id 중복 제거), items';

-- ── 20260628370000_fix_settlement_total_paid_sales_view.sql ──────
drop function if exists public.sales_total_revenue(uuid, timestamptz, timestamptz);
drop function if exists public.sales_sum_extension(uuid, timestamptz, timestamptz);
drop function if exists public.sales_sum_gross(uuid, timestamptz, timestamptz);

create function public.sales_sum_gross(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(s.gross_amount), 0)::bigint
  from public.sales_completed_reservations_v s
  where (p_complex_id is null or s.complex_id = p_complex_id)
    and (p_period_start is null or s.return_completed_at >= p_period_start)
    and (p_period_end is null or s.return_completed_at < p_period_end);
$$;

create function public.sales_sum_extension(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(e.extension_amount), 0)::bigint
  from public.sales_extension_lines_v e
  where (p_complex_id is null or e.complex_id = p_complex_id)
    and (p_period_start is null or e.return_completed_at >= p_period_start)
    and (p_period_end is null or e.return_completed_at < p_period_end);
$$;

create function public.sales_total_revenue(
  p_complex_id uuid default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select
    public.sales_sum_gross(p_complex_id, p_period_start, p_period_end)
    + public.sales_sum_extension(p_complex_id, p_period_start, p_period_end);
$$;

revoke all on function public.sales_sum_gross(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_sum_extension(uuid, timestamptz, timestamptz) from public;
revoke all on function public.sales_total_revenue(uuid, timestamptz, timestamptz) from public;

comment on function public.sales_sum_gross(uuid, timestamptz, timestamptz) is
  '매출 gross 합계 — sales_completed_reservations_v.gross_amount, 반납완료일 기간 필터.';
comment on function public.sales_sum_extension(uuid, timestamptz, timestamptz) is
  '연장 매출 합계 — sales_extension_lines_v, 반납완료일 기간 필터.';
comment on function public.sales_total_revenue(uuid, timestamptz, timestamptz) is
  '매출 총합 — sales_sum_gross + sales_sum_extension (payment_orders 미사용).';

drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

create function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_month_start date;
  v_total_paid bigint := 0;
  v_cancel_refund bigint := 0;
  v_reservation_refund bigint := 0;
  v_payment_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_month_start := make_date(v_year, v_month, 1);

  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_total_paid := public.sales_sum_gross(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'refund_amount'
  )
  into v_has_refund_col;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc(
            'month',
            coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
          )::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc(
          'month',
          coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
        )::date = v_month_start;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = v_month_start;
    end if;
  end if;

  select coalesce(sum(coalesce(po.total_price, 0)), 0)::bigint
  into v_payment_refund
  from public.payment_orders po
  join public.vehicles veh on veh.id::text = po.vehicle_id::text
  where veh.complex_id = p_complex_id
    and po.status = 'cancelled'
    and date_trunc('month', po.updated_at at time zone 'Asia/Seoul')::date = v_month_start
    and not exists (
      select 1
      from public.reservations r2
      where r2.order_id = po.order_id
        and r2.status = 'cancelled'
    );

  v_cancel_refund := coalesce(v_reservation_refund, 0) + coalesce(v_payment_refund, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  return jsonb_build_object(
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '정산 상세 — total_paid(sales_sum_gross·뷰 gross_amount), cancel_refund, items(동일 뷰)';

-- ── 20260628380000_cancel_reservation_soft_cancel.sql ────────────
drop function if exists public.cancel_reservation_for_me(uuid, uuid);

create or replace function public.cancel_reservation_for_me(
  p_reservation_id text,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_row public.reservations%rowtype;
  v_start timestamptz;
  v_id text := nullif(trim(p_reservation_id), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id::text = v_id
    and r.user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status not in ('confirmed', 'pending') then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_row.start_at, v_row.start_time);
  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_start <= now() + interval '1 hour' then
    raise exception 'cancel_too_late';
  end if;

  update public.reservations
  set status = 'cancelled', updated_at = now()
  where id::text = v_id
    and user_id = v_user;

  if v_row.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = now()
    where order_id = v_row.order_id
      and user_id = v_user;
  end if;

  return jsonb_build_object(
    'reservationId', v_id,
    'cancelled', true,
    'orderId', v_row.order_id,
    'paymentKey', v_row.payment_key,
    'totalPrice', v_row.total_price
  );
end;
$$;

revoke all on function public.cancel_reservation_for_me(text, uuid) from public;
grant execute on function public.cancel_reservation_for_me(text, uuid) to authenticated;
grant execute on function public.cancel_reservation_for_me(text, uuid) to service_role;

comment on function public.cancel_reservation_for_me(text, uuid) is
  '예약 취소 — status=cancelled 유지(행 삭제 없음), payment_orders 동기 취소';

-- ── 20260628390000_settlement_cancel_refund_reservations_only.sql ─
drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

create function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_month_start date;
  v_total_paid bigint := 0;
  v_cancel_refund bigint := 0;
  v_reservation_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_month_start := make_date(v_year, v_month, 1);

  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_total_paid := public.sales_sum_gross(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'refund_amount'
  )
  into v_has_refund_col;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc(
            'month',
            coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
          )::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc(
          'month',
          coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
        )::date = v_month_start;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = v_month_start;
    end if;
  end if;

  v_cancel_refund := coalesce(v_reservation_refund, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  return jsonb_build_object(
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '정산 상세 — total_paid(sales_sum_gross), cancel_refund(reservations 취소만, KST 월), items';

