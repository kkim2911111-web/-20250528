-- 월렌트 초과 일요금 + 일↔월 요금 캡 (calc_rental_base_price 앱과 동일 규칙)

alter table public.vehicles
  add column if not exists monthly_excess_daily_price integer;

comment on column public.vehicles.monthly_excess_daily_price is
  '30일 단위 초과 일수에 적용되는 일요금. null이면 30일 배수 기간만 예약 가능(월만 운영 시).';

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
  v_monthly_excess_daily_price integer;
  v_rental_types text[];
  v_effective_daily integer;
  v_effective_monthly integer;
  v_hours integer;
  v_days integer;
  v_blocks integer;
  v_rem integer;
  v_total integer := 0;
  v_block_raw integer;
  v_rem_charge integer;
  v_remainder_rate integer;
  v_has_daily boolean;
  v_has_monthly boolean;
  v_has_excess boolean;
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
    v.monthly_excess_daily_price,
    coalesce(v.rental_types, array['hourly']::text[])
  into
    v_price_per_hour,
    v_daily_price,
    v_monthly_price,
    v_monthly_excess_daily_price,
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
  v_has_daily := 'daily' = any (v_rental_types);
  v_has_monthly := 'monthly' = any (v_rental_types);
  v_has_excess := v_monthly_excess_daily_price is not null
    and v_monthly_excess_daily_price > 0;

  if v_type = 'hourly' then
    v_hours := floor(extract(epoch from (p_end_time - p_start_time)) / 3600)::integer;
    if v_hours < 1 or v_hours > 23 then
      raise exception 'invalid_hourly_duration';
    end if;
    return v_hours * v_price_per_hour;
  end if;

  v_days := floor(extract(epoch from (p_end_time - p_start_time)) / 86400)::integer;

  if v_type = 'daily' then
    if v_days < 1 or v_days > 29 then
      raise exception 'invalid_daily_duration';
    end if;
    if v_has_monthly then
      v_block_raw := v_days * v_effective_daily;
      if v_block_raw > v_effective_monthly then
        return v_effective_monthly;
      end if;
      return v_block_raw;
    end if;
    return v_days * v_effective_daily;
  end if;

  if v_days < 30 then
    raise exception 'invalid_monthly_duration';
  end if;
  if v_days > 11 * 30 then
    raise exception 'invalid_monthly_duration';
  end if;

  v_blocks := v_days / 30;
  v_rem := v_days % 30;

  if v_has_daily then
    v_remainder_rate := coalesce(v_monthly_excess_daily_price, v_effective_daily);
    for v_i in 1..v_blocks loop
      v_block_raw := 30 * v_effective_daily;
      if v_block_raw > v_effective_monthly then
        v_total := v_total + v_effective_monthly;
      else
        v_total := v_total + v_block_raw;
      end if;
    end loop;
    if v_rem > 0 then
      v_rem_charge := v_rem * v_remainder_rate;
      if v_rem_charge > v_effective_monthly then
        v_total := v_total + v_effective_monthly;
      else
        v_total := v_total + v_rem_charge;
      end if;
    end if;
    return v_total;
  end if;

  if not v_has_excess then
    if v_rem <> 0 then
      raise exception 'invalid_monthly_duration';
    end if;
    return v_blocks * v_effective_monthly;
  end if;

  v_total := v_blocks * v_effective_monthly;
  if v_rem > 0 then
    v_rem_charge := v_rem * v_monthly_excess_daily_price;
    if v_rem_charge > v_effective_monthly then
      v_total := v_total + v_effective_monthly;
    else
      v_total := v_total + v_rem_charge;
    end if;
  end if;
  return v_total;
end;
$$;

drop function if exists public.upsert_super_admin_vehicle(
  text, uuid, text, text, text, integer, text, boolean, integer, integer, text[]
);

