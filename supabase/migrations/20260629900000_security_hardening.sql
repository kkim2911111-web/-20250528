-- 보안 보완: staff 매출 RPC IDOR, notifications RLS, reservations staff RLS, super_admin vehicles

-- ── 1) get_admin_sales_summary — 호출자 staff complex_id 검증 ───
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
  v_rows jsonb := '[]'::jsonb;
  v_utilization_rows jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_month_hours constant numeric := 744;
  v_empty jsonb := jsonb_build_object(
    'gross_revenue', 0,
    'extension_revenue', 0,
    'total_revenue', 0,
    'reservation_count', 0,
    'vehicle_count', 0,
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

-- ── 2) get_admin_branch_sales_stats — 호출자 staff complex_id 검증 ─
drop function if exists public.get_admin_branch_sales_stats(uuid);

create or replace function public.get_admin_branch_sales_stats(p_complex_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_staff_complex_id uuid;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_month_end timestamptz;
  v_empty jsonb := jsonb_build_object(
    'today_sales', 0,
    'month_sales', 0
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

  select b.period_start, b.period_end
  into v_day_start, v_day_end
  from public.sales_today_bounds() as b;

  select b.period_start, b.period_end
  into v_month_start, v_month_end
  from public.sales_current_month_bounds() as b;

  return jsonb_build_object(
    'today_sales',
      public.sales_total_revenue(p_complex_id, v_day_start, v_day_end),
    'month_sales',
      public.sales_total_revenue(p_complex_id, v_month_start, v_month_end)
  );
end;
$$;

revoke all on function public.get_admin_sales_summary(uuid, integer, integer) from public;
grant execute on function public.get_admin_sales_summary(uuid, integer, integer) to authenticated;

revoke all on function public.get_admin_branch_sales_stats(uuid) from public;
grant execute on function public.get_admin_branch_sales_stats(uuid) to authenticated;

comment on function public.get_admin_sales_summary(uuid, integer, integer) is
  '단지 관리자 매출 — staff 소속 단지 검증, 불일치 시 빈 결과';

comment on function public.get_admin_branch_sales_stats(uuid) is
  '단지 관리자 홈 매출 카드 — staff 소속 단지 검증, 불일치 시 빈 결과';

-- ── 3) notifications — staff SELECT category 격리 ───────────────
drop policy if exists "notifications_select_staff_complex" on public.notifications;

create policy "notifications_select_staff_complex"
on public.notifications
for select
to authenticated
using (
  notifications.complex_id is not null
  and (
    notifications.category in ('admin', 'super_admin')
    or notifications.user_id = auth.uid()
  )
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = notifications.complex_id
  )
);

-- ── 4) reservations — staff RLS (migrations 이관) ───────────────
alter table public.reservations enable row level security;

drop policy if exists "reservations_staff_select_complex" on public.reservations;
create policy "reservations_staff_select_complex"
on public.reservations
for select
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    join public.vehicles v on v.complex_id = s.complex_id
    where s.user_id = auth.uid()
      and s.approved = true
      and v.id = reservations.vehicle_id
  )
);

drop policy if exists "reservations_staff_update_complex" on public.reservations;
create policy "reservations_staff_update_complex"
on public.reservations
for update
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    join public.vehicles v on v.complex_id = s.complex_id
    where s.user_id = auth.uid()
      and s.approved = true
      and v.id = reservations.vehicle_id
  )
)
with check (
  exists (
    select 1
    from public.staff_users s
    join public.vehicles v on v.complex_id = s.complex_id
    where s.user_id = auth.uid()
      and s.approved = true
      and v.id = reservations.vehicle_id
  )
);

-- ── 5) get_super_admin_vehicles — 점검/주행 컬럼 추가 ───────────
drop function if exists public.get_super_admin_vehicles();

create or replace function public.get_super_admin_vehicles()
returns table (
  vehicle_id text,
  complex_id uuid,
  complex_name text,
  model_name text,
  car_number text,
  car_type text,
  vehicle_type text,
  fuel_type text,
  price_per_hour integer,
  daily_price integer,
  monthly_price integer,
  rental_types text[],
  is_available boolean,
  in_use boolean,
  current_reservation_status text,
  current_renter_name text,
  total_mileage integer,
  is_under_maintenance boolean,
  maintenance_memo text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();

  return query
  select
    v.id::text as vehicle_id,
    v.complex_id,
    c.name as complex_name,
    coalesce(v.model_name, '차량') as model_name,
    v.car_number,
    coalesce(v.car_type, 'SUV') as car_type,
    coalesce(v.vehicle_type, 'sharing') as vehicle_type,
    v.fuel_type,
    coalesce(v.price_per_hour, 0) as price_per_hour,
    v.daily_price,
    v.monthly_price,
    coalesce(v.rental_types, array['hourly']::text[]) as rental_types,
    coalesce(v.is_available, false) as is_available,
    (cur.id is not null) as in_use,
    cur.status as current_reservation_status,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      null
    ) as current_renter_name,
    coalesce(v.total_mileage, 0) as total_mileage,
    coalesce(v.is_under_maintenance, false) as is_under_maintenance,
    v.maintenance_memo,
    v.created_at
  from public.vehicles v
  join public.complexes c on c.id = v.complex_id
  left join lateral (
    select r.id, r.status, r.user_id
    from public.reservations r
    where r.vehicle_id = v.id
      and r.status = 'in_use'
    order by coalesce(r.start_at, r.start_time) desc
    limit 1
  ) cur on true
  left join public.user_profiles up on up.user_id = cur.user_id
  order by c.name asc nulls last, v.model_name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_vehicles() from public;
grant execute on function public.get_super_admin_vehicles() to authenticated;

comment on function public.get_super_admin_vehicles() is
  '최고관리자 차량 목록 — total_mileage, is_under_maintenance, maintenance_memo 포함';
