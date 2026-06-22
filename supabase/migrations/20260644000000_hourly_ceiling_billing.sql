-- 시간권 요금: 분 비례 → 1시간 단위 올림 (10분 단위 예약 선택은 유지, 최소 60분)

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
  v_daily_overage_hourly_rate integer;
  v_rental_types text[];
  v_effective_daily integer;
  v_effective_monthly integer;
  v_minutes integer;
  v_days integer;
  v_total_seconds numeric;
  v_full_days integer;
  v_overage_seconds numeric;
  v_overage_hours_billed integer;
  v_base integer;
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
    v.daily_overage_hourly_rate,
    coalesce(v.rental_types, array['hourly']::text[])
  into
    v_price_per_hour,
    v_daily_price,
    v_monthly_price,
    v_monthly_excess_daily_price,
    v_daily_overage_hourly_rate,
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
    v_minutes := floor(
      extract(epoch from (p_end_time - p_start_time)) / 60
    )::integer;
    if v_minutes < 60 or v_minutes > 23 * 60 or v_minutes % 10 <> 0 then
      raise exception 'invalid_hourly_duration';
    end if;
    return ceil(v_minutes::numeric / 60)::integer * v_price_per_hour;
  end if;

  v_total_seconds := extract(epoch from (p_end_time - p_start_time));
  v_full_days := floor(v_total_seconds / 86400)::integer;
  v_overage_seconds := v_total_seconds - v_full_days * 86400;
  v_overage_hours_billed := case
    when v_overage_seconds <= 0 then 0
    else ceil(v_overage_seconds / 3600)::integer
  end;

  if v_type = 'daily' then
    if v_full_days < 1 or v_full_days > 29 then
      raise exception 'invalid_daily_duration';
    end if;
    if v_overage_seconds > 0 then
      if v_daily_overage_hourly_rate is null or v_daily_overage_hourly_rate <= 0 then
        raise exception 'daily_overage_not_allowed';
      end if;
    end if;
    v_base := v_full_days * v_effective_daily;
    if v_overage_hours_billed > 0 then
      v_base := v_base + v_overage_hours_billed * v_daily_overage_hourly_rate;
    end if;
    if v_has_monthly and v_base > v_effective_monthly then
      return v_effective_monthly;
    end if;
    return v_base;
  end if;

  v_days := v_full_days;
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

comment on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) is
  '대여 기본 요금. hourly=1시간 단위 올림(최소 60분·10분 배수), daily/monthly=기존 규칙.';

revoke all on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) from public;
grant execute on function public.calc_rental_base_price(text, text, timestamptz, timestamptz) to authenticated, service_role;
