-- 관리자: 노쇼의심(confirmed + 시작시각 경과) 예약 강제 취소

create or replace function public.cancel_reservation_for_staff(
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
  v_start timestamptz;
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

  if v_res.status <> 'confirmed' then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_res.start_at, v_res.start_time);
  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_start > v_now then
    raise exception 'not_no_show_suspect';
  end if;

  update public.reservations
  set status = 'cancelled', updated_at = v_now
  where id = v_res.id;

  if v_res.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = v_now
    where order_id = v_res.order_id;
  end if;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'cancelled'
  );
end;
$$;

revoke all on function public.cancel_reservation_for_staff(text) from public;
grant execute on function public.cancel_reservation_for_staff(text) to authenticated;
