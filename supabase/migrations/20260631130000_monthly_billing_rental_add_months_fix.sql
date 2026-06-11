-- 월 대여 결제 오류 수정
-- 1) rental_add_months: extract(timezone) 숫자(0)를 타임존 이름으로 쓰던 버그
--    → invalid input syntax for type numeric time zone: "0"
-- 2) calc_rental_base_price: 30일+ monthly·비정수 월(35일 등) 30일 단위 올림 청구

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

  v_year := extract(year from p_ts at time zone 'UTC')::integer;
  v_month := extract(month from p_ts at time zone 'UTC')::integer + p_months;

  while v_month > 12 loop
    v_year := v_year + 1;
    v_month := v_month - 12;
  end loop;

  while v_month < 1 loop
    v_year := v_year - 1;
    v_month := v_month + 12;
  end loop;

  v_day := extract(day from p_ts at time zone 'UTC')::integer;
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
    extract(hour from p_ts at time zone 'UTC')::integer,
    extract(minute from p_ts at time zone 'UTC')::integer,
    extract(second from p_ts at time zone 'UTC')::double precision,
    'UTC'
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
    when extract(epoch from (p_end - p_start)) < 30 * 86400 then 'daily'
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

  v_days := floor(extract(epoch from (p_end_time - p_start_time)) / 86400)::integer;
  if v_days < 30 then
    raise exception 'invalid_monthly_duration';
  end if;

  v_months := null;
  for v_i in 1..11 loop
    if public.rental_add_months(p_start_time, v_i) = p_end_time then
      v_months := v_i;
      exit;
    end if;
  end loop;

  if v_months is null then
    v_months := (v_days + 29) / 30;
    if v_months > 11 then
      raise exception 'invalid_monthly_duration';
    end if;
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