create or replace function public.upsert_super_admin_vehicle(
  p_vehicle_id text default null,
  p_complex_id uuid default null,
  p_model_name text default null,
  p_vehicle_type text default 'SUV',
  p_fuel_type text default null,
  p_price_per_hour integer default 0,
  p_car_number text default null,
  p_is_available boolean default true,
  p_daily_price integer default null,
  p_monthly_price integer default null,
  p_monthly_excess_daily_price integer default null,
  p_rental_types text[] default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_types text[];
  v_service_type text;
begin
  perform public.assert_is_super_admin();

  v_types := coalesce(
    nullif(p_rental_types, array[]::text[]),
    array['hourly']::text[]
  );

  v_service_type := case
    when v_types && array['daily', 'monthly']::text[] then 'rental'
    else 'sharing'
  end;

  if p_vehicle_id is null then
    if p_complex_id is null then raise exception 'complex_id_required'; end if;
    insert into public.vehicles (
      complex_id, model_name, car_type, vehicle_type, fuel_type, price_per_hour,
      car_number, is_available, daily_price, monthly_price,
      monthly_excess_daily_price, rental_types
    )
    values (
      p_complex_id,
      coalesce(nullif(trim(p_model_name), ''), '차량'),
      coalesce(nullif(trim(p_vehicle_type), ''), 'SUV'),
      v_service_type,
      nullif(trim(p_fuel_type), ''),
      greatest(coalesce(p_price_per_hour, 0), 0),
      nullif(trim(p_car_number), ''),
      coalesce(p_is_available, true),
      p_daily_price,
      p_monthly_price,
      p_monthly_excess_daily_price,
      v_types
    )
    returning id into v_id;
    return v_id::text;
  end if;

  update public.vehicles set
    complex_id = coalesce(p_complex_id, complex_id),
    model_name = coalesce(nullif(trim(p_model_name), ''), model_name),
    car_type = coalesce(nullif(trim(p_vehicle_type), ''), car_type),
    vehicle_type = v_service_type,
    fuel_type = coalesce(nullif(trim(p_fuel_type), ''), fuel_type),
    price_per_hour = greatest(coalesce(p_price_per_hour, price_per_hour), 0),
    car_number = coalesce(nullif(trim(p_car_number), ''), car_number),
    is_available = coalesce(p_is_available, is_available),
    daily_price = p_daily_price,
    monthly_price = p_monthly_price,
    monthly_excess_daily_price = p_monthly_excess_daily_price,
    rental_types = v_types,
    updated_at = now()
  where id::text = trim(p_vehicle_id);
  if not found then raise exception 'vehicle_not_found'; end if;
  return trim(p_vehicle_id);
end;
$$;

revoke all on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) from public;
grant execute on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) to authenticated, service_role;

revoke all on function public.upsert_super_admin_vehicle(
  text, uuid, text, text, text, integer, text, boolean, integer, integer, integer, text[]
) from public;
grant execute on function public.upsert_super_admin_vehicle(
  text, uuid, text, text, text, integer, text, boolean, integer, integer, integer, text[]
) to authenticated;

drop function if exists public.get_super_admin_vehicles();

create or replace function public.get_super_admin_vehicles()
returns table (
  vehicle_id text,
  complex_id uuid,
  complex_name text,
  model_name text,
  car_number text,
  car_type text,
  vehicle_type text,
  fuel_type text,
  price_per_hour integer,
  daily_price integer,
  monthly_price integer,
  monthly_excess_daily_price integer,
  rental_types text[],
  is_available boolean,
  in_use boolean,
  current_reservation_status text,
  current_renter_name text,
  total_mileage integer,
  is_under_maintenance boolean,
  maintenance_memo text,
  created_at timestamptz
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
    v.id::text as vehicle_id,
    v.complex_id,
    c.name as complex_name,
    coalesce(v.model_name, '차량') as model_name,
    v.car_number,
    coalesce(v.car_type, 'SUV') as car_type,
    coalesce(v.vehicle_type, 'sharing') as vehicle_type,
    v.fuel_type,
    coalesce(v.price_per_hour, 0) as price_per_hour,
    v.daily_price,
    v.monthly_price,
    v.monthly_excess_daily_price,
    coalesce(v.rental_types, array['hourly']::text[]) as rental_types,
    coalesce(v.is_available, false) as is_available,
    (cur.id is not null) as in_use,
    cur.status as current_reservation_status,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      null
    ) as current_renter_name,
    coalesce(v.total_mileage, 0) as total_mileage,
    coalesce(v.is_under_maintenance, false) as is_under_maintenance,
    v.maintenance_memo,
    v.created_at
  from public.vehicles v
  join public.complexes c on c.id = v.complex_id
  left join lateral (
    select r.id, r.status, r.user_id
    from public.reservations r
    where r.vehicle_id = v.id
      and r.status = 'in_use'
    order by coalesce(r.start_at, r.start_time) desc
    limit 1
  ) cur on true
  left join public.user_profiles up on up.user_id = cur.user_id
  order by c.name asc nulls last, v.model_name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_vehicles() from public;
grant execute on function public.get_super_admin_vehicles() to authenticated;
