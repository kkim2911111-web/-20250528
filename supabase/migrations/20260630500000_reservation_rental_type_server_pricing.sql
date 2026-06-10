-- 예약 rental_type 저장 + 서버 요금 재검증 + 결제 주문 연동

-- ── 1) 컬럼 ───────────────────────────────────────────────────
alter table public.reservations
  add column if not exists rental_type text not null default 'hourly';

alter table public.reservations
  drop constraint if exists reservations_rental_type_check;

alter table public.reservations
  add constraint reservations_rental_type_check
  check (rental_type in ('hourly', 'daily', 'monthly'));

alter table public.payment_orders
  add column if not exists rental_type text not null default 'hourly';

alter table public.payment_orders
  drop constraint if exists payment_orders_rental_type_check;

alter table public.payment_orders
  add constraint payment_orders_rental_type_check
  check (rental_type in ('hourly', 'daily', 'monthly'));

-- ── 2) 기존 예약 백필 ─────────────────────────────────────────
update public.reservations r
set rental_type = case
  when extract(epoch from (
    coalesce(r.end_at, r.end_time) - coalesce(r.start_at, r.start_time)
  )) < 86400 then 'hourly'
  when extract(epoch from (
    coalesce(r.end_at, r.end_time) - coalesce(r.start_at, r.start_time)
  )) <= 30 * 86400 then 'daily'
  else 'monthly'
end
where r.rental_type = 'hourly'
  and coalesce(r.start_at, r.start_time) is not null
  and coalesce(r.end_at, r.end_time) is not null;

-- ── 3) 요금 계산 헬퍼 (RentalPricing 동일 규칙) ───────────────
create or replace function public.rental_add_months(
  p_ts timestamptz,
  p_months integer
)
returns timestamptz
language plpgsql
immutable
as $$
declare
  v_year integer;
  v_month integer;
  v_day integer;
  v_last_day integer;
begin
  if p_months is null or p_months <= 0 then
    return p_ts;
  end if;

  v_year := extract(year from p_ts)::integer;
  v_month := extract(month from p_ts)::integer + p_months;

  while v_month > 12 loop
    v_year := v_year + 1;
    v_month := v_month - 12;
  end loop;

  while v_month < 1 loop
    v_year := v_year - 1;
    v_month := v_month + 12;
  end loop;

  v_day := extract(day from p_ts)::integer;
  v_last_day := extract(
    day from (
      make_date(v_year, v_month, 1) + interval '1 month - 1 day'
    )::date
  )::integer;

  if v_day > v_last_day then
    v_day := v_last_day;
  end if;

  return make_timestamptz(
    v_year,
    v_month,
    v_day,
    extract(hour from p_ts)::integer,
    extract(minute from p_ts)::integer,
    extract(second from p_ts)::double precision,
    coalesce(nullif(trim(both from extract(timezone from p_ts)::text), ''), 'UTC')
  );
end;
$$;

create or replace function public.infer_rental_type_from_duration(
  p_start timestamptz,
  p_end timestamptz
)
returns text
language sql
immutable
as $$
  select case
    when extract(epoch from (p_end - p_start)) < 86400 then 'hourly'
    when extract(epoch from (p_end - p_start)) <= 30 * 86400 then 'daily'
    else 'monthly'
  end;
$$;

