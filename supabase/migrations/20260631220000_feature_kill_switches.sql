-- 기능별 킬 스위치 — app_config (전체 점검모드 보완)

create table if not exists public.app_config (
  feature_key text primary key,
  is_enabled boolean not null default true,
  disabled_message text,
  updated_at timestamptz not null default now()
);

comment on table public.app_config is
  '기능별 킬 스위치 — 코드 배포 없이 특정 기능만 즉시 차단';

insert into public.app_config (feature_key, is_enabled, disabled_message)
values
  ('booking_hourly', true, null),
  ('booking_daily', true, null),
  ('booking_monthly', true, null),
  ('payment', true, null),
  ('extension', true, null)
on conflict (feature_key) do nothing;

alter table public.app_config enable row level security;

drop policy if exists "app_config_read_authenticated" on public.app_config;

create policy "app_config_read_authenticated"
on public.app_config
for select
to authenticated
using (true);

-- ── 헬퍼 ───────────────────────────────────────────────────────
create or replace function public.is_app_feature_enabled(p_feature_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select c.is_enabled
      from public.app_config c
      where c.feature_key = p_feature_key
    ),
    true
  );
$$;

create or replace function public.get_app_feature_disabled_message(p_feature_key text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(
      (
        select c.disabled_message
        from public.app_config c
        where c.feature_key = p_feature_key
      )
    ), ''),
    '현재 점검 중입니다. 잠시 후 다시 이용해주세요.'
  );
$$;

create or replace function public.booking_feature_key_for_rental_type(p_rental_type text)
returns text
language sql
immutable
as $$
  select case lower(trim(coalesce(p_rental_type, 'hourly')))
    when 'hourly' then 'booking_hourly'
    when 'daily' then 'booking_daily'
    when 'monthly' then 'booking_monthly'
    else null
  end;
$$;

create or replace function public.assert_app_feature_enabled(
  p_feature_key text,
  p_user_id uuid default auth.uid()
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if public.user_bypasses_app_maintenance(p_user_id) then
    return;
  end if;

  if not public.is_app_feature_enabled(p_feature_key) then
    raise exception 'feature_disabled';
  end if;
end;
$$;

create or replace function public.get_app_feature_configs()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_object_agg(
      c.feature_key,
      jsonb_build_object(
        'isEnabled', c.is_enabled,
        'disabledMessage', c.disabled_message
      )
    ),
    '{}'::jsonb
  )
  from public.app_config c;
$$;

comment on function public.get_app_feature_configs() is
  '입주민 앱 — 기능별 킬 스위치 조회 (fail-open 기본값은 클라이언트)';

revoke all on function public.is_app_feature_enabled(text) from public;
revoke all on function public.get_app_feature_disabled_message(text) from public;
revoke all on function public.booking_feature_key_for_rental_type(text) from public;
revoke all on function public.assert_app_feature_enabled(text, uuid) from public;
revoke all on function public.get_app_feature_configs() from public;

grant execute on function public.is_app_feature_enabled(text) to authenticated, service_role;
grant execute on function public.get_app_feature_disabled_message(text) to authenticated, service_role;
grant execute on function public.booking_feature_key_for_rental_type(text) to authenticated, service_role;
grant execute on function public.assert_app_feature_enabled(text, uuid) to authenticated, service_role;
grant execute on function public.get_app_feature_configs() to authenticated;

-- ── 최고관리자 설정 ───────────────────────────────────────────
create or replace function public.get_super_admin_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_maintenance jsonb;
  v_features jsonb;
begin
  perform public.assert_is_super_admin();

  select s.value into v_maintenance
  from public.app_settings s
  where s.key = 'maintenance_mode';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'featureKey', c.feature_key,
        'isEnabled', c.is_enabled,
        'disabledMessage', c.disabled_message,
        'updatedAt', c.updated_at
      )
      order by c.feature_key
    ),
    '[]'::jsonb
  )
  into v_features
  from public.app_config c;

  return jsonb_build_object(
    'maintenance', coalesce(
      v_maintenance,
      jsonb_build_object('enabled', false, 'message', '')
    ),
    'featureConfigs', v_features
  );
end;
$$;

