-- =============================================================================
-- confirm_rental_license_for_me 수정
-- Supabase SQL Editor → 전체 선택 후 Run
-- =============================================================================
-- [문제]
--   기존 RPC가 verify_license_for_me() 를 호출 → user_profiles.license_verified=true
--   user_profiles 트리거(prevent_user_profiles_license_self_verify)가
--   license_verified_self_change_forbidden 예외 발생
--
-- [해결]
--   예약(reservations) 행의 license_verified 만 true 로 설정 (프로필 승인과 분리)
--   start_rental_for_me 에서 user_profiles assert 제거 (예약 단위 license_verified 사용)
-- =============================================================================

-- 컬럼 보장
alter table public.reservations
  add column if not exists photos_uploaded boolean not null default false;

alter table public.reservations
  add column if not exists license_verified boolean not null default false;

comment on column public.reservations.license_verified is
  '이번 예약 대여 플로우에서 면허 확인 완료 (user_profiles.license_verified 와 별개)';

-- ── confirm_rental_license_for_me ────────────────────────────────────────────
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
  v_updated integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  -- 본인 예약 잠금
  select *
  into v_row
  from public.reservations r
  where r.id::text = v_id
    and r.user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  -- 결제 완료(confirmed) 예약만 면허 확인 가능
  if v_row.status <> 'confirmed' then
    raise exception 'invalid_status';
  end if;

  -- 사진 업로드 완료 확인
  if coalesce(v_row.photos_uploaded, false) = false
     and (
       v_row.pickup_photos is null
       or cardinality(v_row.pickup_photos) < 6
     ) then
    raise exception 'photos_required';
  end if;

  -- 면허번호·만료일 등록 여부 (프로필 license_verified 는 건드리지 않음)
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

  -- verify_license_for_me() 호출 제거 — reservations.license_verified 만 true
  update public.reservations r
  set
    license_verified = true,
    updated_at = now()
  where r.id::text = v_id
    and r.user_id = v_user
    and r.status = 'confirmed';

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'license_update_failed';
  end if;

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

-- ── start_rental_for_me: 예약 license_verified 기준 (프로필 assert 제거) ───
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

  if v_row.status = 'in_use' then
    return jsonb_build_object(
      'success', true,
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

  -- assert_booking_license_verified 제거: 대여 플로우는 reservations.license_verified 사용

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
    'success', true,
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

-- ── 확인 쿼리 ───────────────────────────────────────────────────────────────
-- select id, status, photos_uploaded, license_verified
-- from public.reservations
-- where user_id = auth.uid()
-- order by created_at desc
-- limit 5;
