-- 반납 지연 + 본인 연속 예약: 3단계 경고 없이 다음 예약 start_at 에 자동 반납·초과요금

create or replace function public.find_next_overdue_conflict_reservation(
  p_overdue_reservation_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_overdue public.reservations%rowtype;
  v_end timestamptz;
  v_next public.reservations%rowtype;
  v_same_user boolean;
begin
  select *
  into v_overdue
  from public.reservations r
  where r.id::text = nullif(trim(p_overdue_reservation_id), '');

  if not found then
    return null;
  end if;

  v_end := coalesce(v_overdue.end_at, v_overdue.end_time);
  if v_end is null or v_overdue.vehicle_id is null then
    return null;
  end if;

  select *
  into v_next
  from public.reservations n
  where n.vehicle_id = v_overdue.vehicle_id
    and n.status in ('confirmed', 'pending')
    and coalesce(n.start_at, n.start_time) > v_end
    and coalesce(n.start_at, n.start_time) <= v_end + interval '30 minutes'
  order by coalesce(n.start_at, n.start_time) asc
  limit 1;

  if not found then
    return null;
  end if;

  v_same_user := v_overdue.user_id is not null
    and v_next.user_id is not null
    and v_overdue.user_id = v_next.user_id;

  return jsonb_build_object(
    'overdueReservationId', v_overdue.id::text,
    'overdueUserId', v_overdue.user_id,
    'overdueEndAt', v_end,
    'nextReservationId', v_next.id::text,
    'nextUserId', v_next.user_id,
    'nextStartAt', coalesce(v_next.start_at, v_next.start_time),
    'vehicleId', v_overdue.vehicle_id::text,
    'isSameUserConsecutive', v_same_user
  );
end;
$$;

comment on function public.find_next_overdue_conflict_reservation(text) is
  '반납 지연 예약(A)에 대해 30분 이내 다음 예약(B) 존재 시 컨텍스트 반환. isSameUserConsecutive=본인 연속 예약';

-- ── 타인 예약만 1·2차 경고 타임스탬프 ───────────────────────────
create or replace function public.mark_overdue_next_reservation_warned_for_service(
  p_overdue_reservation_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_ctx jsonb;
begin
  v_ctx := public.find_next_overdue_conflict_reservation(p_overdue_reservation_id);
  if v_ctx is null
    or coalesce((v_ctx->>'isSameUserConsecutive')::boolean, false) then
    return false;
  end if;

  update public.reservations r
  set
    overdue_next_reservation_warned_at = v_now,
    updated_at = v_now
  where r.id::text = nullif(trim(p_overdue_reservation_id), '')
    and r.status = 'in_use'
    and coalesce(r.is_overdue, false) = true
    and r.returned_at is null
    and r.overdue_next_reservation_warned_at is null;

  return found;
end;
$$;

create or replace function public.mark_overdue_next_reservation_second_warned_for_service(
  p_overdue_reservation_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_ctx jsonb;
begin
  v_ctx := public.find_next_overdue_conflict_reservation(p_overdue_reservation_id);
  if v_ctx is null
    or coalesce((v_ctx->>'isSameUserConsecutive')::boolean, false) then
    return false;
  end if;

  update public.reservations r
  set
    overdue_next_reservation_second_warned_at = v_now,
    updated_at = v_now
  where r.id::text = nullif(trim(p_overdue_reservation_id), '')
    and r.status = 'in_use'
    and coalesce(r.is_overdue, false) = true
    and r.returned_at is null
    and r.overdue_next_reservation_warned_at is not null
    and r.overdue_next_reservation_warned_at + interval '15 minutes' < v_now
    and r.overdue_next_reservation_second_warned_at is null;

  return found;
end;
$$;

-- ── 타인 예약만 3단계 취소 ─────────────────────────────────────
create or replace function public.cancel_overdue_conflict_reservation_for_service(
  p_victim_reservation_id text,
  p_blocking_overdue_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_blocking public.reservations%rowtype;
  v_victim public.reservations%rowtype;
  v_end timestamptz;
  v_start timestamptz;
  v_ctx jsonb;
  v_paid bigint;
begin
  select *
  into v_blocking
  from public.reservations r
  where r.id::text = nullif(trim(p_blocking_overdue_reservation_id), '')
  for update;

  if not found then
    raise exception 'blocking_reservation_not_found';
  end if;

  if v_blocking.status <> 'in_use'
    or coalesce(v_blocking.is_overdue, false) = false
    or v_blocking.returned_at is not null then
    raise exception 'blocking_not_overdue_in_use';
  end if;

  if v_blocking.overdue_next_reservation_cancelled_at is not null then
    return jsonb_build_object(
      'ok', true,
      'alreadyCancelled', true,
      'victimReservationId', p_victim_reservation_id
    );
  end if;

  v_ctx := public.find_next_overdue_conflict_reservation(p_blocking_overdue_reservation_id);
  if v_ctx is null then
    raise exception 'no_conflict_reservation';
  end if;

  if coalesce((v_ctx->>'isSameUserConsecutive')::boolean, false) then
    raise exception 'same_user_consecutive';
  end if;

  if (v_ctx->>'nextReservationId') <> nullif(trim(p_victim_reservation_id), '') then
    raise exception 'victim_mismatch';
  end if;

  v_start := (v_ctx->>'nextStartAt')::timestamptz;
  if v_start is null or v_start > v_now then
    raise exception 'next_start_not_reached';
  end if;

  select *
  into v_victim
  from public.reservations r
  where r.id::text = nullif(trim(p_victim_reservation_id), '')
  for update;

  if not found then
    raise exception 'victim_reservation_not_found';
  end if;

  if v_victim.status not in ('confirmed', 'pending') then
    raise exception 'invalid_victim_status';
  end if;

  v_end := coalesce(v_blocking.end_at, v_blocking.end_time);
  v_start := coalesce(v_victim.start_at, v_victim.start_time);

  if v_victim.vehicle_id is distinct from v_blocking.vehicle_id
    or v_start is null
    or v_end is null
    or v_start <= v_end
    or v_start > v_end + interval '30 minutes' then
    raise exception 'conflict_window_invalid';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    cancel_reason = 'overdue_conflict',
    cancelled_at = v_now,
    is_no_show = false,
    refund_amount = 0,
    updated_at = v_now
  where id = v_victim.id;

  update public.reservations
  set
    overdue_next_reservation_cancelled_at = v_now,
    updated_at = v_now
  where id = v_blocking.id;

  v_paid := public.reservation_card_paid_amount(p_victim_reservation_id);

  return jsonb_build_object(
    'ok', true,
    'victimReservationId', v_victim.id::text,
    'victimUserId', v_victim.user_id,
    'blockingReservationId', v_blocking.id::text,
    'paymentKey', v_victim.payment_key,
    'orderId', v_victim.order_id,
    'paidAmount', v_paid,
    'vehicleId', v_victim.vehicle_id::text
  );
end;
$$;

-- ── 본인 연속 예약: 다음 start_at 도달 시 자동 반납 + 초과요금 ──
create or replace function public.auto_return_same_user_consecutive_overdue_for_service(
  p_overdue_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_ctx jsonb;
  v_row public.reservations%rowtype;
  v_scheduled_end timestamptz;
  v_return_at timestamptz;
  v_next_start timestamptz;
  v_overage jsonb;
begin
  v_ctx := public.find_next_overdue_conflict_reservation(p_overdue_reservation_id);
  if v_ctx is null then
    return jsonb_build_object('ok', false, 'reason', 'no_conflict');
  end if;

  if coalesce((v_ctx->>'isSameUserConsecutive')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'reason', 'not_same_user');
  end if;

  v_next_start := (v_ctx->>'nextStartAt')::timestamptz;
  if v_next_start is null or v_next_start > v_now then
    return jsonb_build_object('ok', false, 'reason', 'next_start_not_reached');
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id::text = nullif(trim(p_overdue_reservation_id), '')
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status <> 'in_use'
    or coalesce(v_row.is_overdue, false) = false then
    return jsonb_build_object('ok', false, 'reason', 'not_overdue_in_use');
  end if;

  if v_row.returned_at is not null or v_row.status = 'returned' then
    return jsonb_build_object('ok', false, 'reason', 'already_returned', 'alreadyReturned', true);
  end if;

  v_scheduled_end := coalesce(v_row.end_at, v_row.end_time);
  if v_scheduled_end is null then
    raise exception 'invalid_end_time';
  end if;

  v_return_at := v_next_start;

  update public.reservations
  set
    status = 'returned',
    returned_at = v_return_at,
    actual_end_at = v_return_at,
    return_type = 'auto',
    updated_at = v_now
  where id = v_row.id;

  v_overage := public.apply_return_overdue_overage_for_service(
    p_overdue_reservation_id,
    v_scheduled_end,
    v_return_at,
    true
  );

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_row.id::text,
    'userId', v_row.user_id,
    'nextReservationId', v_ctx->>'nextReservationId',
    'returnedAt', v_return_at,
    'scheduledEndAt', v_scheduled_end,
    'overdueOverage', v_overage
  );
end;
$$;

revoke all on function public.auto_return_same_user_consecutive_overdue_for_service(text) from public;
grant execute on function public.auto_return_same_user_consecutive_overdue_for_service(text)
  to service_role;

comment on function public.auto_return_same_user_consecutive_overdue_for_service(text) is
  '본인 연속 예약: 다음 start_at 에 returned_at 설정 후 초과요금 billing-overdue-overage-charge 호출';
