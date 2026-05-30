-- ============================================================
-- 결제 성공 후 reservations 최종 저장 (스키마 자동 대응)
-- Supabase SQL Editor → Run
-- 선행: fix_reservation_insert.sql 권장
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

  if exists (
    select 1
    from public.reservations r
    where r.vehicle_id::text = v_order.vehicle_id::text
      and coalesce(r.status, 'pending') in ('pending', 'confirmed', 'in_use')
      and coalesce(r.start_time, r.start_at) < v_order.end_time
      and coalesce(r.end_time, r.end_at) > v_order.start_time
      and (r.order_id is null or r.order_id <> p_order_id)
  ) then
    update public.payment_orders
    set status = 'cancelled', updated_at = now()
    where order_id = p_order_id;
    raise exception 'time_overlap';
  end if;

  -- reservations.vehicle_id 타입 기준 (vehicles.id 와 다를 수 있음)
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
grant execute on function public.finalize_reservation_after_payment(text, text, integer, uuid) to authenticated;
grant execute on function public.finalize_reservation_after_payment(text, text, integer, uuid) to service_role;

create unique index if not exists reservations_order_id_unique
  on public.reservations (order_id)
  where order_id is not null;

alter table public.reservations add column if not exists order_id text;
alter table public.reservations add column if not exists payment_key text;
alter table public.reservations add column if not exists payment_status text;
alter table public.reservations add column if not exists start_time timestamptz;
alter table public.reservations add column if not exists end_time timestamptz;
alter table public.reservations add column if not exists start_at timestamptz;
alter table public.reservations add column if not exists end_at timestamptz;
alter table public.reservations add column if not exists total_price integer not null default 0;

-- status 제약 완화 (confirmed 저장 허용)
alter table public.reservations drop constraint if exists reservations_status_check;
alter table public.reservations add constraint reservations_status_check
  check (status in ('pending', 'confirmed', 'in_use', 'returned', 'completed', 'cancelled'));
