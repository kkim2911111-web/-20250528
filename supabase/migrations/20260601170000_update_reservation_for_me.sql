-- 예약 변경 RPC (본인 confirmed/pending, 대여 시작 1시간 전, 겹침 제외)

create or replace function public.update_reservation_for_me(
  p_reservation_id text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row record;
  v_vehicle_id text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  select
    r.id,
    r.user_id,
    r.vehicle_id::text,
    r.status,
    coalesce(r.start_time, r.start_at) as start_at,
    r.order_id
  into v_row
  from public.reservations r
  where r.id::text = p_reservation_id
    and r.user_id = v_user;

  if v_row.id is null then
    raise exception 'reservation_not_found';
  end if;

  if coalesce(v_row.status, '') not in ('pending', 'confirmed') then
    raise exception 'invalid_status';
  end if;

  if v_row.start_at is not null
     and now() >= v_row.start_at - interval '1 hour' then
    raise exception 'change_too_late';
  end if;

  v_vehicle_id := v_row.vehicle_id;

  if not public.is_vehicle_in_my_complex(v_vehicle_id) then
    raise exception 'vehicle_not_in_complex';
  end if;

  if public.reservations_overlap_exists(
    v_vehicle_id, p_start_time, p_end_time, p_reservation_id, null
  ) then
    raise exception 'time_overlap';
  end if;

  update public.reservations
  set
    start_time = p_start_time,
    end_time = p_end_time,
    start_at = p_start_time,
    end_at = p_end_time,
    total_price = coalesce(p_total_price, total_price),
    updated_at = now()
  where id::text = p_reservation_id
    and user_id = v_user;

  if v_row.order_id is not null then
    update public.payment_orders
    set
      start_time = p_start_time,
      end_time = p_end_time,
      total_price = coalesce(p_total_price, total_price),
      updated_at = now()
    where order_id = v_row.order_id
      and user_id = v_user;
  end if;

  return jsonb_build_object(
    'id', p_reservation_id,
    'status', v_row.status
  );
end;
$$;

revoke all on function public.update_reservation_for_me(text, timestamptz, timestamptz, integer)
  from public;
grant execute on function public.update_reservation_for_me(text, timestamptz, timestamptz, integer)
  to authenticated, service_role;
