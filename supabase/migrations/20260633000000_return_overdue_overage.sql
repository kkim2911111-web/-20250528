-- 반납 지연 표시 + 초과 이용 요금 자동결제

-- ── 1) reservations 컬럼 ─────────────────────────────────────
alter table public.reservations
  add column if not exists is_overdue boolean not null default false,
  add column if not exists overdue_notified_at timestamptz,
  add column if not exists overdue_overage_hours integer,
  add column if not exists overdue_overage_amount integer,
  add column if not exists overdue_overage_charged boolean not null default false,
  add column if not exists overdue_overage_charged_at timestamptz;

comment on column public.reservations.is_overdue is
  '대여 종료 시각 경과 후 미반납(반납지연중)';
comment on column public.reservations.overdue_notified_at is
  '반납 지연 알림 1회 발송 시각';
comment on column public.reservations.overdue_overage_amount is
  '반납 지연 초과 이용 요금(원)';
comment on column public.reservations.overdue_overage_hours is
  '반납 지연 초과 이용 시간(시간 단위 올림)';

-- ── 2) 초과 이용 요금 계산 ─────────────────────────────────────
create or replace function public.calc_return_overdue_overage(
  p_scheduled_end timestamptz,
  p_returned_at timestamptz,
  p_daily_overage_hourly_rate integer
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_late_minutes integer;
  v_billed_hours integer;
  v_amount integer;
begin
  if p_scheduled_end is null
    or p_returned_at is null
    or p_returned_at <= p_scheduled_end then
    return jsonb_build_object(
      'billedHours', 0,
      'amount', 0,
      'rateMissing', false
    );
  end if;

  v_late_minutes := floor(
    extract(epoch from (p_returned_at - p_scheduled_end)) / 60.0
  )::integer;

  v_billed_hours := case
    when v_late_minutes > 0 then ceil(v_late_minutes / 60.0)::integer
    else 0
  end;

  if p_daily_overage_hourly_rate is null or p_daily_overage_hourly_rate <= 0 then
    return jsonb_build_object(
      'billedHours', v_billed_hours,
      'amount', 0,
      'rateMissing', true
    );
  end if;

  v_amount := v_billed_hours * p_daily_overage_hourly_rate;

  return jsonb_build_object(
    'billedHours', v_billed_hours,
    'amount', v_amount,
    'rateMissing', false
  );
end;
$$;

-- ── 3) 반납 시 초과 요금 큐 등록 ───────────────────────────────
create or replace function public.enqueue_overdue_overage_billing(
  p_reservation_id text,
  p_user_id uuid,
  p_complex_id uuid,
  p_amount integer,
  p_billed_hours integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_amount is null or p_amount <= 0 then
    return;
  end if;

  if p_billed_hours is null or p_billed_hours < 1 then
    return;
  end if;

  if exists (
    select 1
    from public.billing_charge_retries b
    where b.charge_type = 'extension'
      and b.reservation_id = p_reservation_id
      and coalesce(b.extension_hours, 0) = p_billed_hours
      and b.status = 'pending'
  ) then
    update public.billing_charge_retries b
    set
      amount = p_amount,
      complex_id = p_complex_id,
      next_retry_at = now() + interval '1 hour',
      updated_at = now()
    where b.charge_type = 'extension'
      and b.reservation_id = p_reservation_id
      and coalesce(b.extension_hours, 0) = p_billed_hours
      and b.status = 'pending';
    return;
  end if;

  insert into public.billing_charge_retries (
    charge_type,
    reservation_id,
    user_id,
    complex_id,
    amount,
    extension_hours,
    retry_count,
    max_retries,
    next_retry_at,
    status
  )
  values (
    'extension',
    p_reservation_id,
    p_user_id,
    p_complex_id,
    p_amount,
    p_billed_hours,
    0,
    3,
    now() + interval '1 hour',
    'pending'
  );
end;
$$;

create or replace function public.apply_return_overdue_overage_for_service(
  p_reservation_id text,
  p_scheduled_end timestamptz,
  p_returned_at timestamptz,
  p_was_overdue boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.reservations%rowtype;
  v_rate integer;
  v_complex_id uuid;
  v_calc jsonb;
  v_amount integer;
  v_hours integer;
begin
  if not coalesce(p_was_overdue, false) then
    return jsonb_build_object('enqueued', false);
  end if;

  select r.*
  into v_row
  from public.reservations r
  where r.id::text = p_reservation_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  select v.daily_overage_hourly_rate, v.complex_id
  into v_rate, v_complex_id
  from public.vehicles v
  where v.id = v_row.vehicle_id;

  if coalesce(v_row.overdue_overage_charged, false) = true then
    return jsonb_build_object('enqueued', false, 'alreadyCharged', true);
  end if;

  v_calc := public.calc_return_overdue_overage(
    p_scheduled_end,
    p_returned_at,
    v_rate
  );

  v_hours := coalesce((v_calc->>'billedHours')::integer, 0);
  v_amount := coalesce((v_calc->>'amount')::integer, 0);

  update public.reservations
  set
    is_overdue = false,
    overdue_overage_hours = case when v_amount > 0 then v_hours else null end,
    overdue_overage_amount = case when v_amount > 0 then v_amount else null end,
    updated_at = now()
  where id = v_row.id;

  if v_amount > 0 then
    perform public.enqueue_overdue_overage_billing(
      p_reservation_id,
      v_row.user_id,
      v_complex_id,
      v_amount,
      v_hours
    );
    return jsonb_build_object(
      'enqueued', true,
      'amount', v_amount,
      'billedHours', v_hours
    );
  end if;

  return jsonb_build_object(
    'enqueued', false,
    'rateMissing', coalesce((v_calc->>'rateMissing')::boolean, false),
    'billedHours', v_hours
  );
end;
$$;

revoke all on function public.enqueue_overdue_overage_billing(
  text, uuid, uuid, integer, integer
) from public;
grant execute on function public.enqueue_overdue_overage_billing(
  text, uuid, uuid, integer, integer
) to service_role;

revoke all on function public.apply_return_overdue_overage_for_service(
  text, timestamptz, timestamptz, boolean
) from public;
grant execute on function public.apply_return_overdue_overage_for_service(
  text, timestamptz, timestamptz, boolean
) to service_role;

-- ── 4) 지연 알림 발송 기록 ─────────────────────────────────────
create or replace function public.mark_overdue_notified_for_service(
  p_reservation_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.reservations
  set overdue_notified_at = now(), updated_at = now()
  where id::text = p_reservation_id
    and is_overdue = true
    and overdue_notified_at is null;
end;
$$;

revoke all on function public.mark_overdue_notified_for_service(text) from public;
grant execute on function public.mark_overdue_notified_for_service(text) to service_role;

create or replace function public.mark_overdue_notified_for_me(
  p_reservation_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  update public.reservations
  set overdue_notified_at = now(), updated_at = now()
  where id::text = v_id
    and user_id = v_user
    and is_overdue = true
    and overdue_notified_at is null;
end;
$$;

revoke all on function public.mark_overdue_notified_for_me(text) from public;
grant execute on function public.mark_overdue_notified_for_me(text) to authenticated;

-- ── 5) 만료 처리 — in_use 지연 표시 (자동반납 제거) ────────────
create or replace function public.auto_return_expired_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_no_show_count integer := 0;
  v_overdue_count integer := 0;
  v_no_shows jsonb := '[]'::jsonb;
  v_overdues jsonb := '[]'::jsonb;
begin
  with no_show_updated as (
    update public.reservations r
    set
      status = 'completed',
      is_no_show = true,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_no_shows, v_no_show_count
  from no_show_updated;

  with overdue_updated as (
    update public.reservations r
    set
      is_overdue = true,
      updated_at = v_now
    where r.status = 'in_use'
      and coalesce(r.is_overdue, false) = false
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_overdues, v_overdue_count
  from overdue_updated;

  return jsonb_build_object(
    'overdueCount', v_overdue_count,
    'noShowCount', v_no_show_count,
    'overdues', v_overdues,
    'noShows', v_no_shows,
    'processedAt', v_now
  );
end;
$$;

-- integer → jsonb 전환(320) 미적용 DB 대비 — 이미 jsonb면 무해
drop function if exists public.auto_complete_expired_reservations_for_me();

create or replace function public.auto_complete_expired_reservations_for_me()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_no_show_count integer := 0;
  v_overdue_count integer := 0;
  v_no_shows jsonb := '[]'::jsonb;
  v_overdues jsonb := '[]'::jsonb;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  with no_show_updated as (
    update public.reservations r
    set
      status = 'completed',
      is_no_show = true,
      actual_end_at = coalesce(
        r.actual_end_at,
        coalesce(r.end_at, r.end_time),
        v_now
      ),
      updated_at = v_now
    where r.user_id = v_user
      and r.status = 'confirmed'
      and r.rental_started_at is null
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_no_shows, v_no_show_count
  from no_show_updated;

  with overdue_updated as (
    update public.reservations r
    set
      is_overdue = true,
      updated_at = v_now
    where r.user_id = v_user
      and r.status = 'in_use'
      and coalesce(r.is_overdue, false) = false
      and coalesce(r.end_at, r.end_time) is not null
      and coalesce(r.end_at, r.end_time) < v_now
    returning
      r.id::text as reservation_id,
      r.user_id,
      r.vehicle_id::text as vehicle_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'reservationId', reservation_id,
          'userId', user_id,
          'vehicleId', vehicle_id
        )
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_overdues, v_overdue_count
  from overdue_updated;

  return jsonb_build_object(
    'overdueCount', v_overdue_count,
    'noShowCount', v_no_show_count,
    'overdues', v_overdues,
    'noShows', v_no_shows,
    'processedAt', v_now
  );
end;
$$;

-- ── 6) 고객 반납 — 초과 요금 큐 등록 ───────────────────────────
create or replace function public.complete_rental_for_me(
  p_reservation_id text,
  p_return_photos text[],
  p_mileage_end integer,
  p_fuel_level_end text,
  p_is_accident boolean default false,
  p_accident_note text default null,
  p_is_early_return boolean default false,
  p_early_return_acknowledged boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_scheduled_end timestamptz;
  v_now timestamptz := now();
  v_was_overdue boolean;
  v_overage jsonb;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  if p_return_photos is null or cardinality(p_return_photos) < 1 then
    raise exception 'photos_required';
  end if;

  if cardinality(p_return_photos) > 10 then
    raise exception 'too_many_photos';
  end if;

  if p_mileage_end is null or p_mileage_end < 0 then
    raise exception 'invalid_mileage';
  end if;

  if p_fuel_level_end is null
    or p_fuel_level_end not in ('full', '3quarter', 'half', 'quarter', 'empty') then
    raise exception 'invalid_fuel_level';
  end if;

  if p_is_accident and (p_accident_note is null or length(trim(p_accident_note)) = 0) then
    raise exception 'accident_note_required';
  end if;

  if p_is_early_return and not p_early_return_acknowledged then
    raise exception 'early_return_not_acknowledged';
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id::text = v_id
    and r.user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status <> 'in_use' then
    raise exception 'invalid_status';
  end if;

  v_scheduled_end := coalesce(v_row.end_at, v_row.end_time);

  if p_is_early_return then
    if v_scheduled_end is null then
      raise exception 'invalid_end_time';
    end if;
    if v_now >= v_scheduled_end then
      raise exception 'not_early_return';
    end if;
  end if;

  if p_mileage_end < coalesce(v_row.mileage_start, 0) then
    raise exception 'mileage_decreased';
  end if;

  v_was_overdue := coalesce(v_row.is_overdue, false);
  if not v_was_overdue
    and not p_is_early_return
    and v_scheduled_end is not null
    and v_scheduled_end < v_now then
    v_was_overdue := true;
  end if;

  update public.reservations
  set
    status = 'returned',
    returned_at = v_now,
    actual_end_at = v_now,
    return_type = 'manual',
    early_return_confirmed_at = case
      when p_is_early_return then v_now
      else null
    end,
    return_photos = p_return_photos,
    mileage_end = p_mileage_end,
    fuel_level_end = p_fuel_level_end,
    is_accident = coalesce(p_is_accident, false),
    accident_note = case
      when coalesce(p_is_accident, false) then nullif(trim(p_accident_note), '')
      else null
    end,
    updated_at = v_now
  where id::text = v_id;

  v_overage := public.apply_return_overdue_overage_for_service(
    v_id,
    v_scheduled_end,
    v_now,
    v_was_overdue
  );

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'returned',
    'returnType', 'manual',
    'returnedAt', v_now,
    'actualEndAt', v_now,
    'scheduledEndAt', v_scheduled_end,
    'isEarlyReturn', p_is_early_return,
    'wasOverdue', v_was_overdue,
    'overdueOverage', v_overage
  );
end;
$$;

-- ── 7) 관리자 강제 반납 — 초과 요금 큐 등록 ────────────────────
create or replace function public.force_return_reservation_for_staff(
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
  v_scheduled_end timestamptz;
  v_now timestamptz := now();
  v_was_overdue boolean;
  v_overage jsonb;
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
  for update of r;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status <> 'in_use' then
    raise exception 'invalid_status';
  end if;

  v_scheduled_end := coalesce(v_res.end_at, v_res.end_time);
  v_was_overdue := coalesce(v_res.is_overdue, false);
  if not v_was_overdue
    and v_scheduled_end is not null
    and v_scheduled_end < v_now then
    v_was_overdue := true;
  end if;

  update public.reservations
  set
    status = 'returned',
    returned_at = coalesce(v_res.returned_at, v_now),
    actual_end_at = v_now,
    return_type = 'manual',
    updated_at = v_now
  where id = v_res.id;

  v_overage := public.apply_return_overdue_overage_for_service(
    v_id,
    v_scheduled_end,
    v_now,
    v_was_overdue
  );

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'returned',
    'wasOverdue', v_was_overdue,
    'overdueOverage', v_overage
  );
end;
$$;

-- ── 8) 관리자 목록 RPC — is_overdue 포함 ───────────────────────
drop function if exists public.get_admin_reservations_with_conflict(integer, integer);

create or replace function public.get_admin_reservations_with_conflict(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  reservation_number text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_started_at timestamptz,
  updated_at timestamptz,
  next_start_at timestamptz,
  next_renter_name text,
  next_renter_phone text,
  is_conflict_risk boolean,
  second_driver_name text,
  second_driver_license text,
  is_overdue boolean,
  overdue_overage_amount integer,
  overdue_overage_charged boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid() and s.approved = true
    limit 1
  ),
  scoped as (
    select
      r.id,
      r.reservation_number,
      r.vehicle_id,
      r.user_id,
      r.status,
      coalesce(r.start_at, r.start_time) as start_at,
      coalesce(r.end_at, r.end_time) as end_at,
      coalesce(r.total_price, 0) as total_price,
      r.rental_started_at,
      r.updated_at,
      coalesce(r.is_overdue, false) as is_overdue,
      r.overdue_overage_amount,
      coalesce(r.overdue_overage_charged, false) as overdue_overage_charged,
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
    s.reservation_number,
    s.vehicle_name,
    s.car_number,
    s.renter_name,
    s.renter_phone,
    s.status,
    s.start_at,
    s.end_at,
    s.total_price,
    s.rental_started_at,
    s.updated_at,
    next_res.next_start_at,
    next_res.next_renter_name,
    next_res.next_renter_phone,
    (s.status = 'in_use' and next_res.next_start_at is not null) as is_conflict_risk,
    s.second_driver_name,
    s.second_driver_license,
    s.is_overdue,
    s.overdue_overage_amount,
    s.overdue_overage_charged
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

revoke all on function public.get_admin_reservations_with_conflict(integer, integer) from public;
grant execute on function public.get_admin_reservations_with_conflict(integer, integer) to authenticated;

-- ── 9) 초과 요금 결제 완료 표시 (Edge Function) ────────────────
create or replace function public.mark_overdue_overage_charged_for_service(
  p_reservation_id text,
  p_amount integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.reservations
  set
    overdue_overage_charged = true,
    overdue_overage_charged_at = now(),
    overdue_overage_amount = coalesce(p_amount, overdue_overage_amount),
    updated_at = now()
  where id::text = p_reservation_id
    and coalesce(overdue_overage_charged, false) = false;
end;
$$;

revoke all on function public.mark_overdue_overage_charged_for_service(text, integer) from public;
grant execute on function public.mark_overdue_overage_charged_for_service(text, integer) to service_role;

-- ── 10) 최고관리자 강제 반납 — 초과 요금 큐 등록 ───────────────
create or replace function public.force_return_reservation_for_super_admin(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := nullif(trim(p_reservation_id), '');
  v_res public.reservations%rowtype;
  v_scheduled_end timestamptz;
  v_now timestamptz := now();
  v_was_overdue boolean;
  v_overage jsonb;
begin
  perform public.assert_is_super_admin();

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_res
  from public.reservations r
  where r.id::text = v_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status <> 'in_use' then
    raise exception 'invalid_status';
  end if;

  v_scheduled_end := coalesce(v_res.end_at, v_res.end_time);
  v_was_overdue := coalesce(v_res.is_overdue, false);
  if not v_was_overdue
    and v_scheduled_end is not null
    and v_scheduled_end < v_now then
    v_was_overdue := true;
  end if;

  update public.reservations
  set
    status = 'returned',
    returned_at = coalesce(v_res.returned_at, v_now),
    actual_end_at = v_now,
    return_type = 'manual',
    updated_at = v_now
  where id = v_res.id;

  v_overage := public.apply_return_overdue_overage_for_service(
    v_id,
    v_scheduled_end,
    v_now,
    v_was_overdue
  );

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'returned',
    'wasOverdue', v_was_overdue,
    'overdueOverage', v_overage
  );
end;
$$;

