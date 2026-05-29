-- ============================================================
-- 스마트키 문열림/닫힘 (door_unlocked)
-- fix_reservations_schema.sql 선행 권장
-- Supabase SQL Editor → Run
-- ============================================================

create or replace function public.set_door_lock_for_me(
  p_reservation_id uuid,
  p_unlocked boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row public.reservations%rowtype;
  v_photo_count integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id = p_reservation_id
    and r.user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status not in ('confirmed', 'in_use') then
    raise exception 'invalid_status';
  end if;

  if coalesce(v_row.end_at, v_row.end_time) < now() then
    raise exception 'expired';
  end if;

  v_photo_count := coalesce(cardinality(v_row.pickup_photos), 0);

  if p_unlocked
    and v_row.status <> 'in_use'
    and v_photo_count < 10 then
    raise exception 'photos_required';
  end if;

  update public.reservations
  set door_unlocked = p_unlocked
  where id = p_reservation_id;

  return jsonb_build_object(
    'reservationId', p_reservation_id::text,
    'doorUnlocked', p_unlocked
  );
end;
$$;

revoke all on function public.set_door_lock_for_me(uuid, boolean) from public;
grant execute on function public.set_door_lock_for_me(uuid, boolean) to authenticated;
