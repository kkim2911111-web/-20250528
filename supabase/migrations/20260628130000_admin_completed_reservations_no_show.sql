-- 완료 탭: 노쇼 구분 (return_type / is_no_show) + 강제 반납 시 is_no_show 표시

alter table public.reservations
  add column if not exists is_no_show boolean not null default false;

comment on column public.reservations.is_no_show is
  '노쇼 강제 반납 등 관리자 처리 노쇼 여부';

create or replace function public.cancel_reservation_for_staff(
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
  v_start timestamptz;
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

  if v_res.status <> 'confirmed' then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_res.start_at, v_res.start_time);
  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_start > v_now then
    raise exception 'not_no_show_suspect';
  end if;

  update public.reservations
  set
    status = 'cancelled',
    is_no_show = true,
    updated_at = v_now
  where id = v_res.id;

  if v_res.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = v_now
    where order_id = v_res.order_id;
  end if;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'cancelled',
    'isNoShow', true
  );
end;
$$;

create or replace function public.get_admin_completed_reservations()
returns table (
  reservation_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  return_type text,
  is_no_show boolean,
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
    coalesce(r.total_price, 0) as total_price,
    r.return_type,
    coalesce(r.is_no_show, false) as is_no_show,
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
  order by sort_at desc nulls last;
$$;

revoke all on function public.cancel_reservation_for_staff(text) from public;
grant execute on function public.cancel_reservation_for_staff(text) to authenticated;

revoke all on function public.get_admin_completed_reservations() from public;
grant execute on function public.get_admin_completed_reservations() to authenticated;
