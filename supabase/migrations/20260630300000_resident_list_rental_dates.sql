-- 입주민 목록: 가입일·최근 대여일 일괄 집계 (취소 제외, 노쇼 포함)

-- ── 1) 단지 관리자 고객 목록 ───────────────────────────────────
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
    lr.last_rental_at
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
    group by s.user_id
  ) st on st.user_id = res.user_id
  left join (
    select
      r.user_id,
      max(coalesce(r.start_at, r.start_time)) as last_rental_at
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where r.status <> 'cancelled'
      and v.complex_id = v_complex_id
    group by r.user_id
  ) lr on lr.user_id = res.user_id
  where res.complex_id = v_complex_id
    and res.approved = true
  order by lr.last_rental_at desc nulls last, res.created_at desc, full_name asc nulls last;
end;
$$;

revoke all on function public.get_admin_customers_for_staff() from public;
grant execute on function public.get_admin_customers_for_staff() to authenticated;

comment on function public.get_admin_customers_for_staff() is
  '단지 staff — 승인 입주민 목록 + 가입일·최근 대여일(취소 제외)';

-- ── 2) 최고관리자 입주민 목록 ──────────────────────────────────
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
      r.user_id,
      v.complex_id,
      max(coalesce(r.start_at, r.start_time)) as last_rental_at
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where r.status <> 'cancelled'
    group by r.user_id, v.complex_id
  ) lr on lr.user_id = res.user_id
    and lr.complex_id = res.complex_id
  order by c.name asc nulls last, res.created_at desc;
end;
$$;

revoke all on function public.get_super_admin_residents() from public;
grant execute on function public.get_super_admin_residents() to authenticated;

-- ── 3) 최고관리자 입주민 상세 — 최근 대여일 ────────────────────
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
      select max(coalesce(r.start_at, r.start_time))
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where r.user_id = res.user_id
        and r.status <> 'cancelled'
        and v.complex_id = res.complex_id
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
