-- ============================================================
-- 대여 시작(in_use) 한 번에 설정
-- Supabase SQL Editor → 전체 붙여넣기 → Run
-- ============================================================

-- 0) updated_at (RPC·트리거용)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

alter table public.reservations
  add column if not exists updated_at timestamptz not null default now();

drop trigger if exists reservations_set_updated_at on public.reservations;
create trigger reservations_set_updated_at
before update on public.reservations
for each row execute function public.set_updated_at();

-- 1) 대여·반납 컬럼
alter table public.reservations
  add column if not exists rental_started_at timestamptz;

alter table public.reservations
  add column if not exists returned_at timestamptz;

alter table public.reservations
  add column if not exists pickup_photos text[] default '{}';

alter table public.reservations
  add column if not exists return_photos text[] default '{}';

alter table public.reservations
  add column if not exists mileage_start integer;

alter table public.reservations
  add column if not exists mileage_end integer;

alter table public.reservations
  add column if not exists fuel_level_start text;

alter table public.reservations
  add column if not exists fuel_level_end text;

alter table public.reservations
  add column if not exists is_accident boolean not null default false;

alter table public.reservations
  add column if not exists accident_note text;

-- 2) status 확장: in_use 포함
alter table public.reservations
  drop constraint if exists reservations_status_check;

alter table public.reservations
  add constraint reservations_status_check
  check (status in ('pending', 'confirmed', 'in_use', 'returned', 'completed', 'cancelled'));

-- 3) 주유상태 check
alter table public.reservations
  drop constraint if exists reservations_fuel_level_start_check;

alter table public.reservations
  add constraint reservations_fuel_level_start_check
  check (
    fuel_level_start is null
    or fuel_level_start in ('full', '3quarter', 'half', 'quarter', 'empty')
  );

alter table public.reservations
  drop constraint if exists reservations_fuel_level_end_check;

alter table public.reservations
  add constraint reservations_fuel_level_end_check
  check (
    fuel_level_end is null
    or fuel_level_end in ('full', '3quarter', 'half', 'quarter', 'empty')
  );

-- 4) 사진 최대 10장
alter table public.reservations
  drop constraint if exists reservations_pickup_photos_max;

alter table public.reservations
  add constraint reservations_pickup_photos_max
  check (pickup_photos is null or cardinality(pickup_photos) <= 10);

alter table public.reservations
  drop constraint if exists reservations_return_photos_max;

alter table public.reservations
  add constraint reservations_return_photos_max
  check (return_photos is null or cardinality(return_photos) <= 10);

-- 5) 대여 시작 RPC (reservations.id = bigint → text ID)
-- 기존 오버로드·default 시그니처 모두 제거 후 재생성 (42P13 방지)
drop function if exists public.start_rental_for_me(uuid, text[], integer, text);
drop function if exists public.start_rental_for_me(text, text[], integer, text);

create or replace function public.start_rental_for_me(
  p_reservation_id text,
  p_pickup_photos text[],
  p_mileage_start integer default null,
  p_fuel_level_start text default null
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

  if p_pickup_photos is null or cardinality(p_pickup_photos) < 6 then
    raise exception 'photos_required';
  end if;

  if cardinality(p_pickup_photos) > 10 then
    raise exception 'too_many_photos';
  end if;

  if p_mileage_start is not null and p_mileage_start < 0 then
    raise exception 'invalid_mileage';
  end if;

  if p_fuel_level_start is not null
    and p_fuel_level_start not in ('full', '3quarter', 'half', 'quarter', 'empty') then
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
    'rentalStartedAt', v_now,
    'photoCount', cardinality(p_pickup_photos)
  );
end;
$$;

revoke all on function public.start_rental_for_me(text, text[], integer, text) from public;
grant execute on function public.start_rental_for_me(text, text[], integer, text) to authenticated;

-- 6) 확인 (선택)
-- select column_name from information_schema.columns
-- where table_schema = 'public' and table_name = 'reservations'
--   and column_name in ('rental_started_at', 'pickup_photos', 'mileage_start', 'fuel_level_start');
