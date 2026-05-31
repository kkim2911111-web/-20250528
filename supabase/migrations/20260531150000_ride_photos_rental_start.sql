-- ============================================================
-- ride_photos 테이블 + 운행 시작(사진 6장 이상, 주행/주유 선택)
-- Supabase SQL Editor → Run
-- ============================================================

-- 1) ride_photos
create table if not exists public.ride_photos (
  id bigint generated always as identity primary key,
  reservation_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  phase text not null default 'pickup'
    check (phase in ('pickup', 'return')),
  photo_url text not null,
  photo_order integer not null default 0,
  photo_type text,
  is_required boolean,
  mileage_start integer,
  fuel_level_start text,
  created_at timestamptz not null default now()
);

alter table public.ride_photos
  add column if not exists photo_order integer not null default 0;

alter table public.ride_photos
  add column if not exists photo_type text;

alter table public.ride_photos
  add column if not exists is_required boolean;

alter table public.ride_photos
  add column if not exists mileage_start integer;

alter table public.ride_photos
  add column if not exists fuel_level_start text;

alter table public.ride_photos
  drop constraint if exists ride_photos_fuel_level_start_check;

alter table public.ride_photos
  add constraint ride_photos_fuel_level_start_check
  check (
    fuel_level_start is null
    or fuel_level_start in ('full', '3quarter', 'half', 'quarter', 'empty')
  );

create index if not exists ride_photos_reservation_phase_idx
  on public.ride_photos (reservation_id, phase, photo_order);

alter table public.ride_photos enable row level security;

drop policy if exists "ride_photos_select_own" on public.ride_photos;
create policy "ride_photos_select_own"
on public.ride_photos for select to authenticated
using (user_id = auth.uid());

drop policy if exists "ride_photos_insert_own" on public.ride_photos;
create policy "ride_photos_insert_own"
on public.ride_photos for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "ride_photos_delete_own" on public.ride_photos;
create policy "ride_photos_delete_own"
on public.ride_photos for delete to authenticated
using (user_id = auth.uid());

-- 2) reservations — 주행/주유 nullable (이미 nullable이면 유지)
alter table public.reservations
  alter column mileage_start drop not null;

alter table public.reservations
  alter column fuel_level_start drop not null;

-- 3) 대여 시작 RPC — 사진 최소 6장, 주행/주유 선택
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
  v_i integer;
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

  delete from public.ride_photos
  where reservation_id = v_id
    and user_id = v_user
    and phase = 'pickup';

  for v_i in 1..cardinality(p_pickup_photos) loop
    insert into public.ride_photos (
      reservation_id,
      user_id,
      phase,
      photo_url,
      photo_order,
      photo_type,
      is_required,
      mileage_start,
      fuel_level_start
    )
    values (
      v_id,
      v_user,
      'pickup',
      p_pickup_photos[v_i],
      v_i - 1,
      null,
      null,
      case when v_i = 1 then p_mileage_start else null end,
      case when v_i = 1 then p_fuel_level_start else null end
    );
  end loop;

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
grant execute on function public.start_rental_for_me(text, text[], integer, text) to service_role;