create or replace function public.calc_rental_base_price(
  p_vehicle_id text,
  p_rental_type text,
  p_start_time timestamptz,
  p_end_time timestamptz
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_type text := lower(trim(coalesce(p_rental_type, 'hourly')));
  v_price_per_hour integer;
  v_daily_price integer;
  v_monthly_price integer;
  v_rental_types text[];
  v_effective_daily integer;
  v_effective_monthly integer;
  v_hours integer;
  v_days integer;
  v_months integer;
  v_i integer;
begin
  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if v_type not in ('hourly', 'daily', 'monthly') then
    raise exception 'invalid_rental_type';
  end if;

  select
    coalesce(v.price_per_hour, 0),
    v.daily_price,
    v.monthly_price,
    coalesce(v.rental_types, array['hourly']::text[])
  into
    v_price_per_hour,
    v_daily_price,
    v_monthly_price,
    v_rental_types
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  if not found then
    raise exception 'vehicle_not_found';
  end if;

  if not (v_type = any (v_rental_types)) then
    raise exception 'rental_type_not_allowed';
  end if;

  v_effective_daily := coalesce(v_daily_price, v_price_per_hour * 20);
  v_effective_monthly := coalesce(v_monthly_price, v_effective_daily * 25);

  if v_type = 'hourly' then
    v_hours := floor(extract(epoch from (p_end_time - p_start_time)) / 3600)::integer;
    if v_hours < 1 or v_hours > 23 then
      raise exception 'invalid_hourly_duration';
    end if;
    return v_hours * v_price_per_hour;
  end if;

  if v_type = 'daily' then
    v_days := floor(extract(epoch from (p_end_time - p_start_time)) / 86400)::integer;
    if v_days < 1 or v_days > 29 then
      raise exception 'invalid_daily_duration';
    end if;
    return v_days * v_effective_daily;
  end if;

  v_months := null;
  for v_i in 1..11 loop
    if public.rental_add_months(p_start_time, v_i) = p_end_time then
      v_months := v_i;
      exit;
    end if;
  end loop;

  if v_months is null then
    raise exception 'invalid_monthly_duration';
  end if;

  return v_months * v_effective_monthly;
end;
$$;

revoke all on function public.rental_add_months(timestamptz, integer) from public;
grant execute on function public.rental_add_months(timestamptz, integer) to authenticated, service_role;

revoke all on function public.infer_rental_type_from_duration(timestamptz, timestamptz) from public;
grant execute on function public.infer_rental_type_from_duration(timestamptz, timestamptz) to authenticated, service_role;

revoke all on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) from public;
grant execute on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) to authenticated, service_role;

comment on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) is
  '차량 요금·기간으로 기본 대여 요금 계산 (쿠폰/포인트 제외, RentalPricing 동일)';

-- ── 4) prepare_payment_order — rental_type + 요금 검증 ────────
drop function if exists public.prepare_payment_order(text, text, timestamptz, timestamptz, integer);
drop function if exists public.prepare_payment_order(
  text, text, timestamptz, timestamptz, integer, text, integer, integer
);

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

revoke all on function public.prepare_payment_order(
  text, text, timestamptz, timestamptz, integer, text, integer, integer, text
) from public;
grant execute on function public.prepare_payment_order(
  text, text, timestamptz, timestamptz, integer, text, integer, integer, text
) to authenticated;

-- ── 5) create_reservation_for_me — rental_type + 요금 검증 ────
drop function if exists public.create_reservation_for_me(text, timestamptz, timestamptz, integer);

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

revoke all on function public.create_reservation_for_me(
  text, timestamptz, timestamptz, integer, text
) from public;
grant execute on function public.create_reservation_for_me(
  text, timestamptz, timestamptz, integer, text
) to authenticated;

-- ── 6) finalize_reservation_after_payment — rental_type 저장 ──
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
  v_has_rental_type boolean;
  v_rental_type text;
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

  v_rental_type := lower(trim(coalesce(v_order.rental_type, 'hourly')));

  if v_order.original_price is distinct from public.calc_rental_base_price(
    v_order.vehicle_id::text,
    v_rental_type,
    v_order.start_time,
    v_order.end_time
  ) then
    raise exception 'price_mismatch';
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

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'rental_type'
  ) into v_has_rental_type;

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id,
      vehicle_id,
      total_price,
      status
      %s%s%s%s%s%s
    ) values (
      %L,
      %L::%s,
      %s,
      'confirmed'
      %s%s%s%s%s%s
    )
    returning id::text
    $f$,
    case when v_has_start_time then ', start_time, end_time' else '' end,
    case when v_has_start_at then ', start_at, end_at' else '' end,
    case when v_has_payment_key then ', payment_key' else '' end,
    case when v_has_order_id then ', order_id' else '' end,
    case when v_has_payment_status then ', payment_status' else '' end,
    case when v_has_rental_type then ', rental_type' else '' end,
    v_user,
    v_order.vehicle_id,
    v_vehicle_id_type,
    v_order.total_price,
    case when v_has_start_time then format(', %L, %L', v_order.start_time, v_order.end_time) else '' end,
    case when v_has_start_at then format(', %L, %L', v_order.start_time, v_order.end_time) else '' end,
    case when v_has_payment_key then format(', %L', p_payment_key) else '' end,
    case when v_has_order_id then format(', %L', p_order_id) else '' end,
    case when v_has_payment_status then format(', %L', 'paid') else '' end,
    case when v_has_rental_type then format(', %L', v_rental_type) else '' end
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
    'paymentKey', p_payment_key
  );
