-- ============================================================
-- 결제 성공 후 reservations 최종 저장
-- paymentKey, orderId, payment_status 포함
-- Supabase SQL Editor → Run
-- ============================================================

create or replace function public.finalize_reservation_after_payment(
  p_payment_key text,
  p_order_id text,
  p_amount integer,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_order record;
  v_res_id text;
  v_vehicle_id_type text;
  v_sql text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_payment_key is null or length(trim(p_payment_key)) = 0 then
    raise exception 'invalid_payment_key';
  end if;

  if p_order_id is null or length(trim(p_order_id)) = 0 then
    raise exception 'invalid_order_id';
  end if;

  select *
  into v_order
  from public.payment_orders
  where order_id = p_order_id
    and user_id = v_user
  for update;

  if not found then
    raise exception 'order_not_found';
  end if;

  -- 이미 처리된 주문 (재진입 / 새로고침)
  if v_order.status = 'paid' and v_order.reservation_id is not null then
    return jsonb_build_object(
      'reservationId', v_order.reservation_id::text,
      'orderId', p_order_id,
      'paymentKey', coalesce(v_order.payment_key, p_payment_key),
      'alreadyPaid', true
    );
  end if;

  if v_order.status <> 'pending' then
    raise exception 'invalid_order_status';
  end if;

  if v_order.total_price <> p_amount then
    raise exception 'amount_mismatch';
  end if;

  if exists (
    select 1
    from public.reservations r
    where r.vehicle_id::text = v_order.vehicle_id
      and coalesce(r.status, 'pending') in ('pending', 'confirmed')
      and coalesce(r.start_time, r.start_at) < v_order.end_time
      and coalesce(r.end_time, r.end_at) > v_order.start_time
  ) then
    update public.payment_orders
    set status = 'cancelled', updated_at = now()
    where order_id = p_order_id;
    raise exception 'time_overlap';
  end if;

  select c.data_type
  into v_vehicle_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'vehicles'
    and c.column_name = 'id';

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id,
      vehicle_id,
      start_time,
      end_time,
      start_at,
      end_at,
      total_price,
      status,
      payment_key,
      order_id,
      payment_status
    ) values (
      $1,
      $2::%s,
      $3,
      $4,
      $5,
      $6,
      $7,
      'confirmed',
      $8,
      $9,
      'paid'
    )
    returning id::text
    $f$,
    v_vehicle_id_type
  );

  execute v_sql
    using
      v_user,
      v_order.vehicle_id,
      v_order.start_time,
      v_order.end_time,
      v_order.start_time,
      v_order.end_time,
      v_order.total_price,
      p_payment_key,
      p_order_id
    into v_res_id;

  update public.payment_orders
  set
    status = 'paid',
    payment_key = p_payment_key,
    reservation_id = v_res_id::uuid,
    updated_at = now()
  where order_id = p_order_id;

  return jsonb_build_object(
    'reservationId', v_res_id,
    'orderId', p_order_id,
    'paymentKey', p_payment_key,
    'vehicleName', v_order.vehicle_name,
    'totalPrice', v_order.total_price
  );
end;
$$;

revoke all on function public.finalize_reservation_after_payment(text, text, integer, uuid) from public;
grant execute on function public.finalize_reservation_after_payment(text, text, integer, uuid) to authenticated;
grant execute on function public.finalize_reservation_after_payment(text, text, integer, uuid) to service_role;

-- order_id로 예약 조회 (중복 저장 확인용)
create unique index if not exists reservations_order_id_unique
  on public.reservations (order_id)
  where order_id is not null;
