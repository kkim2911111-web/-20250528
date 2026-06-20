-- in_use 미반납 시 end_at 경과 후에도 차량 점유 유지 (예약 가능 목록·결제 겹침 방지)

create or replace function public.reservation_effective_end(
  p_status text,
  p_end timestamptz,
  p_actual_end timestamptz,
  p_returned_at timestamptz
)
returns timestamptz
language sql
stable
as $$
  select case
    when lower(trim(coalesce(p_status, ''))) = 'in_use' then
      'infinity'::timestamptz
    when lower(trim(coalesce(p_status, ''))) in ('returned', 'completed', 'cancelled') then
      coalesce(p_actual_end, p_returned_at, p_end)
    else
      p_end
  end;
$$;

comment on function public.reservation_effective_end(text, timestamptz, timestamptz, timestamptz) is
  '겹침 검사용 실효 종료. in_use는 반납 전까지 무기한 점유(infinity).';

-- prepare_payment_order — 인라인 end_at 비교 → 공통 겹침 함수
create or replace function public.prepare_payment_order(
  p_vehicle_id text,
  p_vehicle_name text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer,
  p_user_coupon_id text default null,
  p_points_used integer default 0,
  p_original_price integer default null,
  p_rental_type text default 'hourly'
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
  v_base integer;
  v_rental_type text := lower(trim(coalesce(p_rental_type, 'hourly')));
  v_booking_key text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_resident_maintenance_allowed(v_user);
  perform public.assert_app_feature_enabled('payment', v_user);

  v_booking_key := public.booking_feature_key_for_rental_type(v_rental_type);
  if v_booking_key is not null then
    perform public.assert_app_feature_enabled(v_booking_key, v_user);
  end if;

  perform public.assert_user_not_blacklisted(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if p_total_price is null or p_total_price < 0 then
    raise exception 'invalid_price';
  end if;

  if v_rental_type not in ('hourly', 'daily', 'monthly') then
    raise exception 'invalid_rental_type';
  end if;

  v_pts := greatest(coalesce(p_points_used, 0), 0);

  v_base := public.calc_rental_base_price(
    p_vehicle_id,
    v_rental_type,
    p_start_time,
    p_end_time
  );

  if p_original_price is null then
    raise exception 'original_price_required';
  end if;

  if p_original_price <> v_base then
    raise exception 'price_mismatch';
  end if;

  v_orig := p_original_price;

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

  perform public.assert_vehicle_bookable(p_vehicle_id);

  if public.reservations_overlap_exists(
    p_vehicle_id, p_start_time, p_end_time, null, null
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
    user_coupon_id, points_used, original_price, rental_type
  ) values (
    v_order_id, v_user, p_vehicle_id, v_vehicle_name,
    p_start_time, p_end_time, p_total_price, 'pending',
    v_coupon_uuid, v_pts, v_orig, v_rental_type
  );

  return jsonb_build_object(
    'orderId', v_order_id,
    'amount', p_total_price,
    'orderName', v_order_name,
    'customerKey', v_user::text
  );
end;
$$;

-- DB exclude — in_use도 반납 전까지 겹침 방지
alter table public.reservations
  drop constraint if exists reservations_no_overlap_active;

alter table public.reservations
  add constraint reservations_no_overlap_active
  exclude using gist (
    vehicle_id with =,
    tstzrange(
      coalesce(start_at, start_time),
      case
        when status = 'in_use' then 'infinity'::timestamptz
        else coalesce(end_at, end_time)
      end,
      '[)'
    ) with &&
  )
  where (status in ('pending', 'confirmed', 'in_use'));