end;
$$;

-- ── 7) RPC 반환에 rental_type 추가 ─────────────────────────────
drop function if exists public.get_super_admin_reservations();

create or replace function public.get_super_admin_reservations()
returns table (
  reservation_id text,
  reservation_number text,
  complex_id uuid,
  complex_name text,
  vehicle_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  is_no_show boolean,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_type text,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz,
  created_at timestamptz,
  pickup_photos text[],
  return_photos text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();

  return query
  select
    r.id::text as reservation_id,
    r.reservation_number,
    v.complex_id,
    c.name as complex_name,
    r.vehicle_id::text as vehicle_id,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone,
    r.status,
    coalesce(r.is_no_show, false) as is_no_show,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    coalesce(r.rental_type, 'hourly') as rental_type,
    r.rental_started_at,
    r.returned_at,
    r.actual_end_at,
    r.created_at,
    coalesce(r.pickup_photos, '{}'::text[]) as pickup_photos,
    coalesce(r.return_photos, '{}'::text[]) as return_photos
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.complexes c on c.id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  order by coalesce(r.start_at, r.start_time) desc nulls last;
end;
$$;

revoke all on function public.get_super_admin_reservations() from public;
grant execute on function public.get_super_admin_reservations() to authenticated;

drop function if exists public.get_admin_reservations_with_conflict();
drop function if exists public.get_admin_reservations_with_conflict(integer, integer);

create or replace function public.get_admin_reservations_with_conflict(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_type text,
  rental_started_at timestamptz,
  updated_at timestamptz,
  next_start_at timestamptz,
  next_renter_name text,
  next_renter_phone text,
  is_conflict_risk boolean,
  second_driver_name text,
  second_driver_license text
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
    limit 1
  ),
  scoped as (
    select
      r.id,
      r.vehicle_id,
      r.user_id,
      r.status,
      coalesce(r.start_at, r.start_time) as start_at,
      coalesce(r.end_at, r.end_time) as end_at,
      coalesce(r.total_price, 0) as total_price,
      coalesce(r.rental_type, 'hourly') as rental_type,
      r.rental_started_at,
      r.updated_at,
      nullif(trim(r.second_driver_name), '') as second_driver_name,
      nullif(trim(r.second_driver_license), '') as second_driver_license,
      coalesce(v.model_name, '차량') as vehicle_name,
      v.car_number,
      coalesce(
        nullif(trim(up.full_name), ''),
        nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as renter_name,
      coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    join staff_complex sc on sc.complex_id = v.complex_id
    left join public.user_profiles up on up.user_id = r.user_id
    where r.status in ('pending', 'confirmed', 'in_use', 'returning')
      and r.status not in ('returned', 'completed', 'cancelled')
  )
  select
    s.id::text as reservation_id,
    s.vehicle_name,
    s.car_number,
    s.renter_name,
    s.renter_phone,
    s.status,
    s.start_at,
    s.end_at,
    s.total_price,
    s.rental_type,
    s.rental_started_at,
    s.updated_at,
    next_res.next_start_at,
    next_res.next_renter_name,
    next_res.next_renter_phone,
    (
      s.status = 'in_use'
      and next_res.next_start_at is not null
    ) as is_conflict_risk,
    s.second_driver_name,
    s.second_driver_license
  from scoped s
  left join lateral (
    select
      coalesce(n.start_at, n.start_time) as next_start_at,
      coalesce(
        nullif(trim(nup.full_name), ''),
        nullif(split_part(nullif(trim(nup.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as next_renter_name,
      coalesce(nullif(trim(nup.phone), ''), '미등록') as next_renter_phone
    from public.reservations n
    left join public.user_profiles nup on nup.user_id = n.user_id
    where n.vehicle_id = s.vehicle_id
      and n.id <> s.id
      and n.status in ('pending', 'confirmed', 'in_use')
      and n.status not in ('returned', 'completed', 'cancelled')
      and coalesce(n.start_at, n.start_time) <= s.end_at + interval '30 minutes'
      and coalesce(n.start_at, n.start_time) >= s.end_at - interval '5 minutes'
    order by coalesce(n.start_at, n.start_time)
    limit 1
  ) next_res on true
  order by s.start_at desc nulls last
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.get_admin_reservations_with_conflict(integer, integer) from public;
grant execute on function public.get_admin_reservations_with_conflict(integer, integer) to authenticated;

drop function if exists public.get_admin_completed_reservations();
drop function if exists public.get_admin_completed_reservations(integer, integer);

create or replace function public.get_admin_completed_reservations(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_type text,
  return_type text,
  is_no_show boolean,
  second_driver_name text,
  second_driver_license text,
  sort_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
    limit 1
  )
  select
    r.id::text as reservation_id,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone,
    r.status,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    coalesce(r.rental_type, 'hourly') as rental_type,
    r.return_type,
    coalesce(r.is_no_show, false) as is_no_show,
    nullif(trim(r.second_driver_name), '') as second_driver_name,
    nullif(trim(r.second_driver_license), '') as second_driver_license,
    coalesce(
      r.returned_at,
      r.actual_end_at,
      r.updated_at,
      r.end_at,
      r.end_time,
      r.start_at,
      r.start_time
    ) as sort_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join staff_complex sc on sc.complex_id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  where r.status = 'completed'
     or (r.status = 'cancelled' and coalesce(r.is_no_show, false) = true)
  order by sort_at desc nulls last
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.get_admin_completed_reservations(integer, integer) from public;
grant execute on function public.get_admin_completed_reservations(integer, integer) to authenticated;

-- 정산 시트 items — rental_type (기존 반환 구조 유지)
create or replace function public.build_settlement_sheet_json(
  p_complex_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_month_start date;
  v_total_paid bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_payment_items jsonb := '[]'::jsonb;
  v_cancel_items jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_requested_at timestamptz;
  v_settled_at timestamptz;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_month_start := make_date(p_year, p_month, 1);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(p_year, p_month) as b;

  v_total_paid := public.sales_sum_gross(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations'
      and column_name = 'refund_amount'
  ) into v_has_refund_col;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations'
      and column_name = 'cancelled_at'
  ) into v_has_cancelled_at_col;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'reservation_number', s.reservation_number,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'rental_type', coalesce(r.rental_type, 'hourly'),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at,
        'is_no_show', s.is_no_show
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.reservations r on r.id::text = s.reservation_id_text
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'order_id', po.order_id,
        'reservation_id', r.id::text,
        'reservation_number', r.reservation_number,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'paid_at', coalesce(po.updated_at, po.created_at),
        'payment_amount', coalesce(po.total_price, 0),
        'rental_type', coalesce(r.rental_type, po.rental_type, 'hourly')
      )
      order by coalesce(po.updated_at, po.created_at) desc nulls last
    ),
    '[]'::jsonb
  )
  into v_payment_items
  from public.payment_orders po
  inner join public.reservations r on (
    (r.order_id is not null and po.order_id = r.order_id)
    or (po.reservation_id is not null and po.reservation_id = r.id::text)
    or po.order_id like 'ext_' || r.id::text || '_%'
  )
  inner join public.vehicles v on v.id = r.vehicle_id
  left join public.user_profiles up on up.user_id = r.user_id
  where v.complex_id = p_complex_id
    and po.status = 'paid'
    and coalesce(po.vehicle_id, '') <> 'signup_card'
    and date_trunc(
      'month',
      coalesce(po.updated_at, po.created_at) at time zone 'Asia/Seoul'
    )::date = v_month_start;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'reservation_id', r.id::text,
              'reservation_number', r.reservation_number,
              'renter_name', coalesce(
                nullif(trim(up.full_name), ''),
                nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
                '이름 미등록'
              ),
              'cancelled_at', coalesce(r.cancelled_at, r.updated_at),
              'paid_amount', coalesce(r.total_price, 0),
              'refund_amount', coalesce(r.refund_amount, 0),
              'rental_type', coalesce(r.rental_type, 'hourly'),
              'cancel_reason', case
                when r.rental_started_at is not null then '관리자 강제취소'
                else '고객취소'
              end
            )
            order by coalesce(r.cancelled_at, r.updated_at) desc nulls last
          ),
          '[]'::jsonb
        )
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        left join public.user_profiles up on up.user_id = r.user_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc(
            'month',
            coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
          )::date = $2
      $sql$
      into v_cancel_items
      using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'reservation_id', r.id::text,
              'reservation_number', r.reservation_number,
              'renter_name', coalesce(
                nullif(trim(up.full_name), ''),
                nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
                '이름 미등록'
              ),
              'cancelled_at', r.updated_at,
              'paid_amount', coalesce(r.total_price, 0),
              'refund_amount', coalesce(r.refund_amount, 0),
              'rental_type', coalesce(r.rental_type, 'hourly'),
              'cancel_reason', case
                when r.rental_started_at is not null then '관리자 강제취소'
                else '고객취소'
              end
            )
            order by r.updated_at desc nulls last
          ),
          '[]'::jsonb
        )
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        left join public.user_profiles up on up.user_id = r.user_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$
      into v_cancel_items
      using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'reservation_id', r.id::text,
            'reservation_number', r.reservation_number,
            'renter_name', coalesce(
              nullif(trim(up.full_name), ''),
              nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
              '이름 미등록'
            ),
            'cancelled_at', coalesce(r.cancelled_at, r.updated_at),
            'paid_amount', coalesce(r.total_price, 0),
            'refund_amount', coalesce(r.total_price, 0),
            'rental_type', coalesce(r.rental_type, 'hourly'),
            'cancel_reason', case
              when r.rental_started_at is not null then '관리자 강제취소'
              else '고객취소'
            end
          )
          order by coalesce(r.cancelled_at, r.updated_at) desc nulls last
        ),
        '[]'::jsonb
      )
      into v_cancel_items
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      left join public.user_profiles up on up.user_id = r.user_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc(
          'month',
          coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
        )::date = v_month_start;
    else
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'reservation_id', r.id::text,
            'reservation_number', r.reservation_number,
            'renter_name', coalesce(
              nullif(trim(up.full_name), ''),
              nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
              '이름 미등록'
            ),
            'cancelled_at', r.updated_at,
            'paid_amount', coalesce(r.total_price, 0),
            'refund_amount', coalesce(r.total_price, 0),
            'rental_type', coalesce(r.rental_type, 'hourly'),
            'cancel_reason', case
              when r.rental_started_at is not null then '관리자 강제취소'
              else '고객취소'
            end
          )
          order by r.updated_at desc nulls last
        ),
        '[]'::jsonb
      )
      into v_cancel_items
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      left join public.user_profiles up on up.user_id = r.user_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date =
          v_month_start;
    end if;
  end if;

  v_counts := public.settlement_sheet_counts(
    p_complex_id, v_period_start, v_period_end, p_year, p_month
  );

  select
    cs.settled_at is not null,
    cs.requested_at is not null and cs.settled_at is null,
    cs.requested_at,
    cs.settled_at
  into v_is_settled, v_is_requested, v_requested_at, v_settled_at
  from public.complex_settlements cs
  where cs.complex_id = p_complex_id
    and cs.period_year = p_year
    and cs.period_month = p_month;

  return jsonb_build_object(
    'complex_id', p_complex_id,
    'year', p_year,
    'month', p_month,
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', 0,
    'net_revenue', coalesce(v_total_paid, 0),
    'items', coalesce(v_items, '[]'::jsonb),
    'payment_items', coalesce(v_payment_items, '[]'::jsonb),
    'cancel_items', coalesce(v_cancel_items, '[]'::jsonb),
    'payment_count', coalesce((v_counts->>'payment_count')::bigint, 0),
    'cancel_count', coalesce((v_counts->>'cancel_count')::bigint, 0),
    'rental_count', coalesce((v_counts->>'rental_count')::bigint, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'requested_at', v_requested_at,
    'settled_at', v_settled_at
  );
end;
$$;
