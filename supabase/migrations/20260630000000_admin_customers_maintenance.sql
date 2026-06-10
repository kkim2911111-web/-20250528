-- 단지 관리자: 고객 관리 RPC + 차량 정비 이력 RPC

-- ── 1) get_admin_customers_for_staff ───────────────────────────
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
  is_blacklisted boolean
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
    coalesce(up.is_blacklisted, false) as is_blacklisted
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
  where res.complex_id = v_complex_id
    and res.approved = true
  order by st.last_used_at desc nulls last, full_name asc nulls last;
end;
$$;

-- ── 2) get_admin_customer_reservations ─────────────────────────
drop function if exists public.get_admin_customer_reservations(uuid);

create or replace function public.get_admin_customer_reservations(p_user_id uuid)
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  return_completed_at timestamptz,
  sort_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
begin
  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = auth.uid()
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    raise exception 'staff_not_found';
  end if;

  if not exists (
    select 1
    from public.residents r
    where r.user_id = p_user_id
      and r.complex_id = v_complex_id
  ) then
    raise exception 'resident_not_found';
  end if;

  return query
  select
    r.id::text as reservation_id,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    r.status,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    public.sales_return_completed_at(
      r.returned_at,
      r.actual_end_at,
      coalesce(r.end_at, r.end_time)
    ) as return_completed_at,
    coalesce(
      public.sales_return_completed_at(
        r.returned_at,
        r.actual_end_at,
        coalesce(r.end_at, r.end_time)
      ),
      r.updated_at,
      coalesce(r.end_at, r.end_time),
      coalesce(r.start_at, r.start_time),
      r.created_at
    ) as sort_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where r.user_id = p_user_id
    and v.complex_id = v_complex_id
  order by sort_at desc nulls last;
end;
$$;

-- ── 3) set_admin_user_blacklist ────────────────────────────────
drop function if exists public.set_admin_user_blacklist(uuid, boolean);

create or replace function public.set_admin_user_blacklist(
  p_user_id uuid,
  p_blacklisted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
begin
  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = auth.uid()
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    raise exception 'staff_not_found';
  end if;

  if not exists (
    select 1
    from public.residents r
    where r.user_id = p_user_id
      and r.complex_id = v_complex_id
      and r.approved = true
  ) then
    raise exception 'resident_not_found';
  end if;

  update public.user_profiles
  set
    is_blacklisted = p_blacklisted,
    updated_at = now()
  where user_id = p_user_id;

  if not found then
    raise exception 'profile_not_found';
  end if;
end;
$$;

-- ── 4) get_vehicle_maintenance_history_for_staff ───────────────
drop function if exists public.get_vehicle_maintenance_history_for_staff(bigint);

create or replace function public.get_vehicle_maintenance_history_for_staff(
  p_vehicle_id bigint
)
returns table (
  id uuid,
  maintenance_type text,
  description text,
  mileage integer,
  cost integer,
  performed_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
  v_vehicle_complex_id uuid;
begin
  if p_vehicle_id is null then
    raise exception 'vehicle_id_required';
  end if;

  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = auth.uid()
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    raise exception 'staff_not_found';
  end if;

  select v.complex_id
  into v_vehicle_complex_id
  from public.vehicles v
  where v.id = p_vehicle_id;

  if v_vehicle_complex_id is null or v_vehicle_complex_id <> v_complex_id then
    return;
  end if;

  return query
  select
    m.id,
    m.maintenance_type,
    m.description,
    m.mileage,
    m.cost,
    m.performed_at,
    m.created_at
  from public.vehicle_maintenance m
  where m.vehicle_id = p_vehicle_id
    and m.complex_id = v_complex_id
  order by m.performed_at desc, m.created_at desc;
end;
$$;

-- ── 5) insert_vehicle_maintenance_for_staff ──────────────────
drop function if exists public.insert_vehicle_maintenance_for_staff(
  bigint, text, text, integer, integer, timestamptz
);

create or replace function public.insert_vehicle_maintenance_for_staff(
  p_vehicle_id bigint,
  p_maintenance_type text,
  p_description text default null,
  p_cost integer default 0,
  p_mileage integer default null,
  p_performed_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_complex_id uuid;
  v_current_mileage integer;
  v_id uuid;
  v_type text := nullif(trim(p_maintenance_type), '');
  v_performed timestamptz := coalesce(p_performed_at, now());
begin
  if p_vehicle_id is null then
    raise exception 'vehicle_id_required';
  end if;

  if v_type is null or v_type not in ('wash', 'repair', 'inspection', 'other') then
    raise exception 'invalid_maintenance_type';
  end if;

  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = v_user
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    raise exception 'staff_not_found';
  end if;

  select v.complex_id, coalesce(v.total_mileage, 0)
  into v_vehicle_complex_id, v_current_mileage
  from public.vehicles v
  where v.id = p_vehicle_id
  for update;

  if v_vehicle_complex_id is null or v_vehicle_complex_id <> v_complex_id then
    raise exception 'vehicle_not_found';
  end if;

  insert into public.vehicle_maintenance (
    vehicle_id,
    complex_id,
    maintenance_type,
    description,
    mileage,
    cost,
    performed_at,
    staff_id
  )
  values (
    p_vehicle_id,
    v_complex_id,
    v_type,
    nullif(trim(p_description), ''),
    p_mileage,
    greatest(coalesce(p_cost, 0), 0),
    v_performed,
    v_user
  )
  returning id into v_id;

  if p_mileage is not null and p_mileage > v_current_mileage then
    update public.vehicles
    set total_mileage = p_mileage
    where id = p_vehicle_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.get_admin_customers_for_staff() from public;
grant execute on function public.get_admin_customers_for_staff() to authenticated;

revoke all on function public.get_admin_customer_reservations(uuid) from public;
grant execute on function public.get_admin_customer_reservations(uuid) to authenticated;

revoke all on function public.set_admin_user_blacklist(uuid, boolean) from public;
grant execute on function public.set_admin_user_blacklist(uuid, boolean) to authenticated;

revoke all on function public.get_vehicle_maintenance_history_for_staff(bigint) from public;
grant execute on function public.get_vehicle_maintenance_history_for_staff(bigint) to authenticated;

revoke all on function public.insert_vehicle_maintenance_for_staff(
  bigint, text, text, integer, integer, timestamptz
) from public;
grant execute on function public.insert_vehicle_maintenance_for_staff(
  bigint, text, text, integer, integer, timestamptz
) to authenticated;

comment on function public.get_admin_customers_for_staff() is
  '단지 관리자 — 승인 입주민 목록 + 누적 대여/결제/마지막 이용일';

comment on function public.get_admin_customer_reservations(uuid) is
  '단지 관리자 — 입주민 예약 이력 (동일 단지)';

comment on function public.set_admin_user_blacklist(uuid, boolean) is
  '단지 관리자 — 소속 단지 입주민 블랙리스트 등록/해제';

comment on function public.get_vehicle_maintenance_history_for_staff(bigint) is
  '단지 관리자 — 차량 정비 이력 조회';

comment on function public.insert_vehicle_maintenance_for_staff(
  bigint, text, text, integer, integer, timestamptz
) is
  '단지 관리자 — 정비 이력 등록 + 주행거리 연동';
