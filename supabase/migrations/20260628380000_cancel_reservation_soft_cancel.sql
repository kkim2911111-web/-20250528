-- 예약 취소 — DELETE 대신 status = 'cancelled' (취소 탭 order_id 조인·예약번호 표시 유지)

drop function if exists public.cancel_reservation_for_me(uuid, uuid);

create or replace function public.cancel_reservation_for_me(
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
  v_row public.reservations%rowtype;
  v_start timestamptz;
  v_id text := nullif(trim(p_reservation_id), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id::text = v_id
    and r.user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status not in ('confirmed', 'pending') then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_row.start_at, v_row.start_time);
  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_start <= now() + interval '1 hour' then
    raise exception 'cancel_too_late';
  end if;

  update public.reservations
  set status = 'cancelled', updated_at = now()
  where id::text = v_id
    and user_id = v_user;

  if v_row.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = now()
    where order_id = v_row.order_id
      and user_id = v_user;
  end if;

  return jsonb_build_object(
    'reservationId', v_id,
    'cancelled', true,
    'orderId', v_row.order_id,
    'paymentKey', v_row.payment_key,
    'totalPrice', v_row.total_price
  );
end;
$$;

revoke all on function public.cancel_reservation_for_me(text, uuid) from public;
grant execute on function public.cancel_reservation_for_me(text, uuid) to authenticated;
grant execute on function public.cancel_reservation_for_me(text, uuid) to service_role;

comment on function public.cancel_reservation_for_me(text, uuid) is
  '예약 취소 — status=cancelled 유지(행 삭제 없음), payment_orders 동기 취소';
