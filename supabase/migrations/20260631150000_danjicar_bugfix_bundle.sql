-- 단지카 버그 수정 묶음
-- 1) completed 반납 시각 보정 → sales_completed_reservations_v 포함
-- 2) 입주민 최근대여 = 반납완료일(completed), 취소 제외
-- 3) 최고관리자 차량 RPC 컬럼 정합(299+306 통합)

-- ── 1) 반납 검수 완료 시 반납완료일 보정 ───────────────────────
create or replace function public.complete_return_inspection_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_res public.reservations%rowtype;
  v_return_completed timestamptz;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = p_reservation_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status = 'completed' then
    return jsonb_build_object(
      'reservationId', p_reservation_id,
      'status', 'completed',
      'alreadyCompleted', true
    );
  end if;

  if v_res.status <> 'returned' then
    raise exception 'invalid_status';
  end if;

  v_return_completed := public.sales_return_completed_at(
    v_res.returned_at,
    v_res.actual_end_at,
    coalesce(v_res.end_at, v_res.end_time)
  );

  update public.reservations
  set
    status = 'completed',
    returned_at = coalesce(v_res.returned_at, v_return_completed, v_now),
    actual_end_at = coalesce(
      v_res.actual_end_at,
      v_res.returned_at,
      v_return_completed,
      v_now
    ),
    updated_at = v_now
  where id = v_res.id;

  return jsonb_build_object(
    'reservationId', p_reservation_id,
    'status', 'completed'
  );
end;
$$;

-- 강제 완료·최고관리자 완료도 동일 기준으로 반납완료일 보정
create or replace function public.force_complete_reservation_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_res public.reservations%rowtype;
  v_anchor timestamptz;
  v_return_completed timestamptz;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status not in ('in_use', 'returning') then
    raise exception 'invalid_status';
  end if;

  v_anchor := coalesce(
    v_res.end_at,
    v_res.end_time,
    v_res.rental_started_at,
    v_res.updated_at
  );

  if v_anchor is null or v_anchor > v_now - interval '24 hours' then
    raise exception 'not_eligible_for_force_complete';
  end if;

  v_return_completed := public.sales_return_completed_at(
    v_res.returned_at,
    v_res.actual_end_at,
    coalesce(v_res.end_at, v_res.end_time)
  );

  update public.reservations
  set
    status = 'completed',
    returned_at = coalesce(v_res.returned_at, v_return_completed, v_now),
    actual_end_at = coalesce(
      v_res.actual_end_at,
      v_res.returned_at,
      v_return_completed,
      v_now
    ),
    updated_at = v_now
  where id = v_res.id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'completed'
  );
end;
$$;

create or replace function public.force_super_admin_complete_reservation(p_reservation_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res public.reservations%rowtype;
  v_return_completed timestamptz;
  v_now timestamptz := now();
begin
  perform public.assert_is_super_admin();

  select *
  into v_res
  from public.reservations
  where id::text = trim(p_reservation_id)
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  v_return_completed := public.sales_return_completed_at(
    v_res.returned_at,
    v_res.actual_end_at,
    coalesce(v_res.end_at, v_res.end_time)
  );

  update public.reservations
  set
    status = 'completed',
    returned_at = coalesce(v_res.returned_at, v_return_completed, v_now),
    actual_end_at = coalesce(
      v_res.actual_end_at,
      v_res.returned_at,
      v_return_completed,
      v_now
    ),
    updated_at = v_now
  where id = v_res.id;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_res.id::text
  );
end;
$$;

-- 기존 completed 중 뷰 조건에서 빠진 건 보정 (daily/monthly 포함)
update public.reservations r
set
  returned_at = coalesce(
    r.returned_at,
    public.sales_return_completed_at(
      r.returned_at,
      r.actual_end_at,
      coalesce(r.end_at, r.end_time)
    ),
    r.updated_at
  ),
  actual_end_at = coalesce(
    r.actual_end_at,
    r.returned_at,
    public.sales_return_completed_at(
      r.returned_at,
      r.actual_end_at,
      coalesce(r.end_at, r.end_time)
    ),
    r.updated_at
  ),
  updated_at = r.updated_at
where r.status = 'completed'
  and coalesce(r.is_no_show, false) = false
  and public.sales_return_completed_at(
    r.returned_at,
    r.actual_end_at,
    coalesce(r.end_at, r.end_time)
  ) is null;

-- ── 2) 입주민 최근대여 — completed 반납완료일, 취소 제외 ────────
drop function if exists public.get_admin_customers_for_staff();

