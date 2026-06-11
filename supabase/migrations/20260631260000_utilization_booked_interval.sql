-- 가동률: 결제된 예약 구간(confirmed/in_use/completed, 월 경계 클리핑) — 매출 집계는 변경 없음

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
  v_user uuid := auth.uid();
  v_staff_complex_id uuid;
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_gross bigint := 0;
  v_extension bigint := 0;
  v_count bigint := 0;
  v_vehicle_count integer := 0;
  v_fee_estimate boolean := false;
  v_rows jsonb := '[]'::jsonb;
  v_utilization_rows jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_month_hours numeric;
  v_empty jsonb := jsonb_build_object(
    'gross_revenue', 0,
    'extension_revenue', 0,
    'total_revenue', 0,
    'reservation_count', 0,
    'vehicle_count', 0,
    'is_fee_estimate', false,
    'month_hours', 0,
    'payment_count', 0,
    'cancel_count', 0,
    'rental_count', 0,
    'is_settled', false,
    'is_requested', false,
    'rows', '[]'::jsonb,
    'utilization_rows', '[]'::jsonb
  );
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  if v_user is null then
    return v_empty;
  end if;

  select s.complex_id
  into v_staff_complex_id
  from public.staff_users s
  where s.user_id = v_user
    and s.approved = true
  limit 1;

  if v_staff_complex_id is null or v_staff_complex_id <> p_complex_id then
    return v_empty;
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_month_hours := extract(epoch from (v_period_end - v_period_start)) / 3600.0;

  v_vehicle_count := public.platform_fee_vehicle_count_for_month(
    p_complex_id, v_year, v_month
  );
  v_fee_estimate := public.platform_fee_is_estimate_month(v_year, v_month);

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
          (coalesce(occ.rental_hours, 0) / nullif(v_month_hours, 0)) * 100
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
        ) as revenue
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
    left join (
      select
        r.vehicle_id,
        coalesce(sum(
          greatest(
            0,
            extract(epoch from (
              least(
                coalesce(r.end_at, r.end_time),
                v_period_end
              ) - greatest(
                coalesce(r.start_at, r.start_time),
                v_period_start
              )
            )) / 3600.0
          )
        ), 0)::numeric as rental_hours
      from public.reservations r
      inner join public.vehicles rv on rv.id = r.vehicle_id
      where rv.complex_id = p_complex_id
        and r.status in ('confirmed', 'in_use', 'completed')
        and coalesce(r.start_at, r.start_time) is not null
        and coalesce(r.end_at, r.end_time) is not null
        and greatest(
          coalesce(r.start_at, r.start_time),
          v_period_start
        ) < least(
          coalesce(r.end_at, r.end_time),
          v_period_end
        )
      group by r.vehicle_id
    ) occ on occ.vehicle_id = v.id
    where v.complex_id = p_complex_id
      and v.created_at < v_period_end
      and (v.deactivated_at is null or v.deactivated_at >= v_period_start)
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
    'is_fee_estimate', v_fee_estimate,
    'month_hours', round(v_month_hours)::integer,
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
