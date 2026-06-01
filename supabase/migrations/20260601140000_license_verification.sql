-- ============================================================
-- 2단계: 면허 인증 (license_verified) + 예약 차단 + 관리자 승인 RPC
-- Supabase SQL Editor → Run (또는 supabase db push)
-- ============================================================
-- 목표
--   • user_profiles.license_verified — 관리자 승인 후 true
--   • 사용자는 면허 정보·사진 제출 가능, verified 직접 변경 불가
--   • 지점 관리자(staff) — 동 단지 입주민 면허 승인/거절
--   • license_verified = false → prepare_payment_order / create_reservation 차단
-- ============================================================

-- ── 0) user_profiles 컬럼 ─────────────────────────────────
alter table public.user_profiles
  add column if not exists license_verified boolean not null default false;

alter table public.user_profiles
  add column if not exists license_photo_url text;

alter table public.user_profiles
  add column if not exists license_rejection_reason text;

alter table public.user_profiles
  add column if not exists license_submitted_at timestamptz;

alter table public.user_profiles
  add column if not exists license_verified_at timestamptz;

alter table public.user_profiles
  add column if not exists license_verified_by uuid references auth.users(id);

create index if not exists user_profiles_license_verified_idx
  on public.user_profiles (license_verified)
  where license_verified = false;

-- ── 1) 자가 license_verified 변경 방지 트리거 ───────────────
create or replace function public.prevent_user_profiles_license_self_verify()
returns trigger
language plpgsql
as $$
begin
  -- 본인은 license_verified=true 로 승인하거나 verified_at/by 를 조작할 수 없음
  -- false 로 재제출(재심사 요청)은 허용
  if new.license_verified is true
     and (coalesce(old.license_verified, false) = false
          or new.license_verified_at is distinct from old.license_verified_at
          or new.license_verified_by is distinct from old.license_verified_by) then
    raise exception 'license_verified_self_change_forbidden';
  end if;
  if new.license_verified_by is distinct from old.license_verified_by then
    raise exception 'license_verified_by_self_change_forbidden';
  end if;
  if new.license_verified_at is distinct from old.license_verified_at
     and new.license_verified is true then
    raise exception 'license_verified_at_self_change_forbidden';
  end if;
  return new;
end;
$$;

drop trigger if exists user_profiles_prevent_license_self_verify
  on public.user_profiles;

create trigger user_profiles_prevent_license_self_verify
before update on public.user_profiles
for each row
when (old.user_id = auth.uid())
execute function public.prevent_user_profiles_license_self_verify();

-- ── 2) RLS 보강 ───────────────────────────────────────────
alter table public.user_profiles enable row level security;

drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own"
on public.user_profiles for select to authenticated
using (user_id = auth.uid());

-- 지점 관리자: 동 단지 입주민 프로필 조회 (면허 심사용)
drop policy if exists "user_profiles_staff_select_complex" on public.user_profiles;
create policy "user_profiles_staff_select_complex"
on public.user_profiles for select to authenticated
using (
  exists (
    select 1
    from public.residents r
    join public.staff_users s on s.complex_id = r.complex_id
    where r.user_id = user_profiles.user_id
      and s.user_id = auth.uid()
      and s.approved = true
  )
);

drop policy if exists "user_profiles_insert_own" on public.user_profiles;
create policy "user_profiles_insert_own"
on public.user_profiles for insert to authenticated
with check (
  user_id = auth.uid()
  and license_verified = false
);

drop policy if exists "user_profiles_update_own" on public.user_profiles;
create policy "user_profiles_update_own"
on public.user_profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- ── 3) 면허 검증 헬퍼 ─────────────────────────────────────
create or replace function public.is_my_license_verified()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select p.license_verified
      from public.user_profiles p
      where p.user_id = auth.uid()
        and p.license_number is not null
        and trim(p.license_number) <> ''
        and p.license_expiry is not null
        and trim(p.license_expiry) <> ''
    ),
    false
  );
$$;

revoke all on function public.is_my_license_verified() from public;
grant execute on function public.is_my_license_verified() to authenticated;

create or replace function public.assert_booking_license_verified(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.user_profiles p
    where p.user_id = p_user_id
      and p.license_verified = true
      and p.license_number is not null
      and trim(p.license_number) <> ''
      and p.license_expiry is not null
      and trim(p.license_expiry) <> ''
  ) then
    raise exception 'license_not_verified';
  end if;
end;
$$;

revoke all on function public.assert_booking_license_verified(uuid) from public;

