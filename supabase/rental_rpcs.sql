-- ============================================================
-- 대여 시작 / 반납 RPC
-- Supabase SQL Editor → Run (alter_reservations_rental_columns.sql 선행)
-- ============================================================

create or replace function public.start_rental_for_me(
  p_reservation_id uuid,
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
  v_row public.reservations%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated';
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
  from public.reservations
  where id = p_reservation_id
    and user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status <> 'confirmed' then
    raise exception 'invalid_status';
  end if;

  if now() < coalesce(v_row.start_at, v_row.start_time) - interval '30 minutes' then
    raise exception 'too_early';
  end if;

  if now() > coalesce(v_row.end_at, v_row.end_time) then
    raise exception 'expired';
  end if;

  update public.reservations
  set
    status = 'in_use',
    rental_started_at = now(),
    pickup_photos = p_pickup_photos,
    mileage_start = p_mileage_start,
    fuel_level_start = p_fuel_level_start,
    updated_at = now()
  where id = p_reservation_id;

  return jsonb_build_object(
    'reservationId', p_reservation_id::text,
    'status', 'in_use',
    'rentalStartedAt', now()
  );
end;
$$;

create or replace function public.complete_rental_for_me(
  p_reservation_id uuid,
  p_return_photos text[],
  p_mileage_end integer,
  p_fuel_level_end text,
  p_is_accident boolean default false,
  p_accident_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row public.reservations%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated';
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

  select *
  into v_row
  from public.reservations
  where id = p_reservation_id
    and user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status <> 'in_use' then
    raise exception 'invalid_status';
  end if;

  if p_mileage_end < coalesce(v_row.mileage_start, 0) then
    raise exception 'mileage_decreased';
  end if;

  update public.reservations
  set
    status = 'returned',
    returned_at = now(),
    return_photos = p_return_photos,
    mileage_end = p_mileage_end,
    fuel_level_end = p_fuel_level_end,
    is_accident = coalesce(p_is_accident, false),
    accident_note = case
      when coalesce(p_is_accident, false) then nullif(trim(p_accident_note), '')
      else null
    end,
    updated_at = now()
  where id = p_reservation_id;

  return jsonb_build_object(
    'reservationId', p_reservation_id::text,
    'status', 'returned',
    'returnedAt', now()
  );
end;
$$;

revoke all on function public.start_rental_for_me(uuid, text[], integer, text) from public;
grant execute on function public.start_rental_for_me(uuid, text[], integer, text) to authenticated;

revoke all on function public.complete_rental_for_me(uuid, text[], integer, text, boolean, text) from public;
grant execute on function public.complete_rental_for_me(uuid, text[], integer, text, boolean, text) to authenticated;
