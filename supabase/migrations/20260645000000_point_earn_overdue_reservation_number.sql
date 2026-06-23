-- 포인트: 초과요금 포함 적립 + point_history 예약번호 + mark_overdue 시 추가 적립

alter table public.point_history
  add column if not exists reservation_number text;

alter table public.point_history
  add column if not exists expires_at timestamptz;

comment on column public.point_history.reservation_number is
  '적립·사용 시점 예약번호 스냅샷 (표시용)';

-- 대여 완료 포인트 적립 대상 금액 (total_price + 청구완료 초과요금)
create or replace function public._rental_point_earnable_amount(
  p_total_price integer,
  p_overdue_overage_amount integer,
  p_overdue_overage_charged boolean
)
returns integer
language sql
immutable
as $$
  select greatest(coalesce(p_total_price, 0), 0)
    + case
        when coalesce(p_overdue_overage_charged, false) then
          greatest(coalesce(p_overdue_overage_amount, 0), 0)
        else 0
      end;
$$;

create or replace function public.grant_reservation_points(
  p_user_id uuid,
  p_reservation_id text,
  p_amount integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rid text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_vehicle text;
  v_reservation_number text;
  v_earnable integer;
  v_target integer;
  v_already integer;
  v_delta integer;
  v_balance integer;
  v_expires timestamptz := now() + interval '1 year';
begin
  if p_user_id is null then
    raise exception 'user_required';
  end if;

  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'forbidden';
  end if;

  if v_rid is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_reservation_id');
  end if;

  select r.*
  into v_row
  from public.reservations r
  where r.id::text = v_rid
    and r.user_id = p_user_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.returned_at is null
     and lower(trim(coalesce(v_row.status, ''))) not in ('returned', 'completed') then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'not_returned');
  end if;

  v_vehicle := public._booking_vehicle_name_for_reservation(p_user_id, v_rid);
  v_reservation_number := nullif(trim(v_row.reservation_number), '');

  if coalesce(p_amount, 0) > 0 then
    v_earnable := p_amount;
  else
    v_earnable := public._rental_point_earnable_amount(
      v_row.total_price,
      v_row.overdue_overage_amount,
      v_row.overdue_overage_charged
    );
  end if;

  if v_earnable <= 0 then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'zero_earnable');
  end if;

  v_target := floor(v_earnable * 0.05)::integer;
  if v_target <= 0 then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'zero_points');
  end if;

  select coalesce(sum(ph.amount), 0)::integer
  into v_already
  from public.point_history ph
  where ph.user_id = p_user_id
    and ph.reservation_id = v_rid
    and lower(trim(coalesce(ph.type, ''))) = 'earn_rental'
    and coalesce(ph.amount, 0) > 0;

  v_delta := v_target - coalesce(v_already, 0);
  if v_delta <= 0 then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_granted',
      'targetPoints', v_target,
      'alreadyGranted', v_already
    );
  end if;

  select coalesce(up.points, 0)
  into v_balance
  from public.user_profiles up
  where up.user_id = p_user_id
  for update;

  if not found then
    raise exception 'profile_not_found';
  end if;

  update public.user_profiles
  set points = coalesce(points, 0) + v_delta
  where user_id = p_user_id;

  insert into public.point_history (
    user_id,
    amount,
    type,
    description,
    reservation_id,
    reservation_number,
    expires_at,
    balance_after
  )
  values (
    p_user_id,
    v_delta,
    'earn_rental',
    coalesce(v_vehicle, '차량'),
    v_rid,
    v_reservation_number,
    v_expires,
    v_balance + v_delta
  );

  return jsonb_build_object(
    'ok', true,
    'granted', v_delta,
    'targetPoints', v_target,
    'earnableAmount', v_earnable,
    'reservationNumber', v_reservation_number
  );
end;
$$;

comment on function public.grant_reservation_points(uuid, text, integer) is
  '대여 반납 후 5% 포인트 적립. (total_price + overdue_overage_amount[청구완료]) 기준, reservation별 earn_rental 누적 상한.';

-- 초과요금 결제 완료 시 추가 적립분 반영
create or replace function public.mark_overdue_overage_charged_for_service(
  p_reservation_id text,
  p_amount integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  update public.reservations
  set
    overdue_overage_charged = true,
    overdue_overage_charged_at = now(),
    overdue_overage_amount = coalesce(p_amount, overdue_overage_amount),
    updated_at = now()
  where id::text = p_reservation_id
    and coalesce(overdue_overage_charged, false) = false;

  if not found then
    return;
  end if;

  select r.user_id
  into v_user_id
  from public.reservations r
  where r.id::text = p_reservation_id;

  if v_user_id is not null then
    perform public.grant_reservation_points(v_user_id, p_reservation_id, 0);
  end if;
end;
$$;

revoke all on function public.grant_reservation_points(uuid, text, integer) from public;
grant execute on function public.grant_reservation_points(uuid, text, integer)
  to authenticated, service_role;

revoke all on function public.mark_overdue_overage_charged_for_service(text, integer) from public;
grant execute on function public.mark_overdue_overage_charged_for_service(text, integer) to service_role;
