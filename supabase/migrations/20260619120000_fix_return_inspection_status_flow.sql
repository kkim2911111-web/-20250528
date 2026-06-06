-- 고객 반납 → returned (검수 대기), 관리자 검수 완료 → completed
-- (이미 20260618120000 을 completed 로 적용한 DB용 수정)

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
  end if;

  if p_mileage_end < coalesce(v_row.mileage_start, 0) then
    raise exception 'mileage_decreased';
  end if;

  update public.reservations
  set
    status = 'returned',
    returned_at = v_now,
    actual_end_at = v_now,
    return_type = 'manual',
    early_return_confirmed_at = case
      when p_is_early_return then v_now
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
    'returnType', 'manual',
    'returnedAt', v_now,
    'actualEndAt', v_now,
    'scheduledEndAt', v_scheduled_end,
    'isEarlyReturn', p_is_early_return
  );
end;
$$;
