-- 단지 관리자 매출 = 최고관리자 정산 기준 통일 + 실제 대여 시각 RPC 필드

drop function if exists public.get_admin_sales_summary(uuid, integer, integer);
drop function if exists public.get_admin_completed_reservations();
drop function if exists public.get_admin_completed_reservations(integer, integer);
drop function if exists public.get_admin_reservations_with_conflict();
drop function if exists public.get_admin_reservations_with_conflict(integer, integer);
drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);
drop function if exists public.get_super_admin_resident_detail(uuid);

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
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'Asia/Seoul');
  v_period_end := v_period_start + interval '1 month';

  select count(*)::integer
  into v_vehicle_count
  from public.vehicles v
  where v.complex_id = p_complex_id;

  select
    count(*)::bigint,
    coalesce(sum(r.total_price), 0)::bigint
  into v_count, v_gross
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status in ('confirmed', 'in_use', 'returning', 'returned', 'completed')
    and coalesce(r.start_at, r.start_time) >= v_period_start
    and coalesce(r.start_at, r.start_time) < v_period_end;

  select coalesce(sum(re.added_price), 0)::bigint
  into v_extension
  from public.reservation_extensions re
  join public.reservations r on r.id::text = re.reservation_id::text
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and re.created_at >= v_period_start
    and re.created_at < v_period_end;

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
      coalesce(v.model_name, '차량') as vehicle_name,
      coalesce(sum(r.total_price), 0)::bigint as amount,
      count(*)::bigint as cnt
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status in ('confirmed', 'in_use', 'returning', 'returned', 'completed')
      and coalesce(r.start_at, r.start_time) >= v_period_start
      and coalesce(r.start_at, r.start_time) < v_period_end
    group by v.model_name
  ) row_data;

  return jsonb_build_object(
    'gross_revenue', coalesce(v_gross, 0),
    'extension_revenue', coalesce(v_extension, 0),
    'total_revenue', coalesce(v_gross, 0) + coalesce(v_extension, 0),
    'reservation_count', coalesce(v_count, 0),
    'vehicle_count', coalesce(v_vehicle_count, 0),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

-- 완료 예약 RPC — 실제 대여/반납 시각
drop function if exists public.get_admin_completed_reservations(integer, integer);

create or replace function public.get_admin_completed_reservations(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz,
  total_price integer,
  return_type text,
  is_no_show boolean,
  second_driver_name text,
  second_driver_license text,
  sort_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
    limit 1
  )
  select
    r.id::text as reservation_id,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone,
    r.status,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    r.rental_started_at,
    r.returned_at,
    r.actual_end_at,
    coalesce(r.total_price, 0) as total_price,
    r.return_type,
    coalesce(r.is_no_show, false) as is_no_show,
    nullif(trim(r.second_driver_name), '') as second_driver_name,
    nullif(trim(r.second_driver_license), '') as second_driver_license,
    coalesce(
      r.returned_at,
      r.actual_end_at,
      r.updated_at,
      r.end_at,
      r.end_time,
      r.start_at,
      r.start_time
    ) as sort_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join staff_complex sc on sc.complex_id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  where r.status = 'completed'
     or (r.status = 'cancelled' and coalesce(r.is_no_show, false) = true)
  order by sort_at desc nulls last
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

-- 활성 예약 RPC — 반납 시각 필드 추가
drop function if exists public.get_admin_reservations_with_conflict(integer, integer);

create or replace function public.get_admin_reservations_with_conflict(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz,
  total_price integer,
  updated_at timestamptz,
  next_start_at timestamptz,
  next_renter_name text,
  next_renter_phone text,
  is_conflict_risk boolean,
  second_driver_name text,
  second_driver_license text
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
    limit 1
  ),
  scoped as (
    select
      r.id,
      r.vehicle_id,
      r.user_id,
      r.status,
      coalesce(r.start_at, r.start_time) as start_at,
      coalesce(r.end_at, r.end_time) as end_at,
      r.rental_started_at,
      r.returned_at,
      r.actual_end_at,
      coalesce(r.total_price, 0) as total_price,
      r.updated_at,
      nullif(trim(r.second_driver_name), '') as second_driver_name,
      nullif(trim(r.second_driver_license), '') as second_driver_license,
      coalesce(v.model_name, '차량') as vehicle_name,
      v.car_number,
      coalesce(
        nullif(trim(up.full_name), ''),
        nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as renter_name,
      coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    join staff_complex sc on sc.complex_id = v.complex_id
    left join public.user_profiles up on up.user_id = r.user_id
    where r.status in ('pending', 'confirmed', 'in_use', 'returning')
      and r.status not in ('returned', 'completed', 'cancelled')
  )
  select
    s.id::text as reservation_id,
    s.vehicle_name,
    s.car_number,
    s.renter_name,
    s.renter_phone,
    s.status,
    s.start_at,
    s.end_at,
    s.rental_started_at,
    s.returned_at,
    s.actual_end_at,
    s.total_price,
    s.updated_at,
    next_res.next_start_at,
    next_res.next_renter_name,
    next_res.next_renter_phone,
    (
      s.status = 'in_use'
      and next_res.next_start_at is not null
    ) as is_conflict_risk,
    s.second_driver_name,
    s.second_driver_license
  from scoped s
  left join lateral (
    select
      coalesce(n.start_at, n.start_time) as next_start_at,
      coalesce(
        nullif(trim(nup.full_name), ''),
        nullif(split_part(nullif(trim(nup.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as next_renter_name,
      coalesce(nullif(trim(nup.phone), ''), '미등록') as next_renter_phone
    from public.reservations n
    left join public.user_profiles nup on nup.user_id = n.user_id
    where n.vehicle_id = s.vehicle_id
      and n.id <> s.id
      and n.status in ('pending', 'confirmed', 'in_use')
      and n.status not in ('returned', 'completed', 'cancelled')
      and coalesce(n.start_at, n.start_time) <= s.end_at + interval '30 minutes'
      and coalesce(n.start_at, n.start_time) >= s.end_at - interval '5 minutes'
    order by coalesce(n.start_at, n.start_time)
    limit 1
  ) next_res on true
  order by s.start_at desc nulls last
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.get_admin_sales_summary(uuid, integer, integer) from public;
grant execute on function public.get_admin_sales_summary(uuid, integer, integer) to authenticated;

revoke all on function public.get_admin_completed_reservations(integer, integer) from public;
grant execute on function public.get_admin_completed_reservations(integer, integer) to authenticated;

revoke all on function public.get_admin_reservations_with_conflict(integer, integer) from public;
grant execute on function public.get_admin_reservations_with_conflict(integer, integer) to authenticated;

-- 정산 상세 / 입주민 상세 — 실제 대여 시각 필드
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
  start_at timestamptz,
  end_at timestamptz,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz
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
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    r.rental_started_at,
    r.returned_at,
    r.actual_end_at
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

create or replace function public.get_super_admin_resident_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  perform public.assert_is_super_admin();

  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  select jsonb_build_object(
    'user_id', res.user_id::text,
    'complex_id', res.complex_id::text,
    'complex_name', c.name,
    'building', res.building,
    'unit', res.unit,
    'approved', res.approved,
    'full_name', up.full_name,
    'phone', up.phone,
    'email', coalesce(up.email, au.email::text),
    'created_at', res.created_at,
    'is_blacklisted', coalesce(up.is_blacklisted, false),
    'license_verified', coalesce(up.license_verified, false),
    'license_status', coalesce(up.license_status, 'none'),
    'license_number', up.license_number,
    'license_expiry', up.license_expiry,
    'points', coalesce(up.points, 0),
    'coupon_count', (
      select count(*)::integer
      from public.user_coupons uc
      where uc.user_id = res.user_id
        and coalesce(uc.is_used, false) = false
    ),
    'rental_count', (
      select count(*)::integer
      from public.reservations r
      where r.user_id = res.user_id
    ),
    'rentals', coalesce((
      select jsonb_agg(row_data order by sort_at desc nulls last)
      from (
        select
          coalesce(r.returned_at, r.actual_end_at, r.start_at, r.start_time) as sort_at,
          jsonb_build_object(
            'reservation_id', r.id::text,
            'vehicle_name', coalesce(v.model_name, '차량'),
            'start_at', coalesce(r.start_at, r.start_time),
            'end_at', coalesce(r.end_at, r.end_time),
            'rental_started_at', r.rental_started_at,
            'returned_at', r.returned_at,
            'actual_end_at', r.actual_end_at,
            'total_price', coalesce(r.total_price, 0),
            'status', r.status,
            'second_driver_name', nullif(trim(r.second_driver_name), ''),
            'second_driver_license', nullif(trim(r.second_driver_license), '')
          ) as row_data
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where r.user_id = res.user_id
      ) rental_rows
    ), '[]'::jsonb)
  )
  into v_result
  from public.residents res
  join public.complexes c on c.id = res.complex_id
  left join public.user_profiles up on up.user_id = res.user_id
  left join auth.users au on au.id = res.user_id
  where res.user_id = p_user_id;

  if v_result is null then
    raise exception 'resident_not_found';
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;
