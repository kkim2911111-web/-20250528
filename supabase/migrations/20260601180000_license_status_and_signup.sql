-- license_status + signup_completed + submit_license 갱신

alter table public.user_profiles
  add column if not exists license_status text not null default 'none';

alter table public.user_profiles
  add column if not exists signup_completed boolean not null default false;

comment on column public.user_profiles.license_status is
  'none | pending | approved | rejected';

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
    license_status,
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
    'pending',
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
    license_status = 'pending',
    license_rejection_reason = null,
    license_submitted_at = now(),
    license_verified_at = null,
    license_verified_by = null,
    updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'licenseVerified', false,
    'licenseStatus', 'pending',
    'submittedAt', now()
  );
end;
$$;

-- 기존 승인/거절 RPC에 license_status 동기화 추가
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
      license_status = 'approved',
      license_rejection_reason = null,
      license_verified_at = now(),
      license_verified_by = v_staff,
      updated_at = now()
    where user_id = p_user_id;
  else
    update public.user_profiles
    set
      license_verified = false,
      license_status = 'rejected',
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

-- 기존 데이터 license_status 보정
update public.user_profiles
set license_status = case
  when license_verified = true then 'approved'
  when license_rejection_reason is not null
       and trim(license_rejection_reason) <> '' then 'rejected'
  when license_number is not null
       and trim(license_number) <> ''
       and license_expiry is not null
       and trim(license_expiry) <> '' then 'pending'
  else 'none'
end
where license_status = 'none' or license_status is null;
