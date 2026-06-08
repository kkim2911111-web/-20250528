-- 관리자 예약: 강제반납(in_use→returned), 강제결제취소(CS 환불+취소)

drop function if exists public.force_return_reservation_for_staff(text);
drop function if exists public.force_payment_cancel_reservation_for_staff(text, uuid);
drop function if exists public.force_payment_cancel_reservation_for_staff(text);

-- in_use 예약 → returned (반납 검수 화면)
create or replace function public.force_return_reservation_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_res public.reservations%rowtype;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status <> 'in_use' then
    raise exception 'invalid_status';
  end if;

  update public.reservations
  set
    status = 'returned',
    returned_at = coalesce(v_res.returned_at, v_now),
    actual_end_at = coalesce(
      v_res.actual_end_at,
      v_res.returned_at,
      coalesce(v_res.end_at, v_res.end_time),
      v_now
    ),
    return_type = 'manual',
    updated_at = v_now
  where id = v_res.id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'returned'
  );
end;
$$;

-- CS 강제결제취소 — Edge Function(토스 환불) 후 DB 반영
create or replace function public.force_payment_cancel_reservation_for_staff(
  p_reservation_id text,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_id text := nullif(trim(p_reservation_id), '');
  v_res public.reservations%rowtype;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is not null
    and p_user_id is distinct from auth.uid()
    and coalesce(current_setting('role', true), '') <> 'service_role' then
    raise exception 'forbidden';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status not in ('confirmed', 'in_use') then
    raise exception 'invalid_status';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    updated_at = v_now
  where id = v_res.id;

  if v_res.order_id is not null then
    update public.payment_orders
    set
      status = 'cancelled',
      updated_at = v_now
    where order_id = v_res.order_id;
  end if;

  update public.vehicles
  set
    is_available = true,
    updated_at = v_now
  where id = v_res.vehicle_id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'cancelled',
    'orderId', v_res.order_id,
    'paymentKey', v_res.payment_key,
    'totalPrice', v_res.total_price
  );
end;
$$;

revoke all on function public.force_return_reservation_for_staff(text) from public;
grant execute on function public.force_return_reservation_for_staff(text) to authenticated;

revoke all on function public.force_payment_cancel_reservation_for_staff(text, uuid) from public;
grant execute on function public.force_payment_cancel_reservation_for_staff(text, uuid) to authenticated;
grant execute on function public.force_payment_cancel_reservation_for_staff(text, uuid) to service_role;

comment on function public.force_return_reservation_for_staff(text) is
  '관리자 강제반납 — in_use 예약을 returned 로 전환(반납 검수)';

comment on function public.force_payment_cancel_reservation_for_staff(text, uuid) is
  '관리자 CS 강제결제취소 — confirmed/in_use 예약 취소, payment_orders 취소, 차량 가용';
