-- ============================================================
-- reservations 예약 시작/종료 시각 컬럼 보장 (timestamptz)
-- 운행시작 버튼: start_rental_for_me RPC — 시작 30분 전부터 허용
-- ============================================================

-- 1) start_at / end_at (기본 컬럼)
alter table public.reservations
  add column if not exists start_at timestamptz;

alter table public.reservations
  add column if not exists end_at timestamptz;

-- 2) start_time / end_time (앱·RPC 호환 별칭)
alter table public.reservations
  add column if not exists start_time timestamptz;

alter table public.reservations
  add column if not exists end_time timestamptz;

-- 3) 타입이 timestamptz가 아니면 변환 (레거시 timestamp without time zone 대비)
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'start_time'
      and data_type = 'timestamp without time zone'
  ) then
    alter table public.reservations
      alter column start_time type timestamptz using start_time at time zone 'Asia/Seoul';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'start_at'
      and data_type = 'timestamp without time zone'
  ) then
    alter table public.reservations
      alter column start_at type timestamptz using start_at at time zone 'Asia/Seoul';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'end_time'
      and data_type = 'timestamp without time zone'
  ) then
    alter table public.reservations
      alter column end_time type timestamptz using end_time at time zone 'Asia/Seoul';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'end_at'
      and data_type = 'timestamp without time zone'
  ) then
    alter table public.reservations
      alter column end_at type timestamptz using end_at at time zone 'Asia/Seoul';
  end if;
end;
$$;

-- 4) start_at ↔ start_time, end_at ↔ end_time 상호 보정
update public.reservations
set
  start_at = coalesce(start_at, start_time),
  start_time = coalesce(start_time, start_at),
  end_at = coalesce(end_at, end_time),
  end_time = coalesce(end_time, end_at)
where start_at is not null
   or start_time is not null
   or end_at is not null
   or end_time is not null;

comment on column public.reservations.start_at is
  '예약 시작 시각 (timestamptz). start_time과 동일 값 유지 권장.';

comment on column public.reservations.start_time is
  '예약 시작 시각 (timestamptz). start_at과 동일 값 유지 권장. 운행시작 30분 전 활성화 기준.';

comment on column public.reservations.end_at is
  '예약 종료 시각 (timestamptz). end_time과 동일 값 유지 권장.';

comment on column public.reservations.end_time is
  '예약 종료 시각 (timestamptz). end_at과 동일 값 유지 권장.';

-- 5) 운행시작 RPC — 예약 시작 30분 전부터 허용 (idempotent)
create or replace function public.start_rental_for_me(
  p_reservation_id text,
  p_pickup_photos text[],
  p_mileage_start integer,
  p_fuel_level_start text
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
  v_now timestamptz := now();
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  if p_pickup_photos is null or cardinality(p_pickup_photos) < 1 then
    raise exception 'photos_required';
  end if;

  if cardinality(p_pickup_photos) > 10 then
    raise exception 'too_many_photos';
  end if;

  if p_mileage_start is null or p_mileage_start < 0 then
    raise exception 'invalid_mileage';
  end if;

  if p_fuel_level_start is null
    or p_fuel_level_start not in ('full', '3quarter', 'half', 'quarter', 'empty') then
    raise exception 'invalid_fuel_level';
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
  v_end := coalesce(v_row.end_at, v_row.end_time);

  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_now < v_start - interval '30 minutes' then
    raise exception 'too_early';
  end if;

  if v_end is not null and v_now > v_end then
    raise exception 'expired';
  end if;

  update public.reservations
  set
    status = 'in_use',
    rental_started_at = v_now,
    pickup_photos = p_pickup_photos,
    mileage_start = p_mileage_start,
    fuel_level_start = p_fuel_level_start,
    updated_at = v_now
  where id::text = v_id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'in_use',
    'rentalStartedAt', v_now
  );
end;
$$;

revoke all on function public.start_rental_for_me(text, text[], integer, text) from public;
grant execute on function public.start_rental_for_me(text, text[], integer, text) to authenticated;
grant execute on function public.start_rental_for_me(text, text[], integer, text) to service_role;
