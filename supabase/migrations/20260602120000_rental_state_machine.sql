-- 결제(confirmed) ↔ 대여 시작(in_use) 분리 — 사진·면허 확인 후 문열림 시에만 in_use
-- photos_uploaded / license_verified: 예약 단위 대여 준비 플래그

alter table public.reservations
  add column if not exists photos_uploaded boolean not null default false;

alter table public.reservations
  add column if not exists license_verified boolean not null default false;

comment on column public.reservations.photos_uploaded is
  '대여 시작 전 필수 사진 6장 업로드 완료';
comment on column public.reservations.license_verified is
  '이번 예약 대여 플로우에서 면허 확인 완료';

-- 기존 pickup_photos 기준 백필
update public.reservations r
set photos_uploaded = true
where coalesce(r.photos_uploaded, false) = false
  and r.pickup_photos is not null
  and cardinality(r.pickup_photos) >= 6;

-- ── 면허 확인 (대여 플로우) ─────────────────────────────────────
drop function if exists public.confirm_rental_license_for_me(text);

create or replace function public.confirm_rental_license_for_me(
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
  v_row public.reservations%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
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

  if v_row.status <> 'confirmed' then
    raise exception 'invalid_status';
  end if;

  if coalesce(v_row.photos_uploaded, false) = false
     and (
       v_row.pickup_photos is null
       or cardinality(v_row.pickup_photos) < 6
     ) then
    raise exception 'photos_required';
  end if;

  -- 면허번호·만료일 등록 여부 (user_profiles.license_verified 는 변경하지 않음)
  if not exists (
    select 1
    from public.user_profiles p
    where p.user_id = v_user
      and p.license_number is not null
      and trim(p.license_number) <> ''
      and p.license_expiry is not null
      and trim(p.license_expiry) <> ''
  ) then
    raise exception 'license_info_required';
  end if;

  update public.reservations
  set
    license_verified = true,
    updated_at = now()
  where id::text = v_id
    and user_id = v_user
    and status = 'confirmed';

  return jsonb_build_object(
    'success', true,
    'ok', true,
    'reservationId', v_id,
    'licenseVerified', true
  );
end;
$$;

revoke all on function public.confirm_rental_license_for_me(text) from public;
grant execute on function public.confirm_rental_license_for_me(text) to authenticated;
grant execute on function public.confirm_rental_license_for_me(text) to service_role;

-- ── start_rental_for_me: confirmed → in_use (문열림 시에만) ───────
drop function if exists public.start_rental_for_me(uuid, text[], integer, text);
drop function if exists public.start_rental_for_me(text, text[], integer, text);

create or replace function public.start_rental_for_me(
  p_reservation_id text,
  p_pickup_photos text[],
  p_mileage_start integer default null,
  p_fuel_level_start text default null
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
  v_now timestamptz := now();
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  if p_pickup_photos is null or cardinality(p_pickup_photos) < 6 then
    raise exception 'photos_required';
  end if;

  if cardinality(p_pickup_photos) > 10 then
    raise exception 'too_many_photos';
  end if;

  if p_mileage_start is not null and p_mileage_start < 0 then
    raise exception 'invalid_mileage';
  end if;

  if p_fuel_level_start is not null
    and p_fuel_level_start not in ('full', '3quarter', 'half', 'quarter', 'empty') then
    raise exception 'invalid_fuel_level';
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

  -- 결제 완료(confirmed/pending)만 대여 시작 가능 — 이미 in_use면 idempotent 반환
  if v_row.status = 'in_use' then
    return jsonb_build_object(
      'reservationId', v_id,
      'status', 'in_use',
      'rentalStartedAt', v_row.rental_started_at,
      'photoCount', cardinality(coalesce(v_row.pickup_photos, '{}'::text[])),
      'alreadyStarted', true
    );
  end if;

  if v_row.status not in ('confirmed', 'pending') then
    raise exception 'invalid_status';
  end if;

  if coalesce(v_row.photos_uploaded, false) = false then
    raise exception 'photos_not_uploaded';
  end if;

  if coalesce(v_row.license_verified, false) = false then
    raise exception 'license_not_verified';
  end if;

  v_start := coalesce(v_row.start_at, v_row.start_time);
  v_end := coalesce(v_row.end_at, v_row.end_time);

  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_now < v_start - interval '30 minutes' then
    raise exception 'too_early';
  end if;

  if v_end is not null and v_now > v_end then
    raise exception 'expired';
  end if;

  update public.reservations
  set
    status = 'in_use',
    rental_started_at = v_now,
    pickup_photos = p_pickup_photos,
    mileage_start = p_mileage_start,
    fuel_level_start = p_fuel_level_start,
    updated_at = v_now
  where id::text = v_id;

  return jsonb_build_object(
    'reservationId', v_id,
    'status', 'in_use',
    'rentalStartedAt', v_now,
    'photoCount', cardinality(p_pickup_photos)
  );
end;
$$;

revoke all on function public.start_rental_for_me(text, text[], integer, text) from public;
grant execute on function public.start_rental_for_me(text, text[], integer, text) to authenticated;
grant execute on function public.start_rental_for_me(text, text[], integer, text) to service_role;

-- ── 결제 RPC가 in_use로 올리지 않도록 재확인 (finalize는 confirmed만) ──
-- finalize_reservation_after_payment 는 status='confirmed' insert — 변경 없음
