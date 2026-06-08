-- 결제건수(연장결제+) · 취소건수 · 대여건수 — 단지관리자 매출 요약 + 공통 집계

create or replace function public.settlement_sheet_counts(
  p_complex_id uuid,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_payment_count bigint := 0;
  v_base_payment_count bigint := 0;
  v_extension_payment_count bigint := 0;
  v_cancel_count bigint := 0;
  v_rental_count bigint := 0;
  v_month_start date;
  v_has_cancelled_at_col boolean := false;
begin
  v_month_start := make_date(p_year, p_month, 1);

  v_rental_count := public.sales_count_reservations(
    p_complex_id, p_period_start, p_period_end
  );

  select count(distinct po.order_id)::bigint
  into v_base_payment_count
  from public.sales_completed_reservations_v s
  join public.reservations r on r.id::text = s.reservation_id_text
  join public.payment_orders po
    on po.order_id = r.order_id
    and po.status = 'paid'
  where s.complex_id = p_complex_id
    and s.return_completed_at >= p_period_start
    and s.return_completed_at < p_period_end;

  select count(*)::bigint
  into v_extension_payment_count
  from public.sales_extension_lines_v e
  where e.complex_id = p_complex_id
    and e.return_completed_at >= p_period_start
    and e.return_completed_at < p_period_end
    and coalesce(e.extension_amount, 0) > 0;

  v_payment_count :=
    coalesce(v_base_payment_count, 0) + coalesce(v_extension_payment_count, 0);

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_cancelled_at_col then
    select count(*)::bigint
    into v_cancel_count
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status = 'cancelled'
      and date_trunc(
        'month',
        coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
      )::date = v_month_start;
  else
    select count(*)::bigint
    into v_cancel_count
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status = 'cancelled'
      and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date =
        v_month_start;
  end if;

  return jsonb_build_object(
    'payment_count', coalesce(v_payment_count, 0),
    'base_payment_count', coalesce(v_base_payment_count, 0),
    'extension_payment_count', coalesce(v_extension_payment_count, 0),
    'cancel_count', coalesce(v_cancel_count, 0),
    'rental_count', coalesce(v_rental_count, 0)
  );
end;
$$;

drop function if exists public.get_admin_sales_summary(uuid, integer, integer);

create or replace function public.get_admin_sales_summary(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
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
  v_gross bigint := 0;
  v_extension bigint := 0;
  v_count bigint := 0;
  v_vehicle_count integer := 0;
  v_rows jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  select count(*)::integer
  into v_vehicle_count
  from public.vehicles v
  where v.complex_id = p_complex_id;

  v_count := public.sales_count_reservations(p_complex_id, v_period_start, v_period_end);
  v_gross := public.sales_sum_gross(p_complex_id, v_period_start, v_period_end);
  v_extension := public.sales_sum_extension(p_complex_id, v_period_start, v_period_end);

  v_counts := public.settlement_sheet_counts(
    p_complex_id, v_period_start, v_period_end, v_year, v_month
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vehicle_name', row_data.vehicle_name,
        'amount', row_data.amount,
        'count', row_data.cnt
      )
      order by row_data.amount desc nulls last
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      s.vehicle_name,
      coalesce(sum(s.gross_amount), 0)::bigint as amount,
      count(*)::bigint as cnt
    from public.sales_completed_reservations_v s
    where s.complex_id = p_complex_id
      and s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.vehicle_name
  ) row_data;

  select
    cs.settled_at is not null,
    cs.requested_at is not null and cs.settled_at is null
  into v_is_settled, v_is_requested
  from public.complex_settlements cs
  where cs.complex_id = p_complex_id
    and cs.period_year = v_year
    and cs.period_month = v_month;

  return jsonb_build_object(
    'gross_revenue', coalesce(v_gross, 0),
    'extension_revenue', coalesce(v_extension, 0),
    'total_revenue', coalesce(v_gross, 0) + coalesce(v_extension, 0),
    'reservation_count', coalesce(v_count, 0),
    'vehicle_count', coalesce(v_vehicle_count, 0),
    'payment_count', coalesce((v_counts->>'payment_count')::bigint, 0),
    'cancel_count', coalesce((v_counts->>'cancel_count')::bigint, 0),
    'rental_count', coalesce((v_counts->>'rental_count')::bigint, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_admin_sales_summary(uuid, integer, integer) from public;
grant execute on function public.get_admin_sales_summary(uuid, integer, integer) to authenticated;
