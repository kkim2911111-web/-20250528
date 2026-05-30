-- ============================================================
-- 중도반납 (early return) — reservations 스키마 + RPC
-- Supabase SQL Editor → Run
-- 선행: alter_reservations_rental_columns.sql, rental_rpcs.sql
-- ============================================================

-- ---------------------------------------------------------------------------
-- 1) 컬럼 추가
-- ---------------------------------------------------------------------------

alter table public.reservations
  add column if not exists actual_end_at timestamptz;

comment on column public.reservations.actual_end_at is
  '실제 이용 종료 시각. 반납(정상·중도) 시 returned_at 과 동일하게 설정. 겹침 검사에 사용.';

alter table public.reservations
  add column if not exists return_type text;

comment on column public.reservations.return_type is
  '반납 유형: normal(정시) | early(중도반납) | auto(시간 만료 자동종료)';

alter table public.reservations
  add column if not exists early_return_confirmed_at timestamptz;

comment on column public.reservations.early_return_confirmed_at is
  '중도반납 환불불가 동의 시각 (앱 확인 팝업)';

alter table public.reservations
  drop constraint if exists reservations_return_type_check;

alter table public.reservations
  add constraint reservations_return_type_check
  check (
    return_type is null
    or return_type in ('normal', 'early', 'auto')
  );

alter table public.reservations
  drop constraint if exists reservations_early_return_confirmed_check;

alter table public.reservations
  add constraint reservations_early_return_confirmed_check
  check (
    return_type is distinct from 'early'
    or early_return_confirmed_at is not null
  );

create index if not exists reservations_actual_end_at_idx
  on public.reservations (actual_end_at)
  where actual_end_at is not null;

-- ---------------------------------------------------------------------------
-- 2) 겹침 검사용 — 예약의 실효 종료 시각
--    (중도반납 후 end_at 은 예약 종료 그대로, actual_end_at 으로 슬롯 해제)
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- 3) complete_rental_for_me — 중도반납 파라미터 추가
--    status: in_use → returned
--    return_type: normal | early
-- ---------------------------------------------------------------------------

drop function if exists public.complete_rental_for_me(uuid, text[], integer, text, boolean, text, boolean, boolean);

create or replace function public.complete_rental_for_me(
  p_reservation_id text,
  p_return_photos text[],
  p_mileage_end integer,
  p_fuel_level_end text,
  p_is_accident boolean default false,
  p_accident_note text default null,
  p_is_early_return boolean default false,
  p_early_return_acknowledged boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_scheduled_end timestamptz;
  v_now timestamptz := now();
  v_return_type text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  if p_return_photos is null or cardinality(p_return_photos) < 1 then
    raise exception 'photos_required';
  end if;

  if cardinality(p_return_photos) > 10 then
    raise exception 'too_many_photos';
  end if;

  if p_mileage_end is null or p_mileage_end < 0 then
    raise exception 'invalid_mileage';
  end if;

  if p_fuel_level_end is null
    or p_fuel_level_end not in ('full', '3quarter', 'half', 'quarter', 'empty') then
    raise exception 'invalid_fuel_level';
  end if;

  if p_is_accident and (p_accident_note is null or length(trim(p_accident_note)) = 0) then
    raise exception 'accident_note_required';
  end if;

  if p_is_early_return and not p_early_return_acknowledged then
    raise exception 'early_return_not_acknowledged';
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

  if v_row.status <> 'in_use' then
    raise exception 'invalid_status';
  end if;

  v_scheduled_end := coalesce(v_row.end_at, v_row.end_time);

  if p_is_early_return then
    if v_scheduled_end is null then
      raise exception 'invalid_end_time';
    end if;
    if v_now >= v_scheduled_end then
      raise exception 'not_early_return';
    end if;
    v_return_type := 'early';
  else
    v_return_type := 'normal';
  end if;

  if p_mileage_end < coalesce(v_row.mileage_start, 0) then
    raise exception 'mileage_decreased';
  end if;

  update public.reservations
  set
    status = 'returned',
    returned_at = v_now,
    actual_end_at = v_now,
    return_type = v_return_type,
    early_return_confirmed_at = case
      when v_return_type = 'early' then v_now
      else null
    end,
    return_photos = p_return_photos,
    mileage_end = p_mileage_end,
    fuel_level_end = p_fuel_level_end,
    is_accident = coalesce(p_is_accident, false),
    accident_note = case
      when coalesce(p_is_accident, false) then nullif(trim(p_accident_note), '')
      else null
    end,
    updated_at = v_now
  where id::text = v_id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'returned',
    'returnType', v_return_type,
    'returnedAt', v_now,
    'actualEndAt', v_now,
    'scheduledEndAt', v_scheduled_end,
    'isEarlyReturn', v_return_type = 'early'
  );
end;
$$;

revoke all on function public.complete_rental_for_me(
  text, text[], integer, text, boolean, text, boolean, boolean
) from public;
grant execute on function public.complete_rental_for_me(
  text, text[], integer, text, boolean, text, boolean, boolean
) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) 기존 반납 데이터 backfill (actual_end_at / return_type)
-- ---------------------------------------------------------------------------

update public.reservations
set
  actual_end_at = coalesce(actual_end_at, returned_at),
  return_type = coalesce(return_type, 'normal')
where status in ('returned', 'completed')
  and returned_at is not null;

update public.reservations
set
  actual_end_at = coalesce(actual_end_at, returned_at, coalesce(end_at, end_time)),
  return_type = coalesce(return_type, 'auto')
where status = 'completed'
  and return_type is null
  and rental_started_at is null;

-- ---------------------------------------------------------------------------
-- 5) 시간 만료 자동종료 — return_type = auto, actual_end_at 설정
-- ---------------------------------------------------------------------------

create or replace function public.auto_complete_expired_reservations_for_me()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count integer;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  update public.reservations r
  set
    status = 'completed',
    returned_at = coalesce(r.returned_at, v_now),
    actual_end_at = coalesce(
      r.actual_end_at,
      r.returned_at,
      coalesce(r.end_at, r.end_time),
      v_now
    ),
    return_type = coalesce(r.return_type, 'auto'),
    updated_at = v_now
  where r.user_id = v_user
    and r.status in ('pending', 'confirmed', 'in_use')
    and coalesce(r.end_at, r.end_time) < v_now;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) prepare_payment_order — 겹침 검사에 actual_end_at 반영
--    (중도반납 후 같은 차량 재예약 가능)
-- ---------------------------------------------------------------------------

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
      and public.reservation_effective_end(
            r.status,
            coalesce(r.end_time, r.end_at),
            r.actual_end_at,
            r.returned_at
          ) > p_start_time
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

-- ---------------------------------------------------------------------------
-- 확인 쿼리
-- ---------------------------------------------------------------------------
-- select column_name, data_type, column_default
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'reservations'
--   and column_name in ('actual_end_at', 'return_type', 'early_return_confirmed_at')
-- order by column_name;

-- select conname, pg_get_constraintdef(oid)
-- from pg_constraint
-- where conrelid = 'public.reservations'::regclass
--   and conname like '%return%';
