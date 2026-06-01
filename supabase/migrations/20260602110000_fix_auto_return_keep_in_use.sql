-- in_use(대여 중) 예약은 시간 경과해도 자동 반납하지 않음
-- 미대여 확정(confirmed/pending + rental_started_at 없음)만 자동 종료

alter table public.reservations
  add column if not exists return_parking_note text;

alter table public.reservations
  add column if not exists handover_note text;

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
    status = 'returned',
    returned_at = coalesce(r.returned_at, v_now),
    actual_end_at = coalesce(
      r.actual_end_at,
      coalesce(r.end_at, r.end_time),
      v_now
    ),
    return_type = coalesce(r.return_type, 'auto'),
    updated_at = v_now
  where r.user_id = v_user
    and r.status in ('confirmed', 'pending')
    and r.rental_started_at is null
    and coalesce(r.end_at, r.end_time) is not null
    and coalesce(r.end_at, r.end_time) < v_now;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.auto_complete_expired_reservations_for_me() from public;
grant execute on function public.auto_complete_expired_reservations_for_me() to authenticated;
grant execute on function public.auto_complete_expired_reservations_for_me() to service_role;

-- ── 이미 auto-return 된 in_use 예약 복구 (테스트용, 1회 실행) ──
-- update public.reservations
-- set status = 'in_use', returned_at = null, actual_end_at = null, return_type = null
-- where id = '<reservation_id>' and return_type = 'auto' and rental_started_at is not null;
