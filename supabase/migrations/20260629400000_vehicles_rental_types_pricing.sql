-- vehicles: 3단계 대여 요금 (시간/일/월)
alter table public.vehicles
  add column if not exists daily_price integer,
  add column if not exists monthly_price integer,
  add column if not exists rental_types text[] not null default array['hourly']::text[];

comment on column public.vehicles.daily_price is '1일 요금(원). 미입력 시 앱에서 price_per_hour × 20';
comment on column public.vehicles.monthly_price is '1개월 요금(원). 미입력 시 앱에서 daily_price × 25';
comment on column public.vehicles.rental_types is '허용 대여 유형: hourly, daily, monthly';

-- ── get_super_admin_vehicles — 신규 컬럼 반환 ───────────────
drop function if exists public.get_super_admin_vehicles();

create or replace function public.get_super_admin_vehicles()
returns table (
  vehicle_id text,
  complex_id uuid,
  complex_name text,
  model_name text,
  car_number text,
  vehicle_type text,
  fuel_type text,
  price_per_hour integer,
  daily_price integer,
  monthly_price integer,
  rental_types text[],
  is_available boolean,
  in_use boolean,
  current_reservation_status text,
  current_renter_name text,
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
    v.vehicle_type,
    v.fuel_type,
    coalesce(v.price_per_hour, 0) as price_per_hour,
    v.daily_price,
    v.monthly_price,
    coalesce(v.rental_types, array['hourly']::text[]) as rental_types,
    coalesce(v.is_available, false) as is_available,
    (cur.id is not null) as in_use,
    cur.status as current_reservation_status,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      null
    ) as current_renter_name,
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

-- ── upsert_super_admin_vehicle — 대여 유형·요금 반영 ────────
drop function if exists public.upsert_super_admin_vehicle(text, uuid, text, text, text, integer, text, boolean);

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
  p_rental_types text[] default null
)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_types text[];
begin
  perform public.assert_is_super_admin();

  v_types := coalesce(
    nullif(p_rental_types, array[]::text[]),
    array['hourly']::text[]
  );

  if p_vehicle_id is null then
    if p_complex_id is null then raise exception 'complex_id_required'; end if;
    insert into public.vehicles (
      complex_id, model_name, vehicle_type, fuel_type, price_per_hour,
      car_number, is_available, daily_price, monthly_price, rental_types
    )
    values (
      p_complex_id,
      coalesce(nullif(trim(p_model_name), ''), '차량'),
      coalesce(p_vehicle_type, 'SUV'),
      nullif(trim(p_fuel_type), ''),
      greatest(coalesce(p_price_per_hour, 0), 0),
      nullif(trim(p_car_number), ''),
      coalesce(p_is_available, true),
      p_daily_price,
      p_monthly_price,
      v_types
    )
    returning id into v_id;
    return v_id::text;
  end if;

  update public.vehicles set
    complex_id = coalesce(p_complex_id, complex_id),
    model_name = coalesce(nullif(trim(p_model_name), ''), model_name),
    vehicle_type = coalesce(nullif(trim(p_vehicle_type), ''), vehicle_type),
    fuel_type = coalesce(nullif(trim(p_fuel_type), ''), fuel_type),
    price_per_hour = greatest(coalesce(p_price_per_hour, price_per_hour), 0),
    car_number = coalesce(nullif(trim(p_car_number), ''), car_number),
    is_available = coalesce(p_is_available, is_available),
    daily_price = p_daily_price,
    monthly_price = p_monthly_price,
    rental_types = v_types,
    updated_at = now()
  where id::text = trim(p_vehicle_id);
  if not found then raise exception 'vehicle_not_found'; end if;
  return trim(p_vehicle_id);
end; $$;

revoke all on function public.get_super_admin_vehicles() from public;
revoke all on function public.upsert_super_admin_vehicle(text, uuid, text, text, text, integer, text, boolean, integer, integer, text[]) from public;

grant execute on function public.get_super_admin_vehicles() to authenticated;
grant execute on function public.upsert_super_admin_vehicle(text, uuid, text, text, text, integer, text, boolean, integer, integer, text[]) to authenticated;
