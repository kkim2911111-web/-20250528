-- 결제 재시도 exhausted — 면책금 미수금 · 연장 취소

alter table public.reservations
  add column if not exists deductible_unpaid boolean not null default false,
  add column if not exists deductible_unpaid_at timestamptz;

comment on column public.reservations.deductible_unpaid is
  '면책금 자동결제 재시도 소진 — 미수금(수동 처리 필요)';
comment on column public.reservations.deductible_unpaid_at is
  '면책금 미수금 등록 시각';

-- service_role — 면책금 미수금 표시
create or replace function public.mark_deductible_unpaid_for_service(
  p_reservation_id text,
  p_amount integer default 500000
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_amount integer := greatest(coalesce(p_amount, 0), 0);
begin
  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if coalesce(v_row.deductible_charged, false) = true then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_charged');
  end if;

  if coalesce(v_row.deductible_waived, false) = true then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'waived');
  end if;

  update public.reservations
  set
    deductible_unpaid = true,
    deductible_unpaid_at = now(),
    deductible_amount = case when v_amount > 0 then v_amount else deductible_amount end,
    updated_at = now()
  where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_id,
    'deductibleUnpaid', true,
    'amount', case when v_amount > 0 then v_amount else v_row.deductible_amount end
  );
end;
$$;

-- service_role — 연장 결제 실패 시 미결제 연장 롤백(있을 경우)
create or replace function public.cancel_extension_charge_exhausted_for_service(
  p_reservation_id text,
  p_extension_hours integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := nullif(trim(p_reservation_id), '');
  v_hours integer := greatest(coalesce(p_extension_hours, 1), 1);
  v_row public.reservations%rowtype;
  v_ext record;
  v_reverted boolean := false;
begin
  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  select
    re.id,
    re.extension_hours,
    re.previous_end_at,
    re.new_end_at,
    coalesce(re.added_price, 0) as added_price,
    re.extension_seq,
    re.payment_status
  into v_ext
  from public.reservation_extensions re
  where re.reservation_id::text = v_id
    and re.extension_hours = v_hours
    and coalesce(re.payment_status, '') <> 'paid'
  order by re.extension_seq desc, re.created_at desc
  limit 1;

  if found then
    update public.reservations
    set
      end_at = v_ext.previous_end_at,
      end_time = v_ext.previous_end_at,
      extension_count = greatest(0, extension_count - 1),
      extension_price_total = greatest(0, extension_price_total - v_ext.added_price),
      total_price = greatest(0, total_price - v_ext.added_price),
      updated_at = now()
    where id = v_row.id;

    update public.reservation_extensions
    set payment_status = 'cancelled'
    where id = v_ext.id;

    v_reverted := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_id,
    'extensionHours', v_hours,
    'reverted', v_reverted
  );
end;
$$;

revoke all on function public.mark_deductible_unpaid_for_service(text, integer) from public;
revoke all on function public.cancel_extension_charge_exhausted_for_service(text, integer) from public;
grant execute on function public.mark_deductible_unpaid_for_service(text, integer) to service_role;
grant execute on function public.cancel_extension_charge_exhausted_for_service(text, integer) to service_role;

-- 면제 시 미수금 해제
create or replace function public.waive_reservation_deductible_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_res public.reservations%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = trim(p_reservation_id)
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if coalesce(v_res.is_accident, false) = false then
    raise exception 'not_accident_reservation';
  end if;

  if coalesce(v_res.deductible_charged, false) = true then
    raise exception 'deductible_already_charged';
  end if;

  if coalesce(v_res.deductible_waived, false) = true then
    raise exception 'deductible_already_waived';
  end if;

  update public.reservations
  set
    deductible_waived = true,
    deductible_waived_at = now(),
    deductible_unpaid = false,
    deductible_unpaid_at = null,
    updated_at = now()
  where id = v_res.id;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_res.id::text,
    'deductibleWaived', true
  );
end;
$$;
