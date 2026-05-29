-- ============================================================
-- 이용 시간(end_at) 경과 예약 자동 이용종료
-- Supabase SQL Editor → Run
-- ============================================================

create or replace function public.auto_complete_expired_reservations_for_me()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  update public.reservations r
  set
    status = 'completed',
    returned_at = coalesce(r.returned_at, now())
  where r.user_id = v_user
    and r.status in ('pending', 'confirmed', 'in_use')
    and coalesce(r.end_at, r.end_time) < now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.auto_complete_expired_reservations_for_me() from public;
grant execute on function public.auto_complete_expired_reservations_for_me() to authenticated;