create or replace function public.get_admin_customers_for_staff()
returns table (
  user_id uuid,
  full_name text,
  phone text,
  building text,
  unit text,
  rental_count bigint,
  total_payment bigint,
  last_used_at timestamptz,
  is_blacklisted boolean,
  joined_at timestamptz,
  last_rental_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
begin
  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = auth.uid()
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    return;
  end if;

  return query
  select
    res.user_id,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as full_name,
    coalesce(nullif(trim(up.phone), ''), '') as phone,
    res.building,
    res.unit,
    coalesce(st.rental_count, 0)::bigint,
    coalesce(st.total_payment, 0)::bigint,
    st.last_used_at,
    coalesce(up.is_blacklisted, false) as is_blacklisted,
    res.created_at as joined_at,
    st.last_used_at as last_rental_at
  from public.residents res
  left join public.user_profiles up on up.user_id = res.user_id
  left join (
    select
      s.user_id,
      count(*)::bigint as rental_count,
      (
        coalesce(sum(s.gross_amount), 0)::bigint
        + coalesce(sum(coalesce(ext.extension_amount, 0)), 0)::bigint
      ) as total_payment,
      max(s.return_completed_at) as last_used_at
    from public.sales_completed_reservations_v s
    left join (
      select
        e.reservation_id_text,
        sum(e.extension_amount)::bigint as extension_amount
      from public.sales_extension_lines_v e
      where e.complex_id = v_complex_id
      group by e.reservation_id_text
    ) ext on ext.reservation_id_text = s.reservation_id_text
    where s.complex_id = v_complex_id
      and s.status = 'completed'
    group by s.user_id
  ) st on st.user_id = res.user_id
  where res.complex_id = v_complex_id
    and res.approved = true
  order by st.last_used_at desc nulls last, res.created_at desc, full_name asc nulls last;
end;
$$;

revoke all on function public.get_admin_customers_for_staff() from public;
grant execute on function public.get_admin_customers_for_staff() to authenticated;

drop function if exists public.get_super_admin_residents();

create or replace function public.get_super_admin_residents()
returns table (
  user_id uuid,
  complex_id uuid,
  complex_name text,
  building text,
  unit text,
  approved boolean,
  full_name text,
  phone text,
  email text,
  license_verified boolean,
  is_blacklisted boolean,
  created_at timestamptz,
  last_rental_at timestamptz
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
    res.user_id,
    res.complex_id,
    c.name as complex_name,
    res.building,
    res.unit,
    res.approved,
    up.full_name,
    up.phone,
    coalesce(up.email, au.email::text) as email,
    coalesce(up.license_verified, false) as license_verified,
    coalesce(up.is_blacklisted, false) as is_blacklisted,
    res.created_at,
    lr.last_rental_at
  from public.residents res
  join public.complexes c on c.id = res.complex_id
  left join public.user_profiles up on up.user_id = res.user_id
  left join auth.users au on au.id = res.user_id
  left join (
    select
      s.user_id,
      v.complex_id,
      max(s.return_completed_at) as last_rental_at
    from public.sales_completed_reservations_v s
    join public.vehicles v on v.id = s.vehicle_id
    where s.status = 'completed'
    group by s.user_id, v.complex_id
  ) lr on lr.user_id = res.user_id
    and lr.complex_id = res.complex_id
  order by res.created_at desc nulls last, c.name asc nulls last, full_name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_residents() from public;
grant execute on function public.get_super_admin_residents() to authenticated;

drop function if exists public.get_super_admin_resident_detail(uuid);

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
    'last_rental_at', (
      select max(s.return_completed_at)
      from public.sales_completed_reservations_v s
      join public.vehicles v on v.id = s.vehicle_id
      where s.user_id = res.user_id
        and v.complex_id = res.complex_id
        and s.status = 'completed'
    ),
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
            'reservation_number', r.reservation_number,
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

revoke all on function public.get_super_admin_resident_detail(uuid) from public;
grant execute on function public.get_super_admin_resident_detail(uuid) to authenticated;

-- ── 3) 최고관리자 차량 목록 RPC — 컬럼 통합(스키마 캐시 오류 방지) ─
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
  where v.deactivated_at is null
  order by c.name asc nulls last, v.model_name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_vehicles() from public;
grant execute on function public.get_super_admin_vehicles() to authenticated;

comment on function public.get_admin_customers_for_staff() is
  '단지 staff — 승인 입주민. 최근대여=completed 반납완료일(sales_completed_reservations_v), 취소 제외';

comment on function public.get_super_admin_residents() is
  '최고관리자 입주민 — 최근 가입순, 최근대여=completed 반납완료일';
