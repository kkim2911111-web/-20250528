-- 최고관리자 — 임차인 이용·노쇼 건수 (전 기간, count 전용)
drop function if exists public.get_super_admin_renter_usage_stats(text);

create or replace function public.get_super_admin_renter_usage_stats(
  p_reservation_id text
)
returns table (
  usage_count integer,
  no_show_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_reservation_id text := nullif(trim(p_reservation_id), '');
begin
  perform public.assert_is_super_admin();

  if v_reservation_id is null then
    raise exception 'reservation_id_required';
  end if;

  select r.user_id
  into v_user_id
  from public.reservations r
  where r.id::text = v_reservation_id
  limit 1;

  if v_user_id is null then
    return query select 0::integer, 0::integer;
    return;
  end if;

  return query
  select
    count(*) filter (
      where lower(trim(coalesce(r.status, ''))) = 'completed'
    )::integer as usage_count,
    count(*) filter (
      where coalesce(r.is_no_show, false) = true
    )::integer as no_show_count
  from public.reservations r
  where r.user_id = v_user_id;
end;
$$;

revoke all on function public.get_super_admin_renter_usage_stats(text) from public;
grant execute on function public.get_super_admin_renter_usage_stats(text) to authenticated;

comment on function public.get_super_admin_renter_usage_stats(text) is
  '최고관리자 — 예약 임차인 전 기간 completed·노쇼 건수';
