-- 입주민 상세 대여 이력 — 노쇼 표시용 is_no_show (집계 로직 변경 없음)

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
            'is_no_show', coalesce(r.is_no_show, false),
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
