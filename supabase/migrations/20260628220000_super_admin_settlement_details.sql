-- 최고관리자 정산 — 단지·월별 예약 상세 내역

drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

create or replace function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns table (
  reservation_id text,
  renter_name text,
  total_price integer,
  start_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'Asia/Seoul');
  v_period_end := v_period_start + interval '1 month';

  return query
  select
    r.id::text as reservation_id,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(r.total_price, 0)::integer as total_price,
    coalesce(r.start_at, r.start_time) as start_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  left join public.user_profiles up on up.user_id = r.user_id
  where v.complex_id = p_complex_id
    and r.status in ('confirmed', 'in_use', 'returning', 'returned', 'completed')
    and coalesce(r.start_at, r.start_time) >= v_period_start
    and coalesce(r.start_at, r.start_time) < v_period_end
  order by coalesce(r.start_at, r.start_time) desc nulls last;
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '최고관리자 정산 — 단지·월별 예약 상세 (get_super_admin_revenue 집계 기준과 동일)';
