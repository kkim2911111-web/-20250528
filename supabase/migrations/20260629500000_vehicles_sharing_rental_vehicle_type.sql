-- vehicle_type: 카셰어링(sharing) / 일월렌트(rental) 구분
-- 기존 차종(SUV 등)은 car_type 으로 이전

alter table public.vehicles add column if not exists car_type text;

-- 차종 데이터 이전 (sharing/rental 이 아닌 기존 값)
update public.vehicles
set car_type = vehicle_type
where car_type is null
  and vehicle_type is not null
  and vehicle_type not in ('sharing', 'rental');

-- rental_types 기준 vehicle_type 설정
update public.vehicles
set vehicle_type = case
  when rental_types && array['daily', 'monthly']::text[] then 'rental'
  else 'sharing'
end
where vehicle_type is null
   or vehicle_type not in ('sharing', 'rental');

alter table public.vehicles
  alter column vehicle_type set default 'sharing';

alter table public.vehicles drop constraint if exists vehicles_vehicle_type_service_check;
alter table public.vehicles add constraint vehicles_vehicle_type_service_check
  check (vehicle_type in ('sharing', 'rental'));

comment on column public.vehicles.vehicle_type is '서비스 유형: sharing(카셰어링), rental(일월렌트)';
comment on column public.vehicles.car_type is '차종 분류: SUV, 세단 등';

-- ── get_super_admin_vehicles ─────────────────────────────────
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
    coalesce(v.car_type, 'SUV') as car_type,
    coalesce(v.vehicle_type, 'sharing') as vehicle_type,
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

-- ── upsert_super_admin_vehicle ───────────────────────────────
drop function if exists public.upsert_super_admin_vehicle(text, uuid, text, text, text, integer, text, boolean, integer, integer, text[]);

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
      car_number, is_available, daily_price, monthly_price, rental_types
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
