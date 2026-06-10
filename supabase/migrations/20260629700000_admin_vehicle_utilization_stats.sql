-- 관리자 매출 요약 — 차량별 가동률(실대여시간/744h) 집계 추가

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
  v_utilization_rows jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_month_hours constant numeric := 744;
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vehicle_name', row_data.vehicle_name,
        'car_number', row_data.car_number,
        'rental_count', row_data.rental_count,
        'revenue', row_data.revenue,
        'utilization_percent', row_data.utilization_percent
      )
      order by row_data.revenue desc nulls last, row_data.vehicle_name
    ),
    '[]'::jsonb
  )
  into v_utilization_rows
  from (
    select
      coalesce(v.model_name, '차량') as vehicle_name,
      v.car_number,
      coalesce(vs.rental_count, 0)::bigint as rental_count,
      coalesce(vs.revenue, 0)::bigint as revenue,
      round(
        least(
          100,
          (coalesce(vs.rental_hours, 0) / v_month_hours) * 100
        ),
        1
      ) as utilization_percent
    from public.vehicles v
    left join (
      select
        pr.vehicle_id,
        count(*)::bigint as rental_count,
        (
          coalesce(sum(pr.gross_amount), 0)::bigint
          + coalesce(sum(coalesce(er.extension_amount, 0)), 0)::bigint
        ) as revenue,
        coalesce(sum(
          case
            when pr.rental_started_at is not null then
              greatest(
                0,
                extract(epoch from (
                  public.sales_return_completed_at(pr.returned_at, pr.actual_end_at)
                  - pr.rental_started_at
                )) / 3600.0
              )
            else 0
          end
        ), 0)::numeric as rental_hours
      from public.sales_completed_reservations_v pr
      left join (
        select
          e.reservation_id_text,
          coalesce(sum(e.extension_amount), 0)::bigint as extension_amount
        from public.sales_extension_lines_v e
        where e.complex_id = p_complex_id
          and e.return_completed_at >= v_period_start
          and e.return_completed_at < v_period_end
        group by e.reservation_id_text
      ) er on er.reservation_id_text = pr.reservation_id_text
      where pr.complex_id = p_complex_id
        and pr.return_completed_at >= v_period_start
        and pr.return_completed_at < v_period_end
      group by pr.vehicle_id
    ) vs on vs.vehicle_id = v.id
    where v.complex_id = p_complex_id
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
    'rows', coalesce(v_rows, '[]'::jsonb),
    'utilization_rows', coalesce(v_utilization_rows, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_admin_sales_summary(uuid, integer, integer) from public;
grant execute on function public.get_admin_sales_summary(uuid, integer, integer) to authenticated;
