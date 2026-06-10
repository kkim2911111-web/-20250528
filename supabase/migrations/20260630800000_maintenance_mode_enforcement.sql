-- 점검모드 — 입주민 신규 예약·결제·카드등록 차단 (관리자 bypass, 서버 최종 방어)

-- ── 1) 조회 RLS (입주민 앱) ───────────────────────────────────
drop policy if exists "app_settings_maintenance_read_authenticated" on public.app_settings;

create policy "app_settings_maintenance_read_authenticated"
on public.app_settings
for select
to authenticated
using (key = 'maintenance_mode');

-- ── 2) 헬퍼 ───────────────────────────────────────────────────
create or replace function public.is_app_maintenance_mode_enabled()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select (s.value->>'enabled')::boolean
      from public.app_settings s
      where s.key = 'maintenance_mode'
    ),
    false
  );
$$;

create or replace function public.get_app_maintenance_message()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(
      (select s.value->>'message' from public.app_settings s where s.key = 'maintenance_mode')
    ), ''),
    '점검 중입니다. 잠시 후 다시 이용해주세요.'
  );
$$;

create or replace function public.user_bypasses_app_maintenance(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1
      from public.user_profiles up
      where up.user_id = p_user_id
        and up.is_super_admin = true
    )
    or exists (
      select 1
      from public.staff_users s
      where s.user_id = p_user_id
        and s.approved = true
    );
$$;

create or replace function public.assert_resident_maintenance_allowed(
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

  if public.is_app_maintenance_mode_enabled() then
    raise exception 'maintenance_active';
  end if;
end;
$$;

create or replace function public.get_app_maintenance_status()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'enabled', public.is_app_maintenance_mode_enabled(),
    'message', public.get_app_maintenance_message()
  );
$$;

comment on function public.assert_resident_maintenance_allowed(uuid) is
  '점검모드 시 입주민 신규 예약·결제·카드등록 차단. 단지관리자·최고관리자 bypass.';

revoke all on function public.is_app_maintenance_mode_enabled() from public;
revoke all on function public.get_app_maintenance_message() from public;
revoke all on function public.user_bypasses_app_maintenance(uuid) from public;
revoke all on function public.assert_resident_maintenance_allowed(uuid) from public;
revoke all on function public.get_app_maintenance_status() from public;

grant execute on function public.is_app_maintenance_mode_enabled() to authenticated, service_role;
grant execute on function public.get_app_maintenance_message() to authenticated, service_role;
grant execute on function public.user_bypasses_app_maintenance(uuid) to authenticated, service_role;
grant execute on function public.assert_resident_maintenance_allowed(uuid) to authenticated, service_role;
grant execute on function public.get_app_maintenance_status() to authenticated;

-- ── 3) prepare_payment_order ────────────────────────────────────
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
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_resident_maintenance_allowed(v_user);
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

-- ── 4) create_reservation_for_me ────────────────────────────────
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
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_resident_maintenance_allowed(v_user);
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