-- ── 4) 입주민 — 면허 정보 제출 (재제출 시 verified=false) ───
create or replace function public.submit_license_for_me(
  p_license_number text,
  p_license_expiry text,
  p_license_photo_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_license_number is null or trim(p_license_number) = '' then
    raise exception 'license_number_required';
  end if;

  if p_license_expiry is null or trim(p_license_expiry) = '' then
    raise exception 'license_expiry_required';
  end if;

  insert into public.user_profiles (
    user_id,
    license_number,
    license_expiry,
    license_photo_url,
    license_verified,
    license_rejection_reason,
    license_submitted_at,
    license_verified_at,
    license_verified_by
  ) values (
    v_user,
    trim(p_license_number),
    trim(p_license_expiry),
    nullif(trim(coalesce(p_license_photo_url, '')), ''),
    false,
    null,
    now(),
    null,
    null
  )
  on conflict (user_id) do update set
    license_number = excluded.license_number,
    license_expiry = excluded.license_expiry,
    license_photo_url = coalesce(excluded.license_photo_url, public.user_profiles.license_photo_url),
    license_verified = false,
    license_rejection_reason = null,
    license_submitted_at = now(),
    license_verified_at = null,
    license_verified_by = null,
    updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'licenseVerified', false,
    'submittedAt', now()
  );
end;
$$;

revoke all on function public.submit_license_for_me(text, text, text) from public;
grant execute on function public.submit_license_for_me(text, text, text) to authenticated;

-- ── 5) 관리자 — 면허 승인/거절 ────────────────────────────
create or replace function public.review_license_for_staff(
  p_user_id uuid,
  p_approved boolean,
  p_rejection_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
  v_complex_id uuid;
begin
  if v_staff is null then
    raise exception 'not_authenticated';
  end if;

  select s.complex_id into v_complex_id
  from public.staff_users s
  where s.user_id = v_staff and s.approved = true;

  if v_complex_id is null then
    raise exception 'staff_not_approved';
  end if;

  if not exists (
    select 1
    from public.residents r
    where r.user_id = p_user_id
      and r.complex_id = v_complex_id
  ) then
    raise exception 'resident_not_in_complex';
  end if;

  if not exists (
    select 1 from public.user_profiles p where p.user_id = p_user_id
  ) then
    raise exception 'profile_not_found';
  end if;

  if p_approved then
    update public.user_profiles
    set
      license_verified = true,
      license_rejection_reason = null,
      license_verified_at = now(),
      license_verified_by = v_staff,
      updated_at = now()
    where user_id = p_user_id;
  else
    update public.user_profiles
    set
      license_verified = false,
      license_rejection_reason = nullif(trim(coalesce(p_rejection_reason, '')), ''),
      license_verified_at = null,
      license_verified_by = null,
      updated_at = now()
    where user_id = p_user_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'userId', p_user_id,
    'licenseVerified', p_approved
  );
end;
$$;

revoke all on function public.review_license_for_staff(uuid, boolean, text) from public;
grant execute on function public.review_license_for_staff(uuid, boolean, text) to authenticated;

