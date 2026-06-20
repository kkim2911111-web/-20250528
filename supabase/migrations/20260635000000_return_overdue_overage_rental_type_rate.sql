-- 반납 지연 초과요금: 예약 rental_type 기준 요율 선택
-- hourly → coalesce(hourly_rate, price_per_hour)
-- daily/monthly 반납지연 → daily_overage_hourly_rate (월렌트 예약기간 초과일요금과 별개)

alter table public.vehicles
  add column if not exists hourly_rate integer;

comment on column public.vehicles.hourly_rate is
  '시간당 요금(원). null이면 price_per_hour 사용.';

-- 예약 rental_type에 맞는 반납 지연 시간당 요율
create or replace function public.resolve_return_overdue_hourly_rate(
  p_rental_type text,
  p_hourly_rate integer,
  p_price_per_hour integer,
  p_daily_overage_hourly_rate integer
)
returns integer
language sql
immutable
as $$
  select case lower(trim(coalesce(p_rental_type, 'hourly')))
    when 'hourly' then
      nullif(
        greatest(coalesce(p_hourly_rate, p_price_per_hour, 0), 0),
        0
      )
    when 'daily' then
      nullif(greatest(coalesce(p_daily_overage_hourly_rate, 0), 0), 0)
    when 'monthly' then
      nullif(greatest(coalesce(p_daily_overage_hourly_rate, 0), 0), 0)
    else null
  end;
$$;

comment on function public.resolve_return_overdue_hourly_rate(
  text, integer, integer, integer
) is
  '반납 지연 초과요금용 시간당 요율. monthly_excess_daily_price(예약기간 초과일)와 무관.';

drop function if exists public.calc_return_overdue_overage(
  timestamptz, timestamptz, integer
);

create or replace function public.calc_return_overdue_overage(
  p_scheduled_end timestamptz,
  p_returned_at timestamptz,
  p_hourly_rate integer
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_late_minutes integer;
  v_billed_hours integer;
  v_amount integer;
begin
  if p_scheduled_end is null
    or p_returned_at is null
    or p_returned_at <= p_scheduled_end then
    return jsonb_build_object(
      'billedHours', 0,
      'amount', 0,
      'rateMissing', false
    );
  end if;

  v_late_minutes := floor(
    extract(epoch from (p_returned_at - p_scheduled_end)) / 60.0
  )::integer;

  v_billed_hours := case
    when v_late_minutes > 0 then ceil(v_late_minutes / 60.0)::integer
    else 0
  end;

  if p_hourly_rate is null or p_hourly_rate <= 0 then
    return jsonb_build_object(
      'billedHours', v_billed_hours,
      'amount', 0,
      'rateMissing', true
    );
  end if;

  v_amount := v_billed_hours * p_hourly_rate;

  return jsonb_build_object(
    'billedHours', v_billed_hours,
    'amount', v_amount,
    'rateMissing', false
  );
end;
$$;

comment on function public.calc_return_overdue_overage(
  timestamptz, timestamptz, integer
) is
  '예약 종료 시각 대비 실제 반납 지연분을 시간 단위 올림 청구. p_hourly_rate는 rental_type별 resolve 결과.';

create or replace function public.apply_return_overdue_overage_for_service(
  p_reservation_id text,
  p_scheduled_end timestamptz,
  p_returned_at timestamptz,
  p_was_overdue boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.reservations%rowtype;
  v_rate integer;
  v_complex_id uuid;
  v_calc jsonb;
  v_amount integer;
  v_hours integer;
begin
  if not coalesce(p_was_overdue, false) then
    return jsonb_build_object('enqueued', false);
  end if;

  select r.*
  into v_row
  from public.reservations r
  where r.id::text = p_reservation_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  select
    public.resolve_return_overdue_hourly_rate(
      v_row.rental_type,
      v.hourly_rate,
      v.price_per_hour,
      v.daily_overage_hourly_rate
    ),
    v.complex_id
  into v_rate, v_complex_id
  from public.vehicles v
  where v.id = v_row.vehicle_id;

  if coalesce(v_row.overdue_overage_charged, false) = true then
    return jsonb_build_object('enqueued', false, 'alreadyCharged', true);
  end if;

  v_calc := public.calc_return_overdue_overage(
    p_scheduled_end,
    p_returned_at,
    v_rate
  );

  v_hours := coalesce((v_calc->>'billedHours')::integer, 0);
  v_amount := coalesce((v_calc->>'amount')::integer, 0);

  update public.reservations
  set
    is_overdue = false,
    overdue_overage_hours = case when v_amount > 0 then v_hours else null end,
    overdue_overage_amount = case when v_amount > 0 then v_amount else null end,
    updated_at = now()
  where id = v_row.id;

  if v_amount > 0 then
    perform public.enqueue_overdue_overage_billing(
      p_reservation_id,
      v_row.user_id,
      v_complex_id,
      v_amount,
      v_hours
    );
    return jsonb_build_object(
      'enqueued', true,
      'amount', v_amount,
      'billedHours', v_hours,
      'rentalType', v_row.rental_type,
      'hourlyRate', v_rate
    );
  end if;

  return jsonb_build_object(
    'enqueued', false,
    'rateMissing', coalesce((v_calc->>'rateMissing')::boolean, false),
    'billedHours', v_hours,
    'rentalType', v_row.rental_type,
    'hourlyRate', v_rate
  );
end;
$$;

-- enqueue_overdue_overage_billing: 금액·시간은 apply 단계에서 rental_type 반영 후 전달 (변경 없음)
comment on function public.enqueue_overdue_overage_billing(
  text, uuid, uuid, integer, integer
) is
  '반납 지연 초과요금 결제 큐 등록. 요율은 apply_return_overdue_overage_for_service에서 rental_type 기준 산출.';