create or replace function public.set_super_admin_feature_config(
  p_feature_key text,
  p_is_enabled boolean,
  p_disabled_message text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := nullif(trim(p_feature_key), '');
begin
  perform public.assert_is_super_admin();

  if v_key is null then
    raise exception 'invalid_feature_key';
  end if;

  if v_key not in (
    'booking_hourly',
    'booking_daily',
    'booking_monthly',
    'payment',
    'extension'
  ) then
    raise exception 'invalid_feature_key';
  end if;

  insert into public.app_config (
    feature_key,
    is_enabled,
    disabled_message,
    updated_at
  ) values (
    v_key,
    coalesce(p_is_enabled, true),
    nullif(trim(p_disabled_message), ''),
    now()
  )
  on conflict (feature_key) do update
  set
    is_enabled = excluded.is_enabled,
    disabled_message = excluded.disabled_message,
    updated_at = now();
end;
$$;

revoke all on function public.set_super_admin_feature_config(text, boolean, text) from public;
grant execute on function public.set_super_admin_feature_config(text, boolean, text) to authenticated;

-- ── prepare_payment_order — 기능 차단 ─────────────────────────
create or replace function public.prepare_payment_order(
  p_vehicle_id text,
  p_vehicle_name text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer,
  p_user_coupon_id text default null,
  p_points_used integer default 0,
  p_original_price integer default null,
  p_rental_type text default 'hourly'
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
  v_base integer;
  v_rental_type text := lower(trim(coalesce(p_rental_type, 'hourly')));
  v_booking_key text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_resident_maintenance_allowed(v_user);
  perform public.assert_app_feature_enabled('payment', v_user);

  v_booking_key := public.booking_feature_key_for_rental_type(v_rental_type);
  if v_booking_key is not null then
    perform public.assert_app_feature_enabled(v_booking_key, v_user);
  end if;

  perform public.assert_user_not_blacklisted(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if p_total_price is null or p_total_price < 0 then
    raise exception 'invalid_price';
  end if;

  if v_rental_type not in ('hourly', 'daily', 'monthly') then
    raise exception 'invalid_rental_type';
  end if;

  v_pts := greatest(coalesce(p_points_used, 0), 0);

  v_base := public.calc_rental_base_price(
    p_vehicle_id,
    v_rental_type,
    p_start_time,
    p_end_time
  );

  if p_original_price is null then
    raise exception 'original_price_required';
  end if;

  if p_original_price <> v_base then
    raise exception 'price_mismatch';
  end if;

  v_orig := p_original_price;

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
    user_coupon_id, points_used, original_price, rental_type
  ) values (
    v_order_id, v_user, p_vehicle_id, v_vehicle_name,
    p_start_time, p_end_time, p_total_price, 'pending',
    v_coupon_uuid, v_pts, v_orig, v_rental_type
  );

  return jsonb_build_object(
    'orderId', v_order_id,
    'amount', p_total_price,
    'orderName', v_order_name,
    'customerKey', v_user::text
  );
end;
$$;

-- ── create_reservation_for_me — 기능 차단 ─────────────────────
create or replace function public.create_reservation_for_me(
  p_vehicle_id text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer default 0,
  p_rental_type text default 'hourly'
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
  v_base integer;
  v_rental_type text := lower(trim(coalesce(p_rental_type, 'hourly')));
  v_has_rental_type_col boolean;
  v_booking_key text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_resident_maintenance_allowed(v_user);
  perform public.assert_app_feature_enabled('payment', v_user);

  v_booking_key := public.booking_feature_key_for_rental_type(v_rental_type);
  if v_booking_key is not null then
    perform public.assert_app_feature_enabled(v_booking_key, v_user);
  end if;

  perform public.assert_user_not_blacklisted(v_user);
  perform public.assert_booking_license_verified(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if v_rental_type not in ('hourly', 'daily', 'monthly') then
    raise exception 'invalid_rental_type';
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

  v_base := public.calc_rental_base_price(
    p_vehicle_id,
    v_rental_type,
    p_start_time,
    p_end_time
  );

  if coalesce(p_total_price, 0) <> v_base then
    raise exception 'price_mismatch';
  end if;

  select c.data_type into v_vehicle_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'vehicles'
    and c.column_name = 'id';

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'rental_type'
  ) into v_has_rental_type_col;

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id, vehicle_id, start_time, end_time, start_at, end_at, total_price, status%s
    ) values (
      $1, $2::%s, $3, $4, $5, $6, $7, 'pending'%s
    ) returning id::text
    $f$,
    case when v_has_rental_type_col then ', rental_type' else '' end,
    v_vehicle_id_type,
    case when v_has_rental_type_col then ', $8' else '' end
  );

  if v_has_rental_type_col then
    execute v_sql
      using v_user, p_vehicle_id, p_start_time, p_end_time,
            p_start_time, p_end_time, v_base, v_rental_type
      into v_res_id;
  else
    execute v_sql
      using v_user, p_vehicle_id, p_start_time, p_end_time,
            p_start_time, p_end_time, v_base
      into v_res_id;
  end if;

  return jsonb_build_object(
    'id', v_res_id,
    'status', 'pending',
    'rentalType', v_rental_type,
    'totalPrice', v_base
  );
end;
$$;

-- ── apply_rental_extension_for_me — 연장 차단 ─────────────────
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

  perform public.assert_resident_maintenance_allowed(v_user);
  perform public.assert_app_feature_enabled('extension', v_user);

  v_check := public.check_rental_extension_for_me(
    v_id,
    p_extension_hours,
    v_user
  );
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

revoke all on function public.prepare_payment_order(
  text, text, timestamptz, timestamptz, integer, text, integer, integer, text
) from public;
grant execute on function public.prepare_payment_order(
  text, text, timestamptz, timestamptz, integer, text, integer, integer, text
) to authenticated;

revoke all on function public.create_reservation_for_me(
  text, timestamptz, timestamptz, integer, text
) from public;
grant execute on function public.create_reservation_for_me(
  text, timestamptz, timestamptz, integer, text
) to authenticated;

revoke all on function public.apply_rental_extension_for_me(
  text, integer, text, text, uuid
) from public;
grant execute on function public.apply_rental_extension_for_me(
  text, integer, text, text, uuid
) to authenticated, service_role;