-- ── 6) 관리자 — 면허 심사 대기 목록 ───────────────────────
create or replace function public.list_license_reviews_for_staff()
returns table (
  user_id uuid,
  full_name text,
  phone text,
  license_number text,
  license_expiry text,
  license_photo_url text,
  license_verified boolean,
  license_submitted_at timestamptz,
  license_rejection_reason text,
  building text,
  unit text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
  v_complex_id uuid;
begin
  if v_staff is null then
    raise exception 'not_authenticated';
  end if;

  select s.complex_id into v_complex_id
  from public.staff_users s
  where s.user_id = v_staff and s.approved = true;

  if v_complex_id is null then
    raise exception 'staff_not_approved';
  end if;

  return query
  select
    p.user_id,
    p.full_name,
    p.phone,
    p.license_number,
    p.license_expiry,
    p.license_photo_url,
    p.license_verified,
    p.license_submitted_at,
    p.license_rejection_reason,
    r.building,
    r.unit
  from public.user_profiles p
  join public.residents r on r.user_id = p.user_id
  where r.complex_id = v_complex_id
    and r.approved = true
    and p.license_number is not null
    and trim(p.license_number) <> ''
  order by
    case when p.license_verified then 1 else 0 end,
    p.license_submitted_at desc nulls last;
end;
$$;

revoke all on function public.list_license_reviews_for_staff() from public;
grant execute on function public.list_license_reviews_for_staff() to authenticated;

-- ── 7) 예약 RPC — 면허 미승인 차단 ────────────────────────
-- prepare_payment_order
create or replace function public.prepare_payment_order(
  p_vehicle_id text,
  p_vehicle_name text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_name text;
  v_order_id text;
  v_order_name text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_booking_license_verified(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  if p_total_price is null or p_total_price <= 0 then
    raise exception 'invalid_price';
  end if;

  select r.complex_id into v_complex_id
  from public.residents r
  where r.user_id = v_user and r.approved = true;

  if v_complex_id is null then
    raise exception 'not_approved';
  end if;

  if not public.is_vehicle_in_my_complex(p_vehicle_id) then
    raise exception 'vehicle_not_in_complex';
  end if;

  if exists (
    select 1 from public.reservations r
    where r.vehicle_id::text = p_vehicle_id
      and coalesce(r.status, 'pending') in ('pending', 'confirmed')
      and coalesce(r.start_time, r.start_at) < p_end_time
      and coalesce(r.end_time, r.end_at) > p_start_time
  ) then
    raise exception 'time_overlap';
  end if;

  select coalesce(p_vehicle_name, v.model_name, v.name, '단지카') into v_vehicle_name
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  v_order_id := 'danji_' || floor(extract(epoch from now()) * 1000)::bigint
    || '_' || substr(md5(random()::text), 1, 8);
  v_order_name := v_vehicle_name || ' 예약';

  insert into public.payment_orders (
    order_id, user_id, vehicle_id, vehicle_name,
    start_time, end_time, total_price, status
  ) values (
    v_order_id, v_user, p_vehicle_id, v_vehicle_name,
    p_start_time, p_end_time, p_total_price, 'pending'
  );

  return jsonb_build_object(
    'orderId', v_order_id,
    'amount', p_total_price,
    'orderName', v_order_name,
    'customerKey', v_user::text
  );
end;
$$;

-- create_reservation_for_me (면허 검증 추가)
create or replace function public.create_reservation_for_me(
  p_vehicle_id text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_id_type text;
  v_res_id text;
  v_sql text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  perform public.assert_booking_license_verified(v_user);

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  select r.complex_id into v_complex_id
  from public.residents r
  where r.user_id = v_user and r.approved = true;

  if v_complex_id is null then
    raise exception 'not_approved';
  end if;

  if not public.is_vehicle_in_my_complex(p_vehicle_id) then
    raise exception 'vehicle_not_in_complex';
  end if;

  if exists (
    select 1 from public.reservations r
    where r.vehicle_id::text = p_vehicle_id
      and coalesce(r.status, 'pending') in ('pending', 'confirmed')
      and coalesce(r.start_time, r.start_at) < p_end_time
      and coalesce(r.end_time, r.end_at) > p_start_time
  ) then
    raise exception 'time_overlap';
  end if;

  select c.data_type into v_vehicle_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'vehicles'
    and c.column_name = 'id';

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id, vehicle_id, start_time, end_time, start_at, end_at, total_price, status
    ) values (
      $1, $2::%s, $3, $4, $5, $6, $7, 'pending'
    ) returning id::text
    $f$,
    v_vehicle_id_type
  );

  execute v_sql
    using v_user, p_vehicle_id, p_start_time, p_end_time,
          p_start_time, p_end_time, coalesce(p_total_price, 0)
    into v_res_id;

  return jsonb_build_object('id', v_res_id, 'status', 'pending');
end;
$$;

-- ── 8) Storage — 면허 사진 버킷 (선택) ────────────────────
-- Dashboard → Storage → New bucket: license-photos (private)
-- 아래 정책은 버킷 생성 후 실행
--
-- create policy "license_photos_upload_own"
-- on storage.objects for insert to authenticated
-- with check (
--   bucket_id = 'license-photos'
--   and (storage.foldername(name))[1] = auth.uid()::text
-- );
--
-- create policy "license_photos_read_own_or_staff"
-- on storage.objects for select to authenticated
-- using (
--   bucket_id = 'license-photos'
--   and (
--     (storage.foldername(name))[1] = auth.uid()::text
--     or exists (
--       select 1 from public.staff_users s
--       join public.residents r on r.complex_id = s.complex_id
--       where s.user_id = auth.uid() and s.approved = true
--         and r.user_id::text = (storage.foldername(name))[1]
--     )
--   )
-- );

-- ============================================================
-- 9) 적용 확인
-- ============================================================
--
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'user_profiles'
--   and column_name like 'license%'
-- order by column_name;
--
-- select public.is_my_license_verified();
--
-- -- 면허 미승인 시 prepare_payment_order → license_not_verified 예외
