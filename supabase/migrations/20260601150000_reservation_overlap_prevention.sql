-- ============================================================
-- Stage 3: 중복 예약 방지 강화
-- - start_at ↔ start_time, end_at ↔ end_time 동기화 트리거
-- - pending / confirmed / in_use DB exclude 제약
-- - 겹침 검사 공통 함수 + RPC 정렬 (면허 검증 유지)
-- ============================================================

create extension if not exists btree_gist;

-- ── 1) 중도반납 실효 종료 (없으면 생성) ─────────────────────
create or replace function public.reservation_effective_end(
  p_status text,
  p_end timestamptz,
  p_actual_end timestamptz,
  p_returned_at timestamptz
)
returns timestamptz
language sql
immutable
as $$
  select case
    when p_status in ('returned', 'completed', 'cancelled') then
      coalesce(p_actual_end, p_returned_at, p_end)
    else
      p_end
  end;
$$;

-- ── 2) start/end 컬럼 동기화 트리거 ─────────────────────────
create or replace function public.sync_reservation_time_columns()
returns trigger
language plpgsql
as $$
begin
  new.start_at := coalesce(new.start_at, new.start_time);
  new.start_time := coalesce(new.start_time, new.start_at);
  new.end_at := coalesce(new.end_at, new.end_time);
  new.end_time := coalesce(new.end_time, new.end_at);
  return new;
end;
$$;

drop trigger if exists reservations_sync_time_columns on public.reservations;
create trigger reservations_sync_time_columns
before insert or update of start_at, start_time, end_at, end_time
on public.reservations
for each row
execute function public.sync_reservation_time_columns();

-- 기존 행 보정
update public.reservations
set
  start_at = coalesce(start_at, start_time),
  start_time = coalesce(start_time, start_at),
  end_at = coalesce(end_at, end_time),
  end_time = coalesce(end_time, end_at)
where start_at is null
   or start_time is null
   or end_at is null
   or end_time is null;

-- ── 3) 겹침 검사 공통 함수 ───────────────────────────────────
create or replace function public.reservations_overlap_exists(
  p_vehicle_id text,
  p_start timestamptz,
  p_end timestamptz,
  p_exclude_reservation_id text default null,
  p_exclude_order_id text default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.reservations r
    where r.vehicle_id::text = p_vehicle_id
      and coalesce(r.status, 'pending') in ('pending', 'confirmed', 'in_use')
      and (p_exclude_reservation_id is null or r.id::text <> p_exclude_reservation_id)
      and (p_exclude_order_id is null or r.order_id is distinct from p_exclude_order_id)
      and coalesce(r.start_time, r.start_at) < p_end
      and public.reservation_effective_end(
            r.status,
            coalesce(r.end_time, r.end_at),
            r.actual_end_at,
            r.returned_at
          ) > p_start
  );
$$;

revoke all on function public.reservations_overlap_exists(text, timestamptz, timestamptz, text, text)
  from public;
grant execute on function public.reservations_overlap_exists(text, timestamptz, timestamptz, text, text)
  to authenticated, service_role;

-- 앱 클라이언트용 (본인 단지 차량만)
create or replace function public.check_vehicle_time_overlap_for_me(
  p_vehicle_id text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_exclude_reservation_id text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if not public.is_vehicle_in_my_complex(p_vehicle_id) then
    raise exception 'vehicle_not_in_complex';
  end if;

  return public.reservations_overlap_exists(
    p_vehicle_id,
    p_start_time,
    p_end_time,
    p_exclude_reservation_id,
    null
  );
end;
$$;

revoke all on function public.check_vehicle_time_overlap_for_me(text, timestamptz, timestamptz, text)
  from public;
grant execute on function public.check_vehicle_time_overlap_for_me(text, timestamptz, timestamptz, text)
  to authenticated;

-- ── 4) DB exclude — active 예약끼리 겹침 방지 ───────────────
alter table public.reservations
  drop constraint if exists reservations_no_overlap_confirmed;

alter table public.reservations
  drop constraint if exists reservations_no_overlap;

alter table public.reservations
  drop constraint if exists reservations_no_overlap_active;

alter table public.reservations
  add constraint reservations_no_overlap_active
  exclude using gist (
    vehicle_id with =,
    tstzrange(
      coalesce(start_at, start_time),
      coalesce(end_at, end_time),
      '[)'
    ) with &&
  )
  where (status in ('pending', 'confirmed', 'in_use'));

