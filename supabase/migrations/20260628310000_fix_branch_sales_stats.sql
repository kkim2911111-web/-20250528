-- 단지 관리자 홈 매출 카드 — get_admin_sales_summary(total_revenue)와 동일 집계 기준

create or replace function public.get_admin_branch_sales_stats(p_complex_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_month_end timestamptz;
  v_today_gross bigint := 0;
  v_today_extension bigint := 0;
  v_month_gross bigint := 0;
  v_month_extension bigint := 0;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_day_start := date_trunc('day', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';
  v_day_end := v_day_start + interval '1 day';
  v_month_start := date_trunc('month', now() at time zone 'Asia/Seoul')
    at time zone 'Asia/Seoul';
  v_month_end := v_month_start + interval '1 month';

  select coalesce(sum(r.total_price), 0)::bigint
  into v_today_gross
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_day_start
    and coalesce(r.returned_at, r.actual_end_at) < v_day_end;

  select coalesce(sum(re.added_price), 0)::bigint
  into v_today_extension
  from public.reservation_extensions re
  join public.reservations r on r.id::text = re.reservation_id::text
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_day_start
    and coalesce(r.returned_at, r.actual_end_at) < v_day_end;

  select coalesce(sum(r.total_price), 0)::bigint
  into v_month_gross
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_month_start
    and coalesce(r.returned_at, r.actual_end_at) < v_month_end;

  select coalesce(sum(re.added_price), 0)::bigint
  into v_month_extension
  from public.reservation_extensions re
  join public.reservations r on r.id::text = re.reservation_id::text
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'completed'
    and coalesce(r.returned_at, r.actual_end_at) >= v_month_start
    and coalesce(r.returned_at, r.actual_end_at) < v_month_end;

  return jsonb_build_object(
    'today_sales', coalesce(v_today_gross, 0) + coalesce(v_today_extension, 0),
    'month_sales', coalesce(v_month_gross, 0) + coalesce(v_month_extension, 0)
  );
end;
$$;

comment on function public.get_admin_branch_sales_stats(uuid) is
  '단지 관리자 홈 매출 카드 — completed·반납 완료일 기준, gross+연장(get_admin_sales_summary total_revenue와 동일)';
