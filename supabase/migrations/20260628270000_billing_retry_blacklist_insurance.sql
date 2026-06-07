-- 결제 재시도 · 블랙리스트 예약취소 · 보험 만료 예약 차단

-- ── 1) billing_charge_retries ─────────────────────────────────
create table if not exists public.billing_charge_retries (
  id uuid primary key default gen_random_uuid(),
  charge_type text not null check (charge_type in ('deductible', 'extension')),
  reservation_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  complex_id uuid references public.complexes(id) on delete set null,
  amount integer not null check (amount >= 0),
  extension_hours integer check (extension_hours is null or extension_hours >= 1),
  retry_count integer not null default 0 check (retry_count >= 0),
  max_retries integer not null default 3 check (max_retries >= 1),
  next_retry_at timestamptz not null,
  last_error text,
  status text not null default 'pending'
    check (status in ('pending', 'succeeded', 'exhausted', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists billing_charge_retries_pending_idx
  on public.billing_charge_retries (status, next_retry_at)
  where status = 'pending';

create unique index if not exists billing_charge_retries_active_uniq
  on public.billing_charge_retries (charge_type, reservation_id, coalesce(extension_hours, 0))
  where status = 'pending';

alter table public.billing_charge_retries enable row level security;

-- ── 2) vehicles — 보험 만료 7일 전 알림 기록 ─────────────────
alter table public.vehicles
  add column if not exists insurance_warn_7d_sent_at date;

comment on column public.vehicles.insurance_warn_7d_sent_at is
  '보험 만료 7일 전 관리자 경고 푸시 발송일 (중복 방지)';

-- ── 3) 예약 가능 여부 검사 ───────────────────────────────────
create or replace function public.assert_user_not_blacklisted(p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.user_profiles up
    where up.user_id = p_user_id
      and coalesce(up.is_blacklisted, false) = true
  ) then
    raise exception 'user_blacklisted';
  end if;
end;
$$;

create or replace function public.assert_vehicle_bookable(p_vehicle_id text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  select
    v.id,
    coalesce(v.is_available, true) as is_available,
    v.insurance_expires_at
  into v_row
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  if not found then
    raise exception 'vehicle_not_found';
  end if;

  if v_row.is_available is not true then
    raise exception 'vehicle_unavailable';
  end if;

  if v_row.insurance_expires_at is not null
     and v_row.insurance_expires_at < (now() at time zone 'Asia/Seoul')::date then
    raise exception 'insurance_expired';
  end if;
end;
$$;

revoke all on function public.assert_user_not_blacklisted(uuid) from public;
revoke all on function public.assert_vehicle_bookable(text) from public;
grant execute on function public.assert_user_not_blacklisted(uuid) to authenticated, service_role;
grant execute on function public.assert_vehicle_bookable(text) to authenticated, service_role;

-- ── 4) prepare_payment_order — 블랙리스트·보험·가용성 ────────
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

  perform public.assert_user_not_blacklisted(v_user);

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

  perform public.assert_vehicle_bookable(p_vehicle_id);

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

-- ── 5) create_reservation_for_me — 동일 검사 ─────────────────
create or replace function public.create_reservation_for_me(
  p_vehicle_id text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_id_type text;
  v_res_id text;
  v_sql text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_user_not_blacklisted(v_user);
  perform public.assert_booking_license_verified(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  select r.complex_id into v_complex_id
  from public.residents r
  where r.user_id = v_user and r.approved = true;

  if v_complex_id is null then
    raise exception 'not_approved';
  end if;

  if not public.is_vehicle_in_my_complex(p_vehicle_id) then
    raise exception 'vehicle_not_in_complex';
  end if;

  perform public.assert_vehicle_bookable(p_vehicle_id);

  if public.reservations_overlap_exists(
    p_vehicle_id, p_start_time, p_end_time, null, null
  ) then
    raise exception 'time_overlap';
  end if;

  select c.data_type into v_vehicle_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'vehicles'
    and c.column_name = 'id';

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id, vehicle_id, start_time, end_time, start_at, end_at, total_price, status
    ) values (
      $1, $2::%s, $3, $4, $5, $6, $7, 'pending'
    ) returning id::text
    $f$,
    v_vehicle_id_type
  );

  execute v_sql
    using v_user, p_vehicle_id, p_start_time, p_end_time,
          p_start_time, p_end_time, coalesce(p_total_price, 0)
    into v_res_id;

  return jsonb_build_object('id', v_res_id, 'status', 'pending');
end;
$$;

-- ── 6) 블랙리스트 시 confirmed 예약 목록 (Edge Function용) ────
create or replace function public.list_confirmed_reservations_for_user(
  p_user_id uuid
)
returns table (
  reservation_id text,
  vehicle_name text,
  complex_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id::text,
    coalesce(v.model_name, '차량'),
    v.complex_id
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where r.user_id = p_user_id
    and r.status in ('confirmed', 'pending');
$$;

revoke all on function public.list_confirmed_reservations_for_user(uuid) from public;
grant execute on function public.list_confirmed_reservations_for_user(uuid) to service_role;

comment on function public.assert_vehicle_bookable(text) is
  '신규 예약 차단 — is_available=false 또는 보험 만료';

comment on function public.assert_user_not_blacklisted(uuid) is
  '블랙리스트 사용자 예약 차단';
