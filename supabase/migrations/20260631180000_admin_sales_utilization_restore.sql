-- 관리자 매출 요약 — 가동률(utilization_rows) 복원 + 월 노출 차량 기준 + 월 실일수 시간
-- 집계 함수(sales_sum_*, settlement_sheet_counts)는 변경하지 않음

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
          (coalesce(vs.rental_hours, 0) / nullif(v_month_hours, 0)) * 100
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

-- 차량별 매출 — 선택 월 완료 건 목록 (읽기 전용, 집계 로직 변경 없음)
drop function if exists public.get_admin_vehicle_sales_rentals(uuid, integer, integer, text);

create or replace function public.get_admin_vehicle_sales_rentals(
  p_complex_id uuid,
  p_year integer,
  p_month integer,
  p_vehicle_name text
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
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_items jsonb := '[]'::jsonb;
begin
  if p_complex_id is null or p_vehicle_name is null or trim(p_vehicle_name) = '' then
    return '[]'::jsonb;
  end if;

  if v_user is null then
    return '[]'::jsonb;
  end if;

  select s.complex_id
  into v_staff_complex_id
  from public.staff_users s
  where s.user_id = v_user
    and s.approved = true
  limit 1;

  if v_staff_complex_id is null or v_staff_complex_id <> p_complex_id then
    return '[]'::jsonb;
  end if;

  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(p_year, p_month) as b;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', row_data.reservation_id,
        'reservation_number', row_data.reservation_number,
        'renter_name', row_data.renter_name,
        'rental_type', row_data.rental_type,
        'sort_at', row_data.sort_at,
        'gross_amount', row_data.gross_amount
      )
      order by row_data.sort_at asc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      s.reservation_id_text as reservation_id,
      s.reservation_number,
      coalesce(
        nullif(trim(up.full_name), ''),
        nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
        '임차인'
      ) as renter_name,
      coalesce(nullif(trim(r.rental_type), ''), 'hourly') as rental_type,
      s.return_completed_at as sort_at,
      s.gross_amount
    from public.sales_completed_reservations_v s
    inner join public.reservations r on r.id = s.id
    left join public.user_profiles up on up.user_id = s.user_id
    where s.complex_id = p_complex_id
      and s.vehicle_name = trim(p_vehicle_name)
      and s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
  ) row_data;

  return coalesce(v_items, '[]'::jsonb);
end;
$$;

revoke all on function public.get_admin_vehicle_sales_rentals(uuid, integer, integer, text) from public;
grant execute on function public.get_admin_vehicle_sales_rentals(uuid, integer, integer, text) to authenticated;
