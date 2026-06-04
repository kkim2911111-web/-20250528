-- 예약 결제 — 쿠폰/포인트 (payment_orders 메타 + prepare + 사용 RPC)

drop function if exists public.prepare_payment_order(text, text, timestamptz, timestamptz, integer);

alter table public.payment_orders
  add column if not exists user_coupon_id uuid references public.user_coupons(id) on delete set null;

alter table public.payment_orders
  add column if not exists points_used integer not null default 0 check (points_used >= 0);

alter table public.payment_orders
  add column if not exists original_price integer check (original_price is null or original_price >= 0);

create or replace function public.prepare_payment_order(
  p_vehicle_id text,
  p_vehicle_name text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer,
  p_user_coupon_id text default null,
  p_points_used integer default 0,
  p_original_price integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_name text;
  v_order_id text;
  v_order_name text;
  v_coupon_uuid uuid;
  v_orig integer;
  v_pts integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if p_total_price is null or p_total_price < 0 then
    raise exception 'invalid_price';
  end if;

  v_pts := greatest(coalesce(p_points_used, 0), 0);
  v_orig := coalesce(p_original_price, p_total_price + v_pts);

  if p_user_coupon_id is not null and trim(p_user_coupon_id) <> '' then
    v_coupon_uuid := trim(p_user_coupon_id)::uuid;
    if not exists (
      select 1
      from public.user_coupons uc
      where uc.id = v_coupon_uuid
        and uc.user_id = v_user
        and coalesce(uc.is_used, false) = false
    ) then
      raise exception 'invalid_coupon';
    end if;
  else
    v_coupon_uuid := null;
  end if;

  if v_pts > 0 then
    if not exists (
      select 1
      from public.user_profiles up
      where up.user_id = v_user
        and coalesce(up.points, 0) >= v_pts
    ) then
      raise exception 'insufficient_points';
    end if;
  end if;

  select r.complex_id into v_complex_id
  from public.residents r
  where r.user_id = v_user and r.approved = true;

  if v_complex_id is null then
    raise exception 'not_approved';
  end if;

  if not exists (
    select 1
    from public.vehicles v
    where v.id::text = p_vehicle_id
      and v.complex_id = v_complex_id
  ) then
    raise exception 'vehicle_not_in_complex';
  end if;

  if exists (
    select 1 from public.reservations r
    where r.vehicle_id::text = p_vehicle_id
      and coalesce(r.status, 'pending') in ('pending', 'confirmed', 'in_use')
      and coalesce(r.start_time, r.start_at) < p_end_time
      and coalesce(r.end_time, r.end_at) > p_start_time
  ) then
    raise exception 'time_overlap';
  end if;

  select coalesce(p_vehicle_name, v.model_name, '단지카') into v_vehicle_name
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  v_order_id := 'danji_' || floor(extract(epoch from now()) * 1000)::bigint
    || '_' || substr(md5(random()::text), 1, 8);
  v_order_name := v_vehicle_name || ' 예약';

  insert into public.payment_orders (
    order_id, user_id, vehicle_id, vehicle_name,
    start_time, end_time, total_price, status,
    user_coupon_id, points_used, original_price
  ) values (
    v_order_id, v_user, p_vehicle_id, v_vehicle_name,
    p_start_time, p_end_time, p_total_price, 'pending',
    v_coupon_uuid, v_pts, v_orig
  );

  return jsonb_build_object(
    'orderId', v_order_id,
    'amount', p_total_price,
    'orderName', v_order_name,
    'customerKey', v_user::text
  );
end;
$$;

create or replace function public.consume_user_coupon_for_me(
  p_user_coupon_id text,
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_uc_id uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_coupon_id is null or trim(p_user_coupon_id) = '' then
    return jsonb_build_object('ok', true, 'skipped', true);
  end if;

  v_uc_id := trim(p_user_coupon_id)::uuid;

  update public.user_coupons
  set
    is_used = true,
    used_at = coalesce(used_at, now())
  where id = v_uc_id
    and user_id = v_user
    and coalesce(is_used, false) = false;

  if not found then
    raise exception 'coupon_not_available';
  end if;

  return jsonb_build_object('ok', true, 'userCouponId', v_uc_id::text);
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

  update public.user_profiles
  set points = points - v_pts
  where user_id = v_user;

  insert into public.point_history (user_id, amount, type, description)
  values (
    v_user,
    -v_pts,
    'use',
    coalesce('예약 결제 사용 · ' || nullif(trim(p_reservation_id), ''), '예약 결제 사용')
  );

  return jsonb_build_object('ok', true, 'spent', v_pts);
end;
$$;

revoke all on function public.prepare_payment_order(text, text, timestamptz, timestamptz, integer, text, integer, integer) from public;
grant execute on function public.prepare_payment_order(text, text, timestamptz, timestamptz, integer, text, integer, integer) to authenticated;

revoke all on function public.consume_user_coupon_for_me(text, text) from public;
grant execute on function public.consume_user_coupon_for_me(text, text) to authenticated;

revoke all on function public.spend_booking_points_for_me(uuid, text, integer) from public;
grant execute on function public.spend_booking_points_for_me(uuid, text, integer) to authenticated;
