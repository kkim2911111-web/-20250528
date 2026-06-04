-- 포인트 내역 reservation_id, spend 설명 개선, 취소 시 쿠폰 복구

alter table public.point_history
  add column if not exists reservation_id text;

create index if not exists point_history_reservation_id_idx
  on public.point_history (reservation_id)
  where reservation_id is not null;

-- 예약 id → 차량명 (포인트 description용)
create or replace function public._booking_vehicle_name_for_reservation(
  p_user_id uuid,
  p_reservation_id text
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rid text := nullif(trim(p_reservation_id), '');
  v_name text;
begin
  if v_rid is null then
    return null;
  end if;

  select coalesce(v.model_name, po.vehicle_name, '차량')
  into v_name
  from public.reservations r
  left join public.vehicles v on v.id::text = r.vehicle_id::text
  left join public.payment_orders po
    on po.user_id = r.user_id
   and (
     po.reservation_id::text = v_rid
     or (r.order_id is not null and po.order_id = r.order_id)
   )
  where r.id::text = v_rid
    and r.user_id = p_user_id
  limit 1;

  return nullif(trim(v_name), '');
end;
$$;

create or replace function public.spend_booking_points_for_me(
  p_user_id uuid,
  p_reservation_id text,
  p_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_pts integer;
  v_balance integer;
  v_rid text := nullif(trim(p_reservation_id), '');
  v_vehicle text;
  v_desc text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is distinct from v_user then
    raise exception 'forbidden';
  end if;

  v_pts := greatest(coalesce(p_points, 0), 0);
  if v_pts = 0 then
    return jsonb_build_object('ok', true, 'skipped', true);
  end if;

  select coalesce(up.points, 0) into v_balance
  from public.user_profiles up
  where up.user_id = v_user
  for update;

  if not found or v_balance < v_pts then
    raise exception 'insufficient_points';
  end if;

  v_vehicle := public._booking_vehicle_name_for_reservation(v_user, v_rid);
  v_desc := '포인트 사용 · ' || coalesce(v_vehicle, '차량');

  update public.user_profiles
  set points = points - v_pts
  where user_id = v_user;

  insert into public.point_history (
    user_id, amount, type, description, reservation_id
  )
  values (
    v_user,
    -v_pts,
    'use',
    v_desc,
    v_rid
  );

  return jsonb_build_object('ok', true, 'spent', v_pts, 'description', v_desc);
end;
$$;

create or replace function public.restore_user_coupon(
  p_user_id uuid,
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_rid text := nullif(trim(p_reservation_id), '');
  v_coupon_id uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is distinct from v_user then
    raise exception 'forbidden';
  end if;

  if v_rid is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_reservation_id');
  end if;

  select po.user_coupon_id into v_coupon_id
  from public.payment_orders po
  where po.user_id = p_user_id
    and po.user_coupon_id is not null
    and (
      po.reservation_id::text = v_rid
      or exists (
        select 1
        from public.reservations r
        where r.id::text = v_rid
          and r.user_id = p_user_id
          and r.order_id is not null
          and po.order_id = r.order_id
      )
    )
  order by po.updated_at desc nulls last, po.created_at desc
  limit 1;

  if v_coupon_id is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_coupon_on_order');
  end if;

  update public.user_coupons
  set
    is_used = false,
    used_at = null
  where id = v_coupon_id
    and user_id = p_user_id;

  return jsonb_build_object('ok', true, 'userCouponId', v_coupon_id::text);
end;
$$;

revoke all on function public.restore_user_coupon(uuid, text) from public;
grant execute on function public.restore_user_coupon(uuid, text) to authenticated;

revoke all on function public.spend_booking_points_for_me(uuid, text, integer) from public;
grant execute on function public.spend_booking_points_for_me(uuid, text, integer) to authenticated;
