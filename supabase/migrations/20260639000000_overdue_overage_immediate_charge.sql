-- 반납 지연 초과요금: 반납 시점 즉시 결제 시도 (Edge Function) → 실패 시 기존 재시도 큐 fallback

create or replace function public.try_invoke_overdue_overage_charge(
  p_reservation_id text,
  p_user_id uuid,
  p_complex_id uuid,
  p_amount integer,
  p_billed_hours integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
begin
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('chargeAttempted', false, 'skipped', true);
  end if;

  begin
    perform public.invoke_supabase_edge_function(
      'billing-overdue-overage-charge',
      jsonb_build_object(
        'reservationId', p_reservation_id,
        'userId', p_user_id,
        'complexId', p_complex_id,
        'amount', p_amount,
        'billedHours', p_billed_hours
      )
    );
    return jsonb_build_object('chargeAttempted', true, 'enqueued', false);
  exception
    when others then
      perform public.enqueue_overdue_overage_billing(
        p_reservation_id,
        p_user_id,
        p_complex_id,
        p_amount,
        p_billed_hours
      );
      return jsonb_build_object(
        'chargeAttempted', false,
        'enqueued', true,
        'invokeError', sqlerrm
      );
  end;
end;
$$;

comment on function public.try_invoke_overdue_overage_charge(
  text, uuid, uuid, integer, integer
) is
  '반납 직후 billing-overdue-overage-charge Edge Function 비동기 호출. invoke 실패 시 enqueue_overdue_overage_billing fallback.';

revoke all on function public.try_invoke_overdue_overage_charge(
  text, uuid, uuid, integer, integer
) from public;
grant execute on function public.try_invoke_overdue_overage_charge(
  text, uuid, uuid, integer, integer
) to service_role;

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
  v_charge jsonb;
begin
  if not coalesce(p_was_overdue, false) then
    return jsonb_build_object('enqueued', false, 'chargeAttempted', false);
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
    return jsonb_build_object(
      'enqueued', false,
      'chargeAttempted', false,
      'alreadyCharged', true
    );
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
    v_charge := public.try_invoke_overdue_overage_charge(
      p_reservation_id,
      v_row.user_id,
      v_complex_id,
      v_amount,
      v_hours
    );
    return jsonb_build_object(
      'enqueued', coalesce((v_charge->>'enqueued')::boolean, false),
      'chargeAttempted', coalesce((v_charge->>'chargeAttempted')::boolean, false),
      'amount', v_amount,
      'billedHours', v_hours,
      'rentalType', v_row.rental_type,
      'hourlyRate', v_rate
    ) || coalesce(v_charge, '{}'::jsonb);
  end if;

  return jsonb_build_object(
    'enqueued', false,
    'chargeAttempted', false,
    'rateMissing', coalesce((v_calc->>'rateMissing')::boolean, false),
    'billedHours', v_hours,
    'rentalType', v_row.rental_type,
    'hourlyRate', v_rate
  );
end;
$$;

comment on function public.apply_return_overdue_overage_for_service(
  text, timestamptz, timestamptz, boolean
) is
  '반납 지연 초과요금 산출 후 즉시 billing-overdue-overage-charge 호출. Edge 실패·invoke 불가 시 enqueue_overdue_overage_billing.';

comment on function public.enqueue_overdue_overage_billing(
  text, uuid, uuid, integer, integer
) is
  '반납 지연 초과요금 결제 재시도 큐 (charge_type=overdue_overage). 즉시 결제 실패·invoke fallback 시 사용.';