-- ── 5) prepare_payment_order — 겹침 + 면허 검증 ─────────────
create or replace function public.prepare_payment_order(
  p_vehicle_id text,
  p_vehicle_name text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer
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
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_booking_license_verified(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if p_total_price is null or p_total_price <= 0 then
    raise exception 'invalid_price';
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
    start_time, end_time, total_price, status
  ) values (
    v_order_id, v_user, p_vehicle_id, v_vehicle_name,
    p_start_time, p_end_time, p_total_price, 'pending'
  );

  return jsonb_build_object(
    'orderId', v_order_id,
    'amount', p_total_price,
    'orderName', v_order_name,
    'customerKey', v_user::text
  );
end;
$$;

-- ── 6) create_reservation_for_me — 겹침 + 면허 검증 ─────────
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

-- ── 7) finalize_reservation_after_payment — 겹침 정렬 ───────
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
  v_has_start_time boolean;
  v_has_start_at boolean;
  v_has_payment_key boolean;
  v_has_order_id boolean;
  v_has_payment_status boolean;
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

  select r.id::text
  into v_res_id
  from public.reservations r
  where r.order_id = p_order_id
    and r.user_id = v_user
  limit 1;

  if v_res_id is not null then
    return jsonb_build_object(
      'reservationId', v_res_id,
      'orderId', p_order_id,
      'paymentKey', p_payment_key,
      'alreadyPaid', true
    );
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

  if v_order.status in ('paid', 'confirmed') and v_order.reservation_id is not null then
    return jsonb_build_object(
      'reservationId', v_order.reservation_id::text,
      'orderId', p_order_id,
      'paymentKey', coalesce(v_order.payment_key, p_payment_key),
      'alreadyPaid', true
    );
  end if;

  if v_order.status not in ('pending', 'failed', 'paid', 'confirmed') then
    raise exception 'invalid_order_status';
  end if;

  if v_order.total_price <> p_amount then
    raise exception 'amount_mismatch';
  end if;

  if public.reservations_overlap_exists(
    v_order.vehicle_id::text,
    v_order.start_time,
    v_order.end_time,
    null,
    p_order_id
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
    and c.table_name = 'reservations'
    and c.column_name = 'vehicle_id';

  if v_vehicle_id_type is null then
    select c.data_type
    into v_vehicle_id_type
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'vehicles'
      and c.column_name = 'id';
  end if;

  if v_vehicle_id_type is null then
    v_vehicle_id_type := 'text';
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'start_time'
  ) into v_has_start_time;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'start_at'
  ) into v_has_start_at;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'payment_key'
  ) into v_has_payment_key;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'order_id'
  ) into v_has_order_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations' and column_name = 'payment_status'
  ) into v_has_payment_status;

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id,
      vehicle_id,
      total_price,
      status
      %s%s%s%s%s
    ) values (
      %L,
      %L::%s,
      %s,
      'confirmed'
      %s%s%s%s%s
    )
    returning id::text
    $f$,
    case when v_has_start_time then ', start_time, end_time' else '' end,
    case when v_has_start_at then ', start_at, end_at' else '' end,
    case when v_has_payment_key then ', payment_key' else '' end,
    case when v_has_order_id then ', order_id' else '' end,
    case when v_has_payment_status then ', payment_status' else '' end,
    v_user,
    v_order.vehicle_id,
    v_vehicle_id_type,
    v_order.total_price,
    case when v_has_start_time then format(', %L, %L', v_order.start_time, v_order.end_time) else '' end,
    case when v_has_start_at then format(', %L, %L', v_order.start_time, v_order.end_time) else '' end,
    case when v_has_payment_key then format(', %L', p_payment_key) else '' end,
    case when v_has_order_id then format(', %L', p_order_id) else '' end,
    case when v_has_payment_status then format(', %L', 'paid') else '' end
  );

  execute v_sql into v_res_id;

  update public.payment_orders
  set
    status = 'paid',
    payment_key = p_payment_key,
    has_payment_key = true,
    updated_at = now()
  where order_id = p_order_id;

  begin
    update public.payment_orders
    set reservation_id = v_res_id::uuid
    where order_id = p_order_id
      and v_res_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  exception
    when others then
      null;
  end;

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
grant execute on function public.finalize_reservation_after_payment(text, text, integer, uuid)
  to authenticated, service_role;

-- ============================================================
-- 확인:
-- select conname from pg_constraint
-- where conrelid = 'public.reservations'::regclass and conname like '%overlap%';
--
-- select public.check_vehicle_time_overlap_for_me(
--   '<vehicle_id>', now() + interval '1 hour', now() + interval '3 hours'
-- );
-- ============================================================
