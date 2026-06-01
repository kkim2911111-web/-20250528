-- 대여 시작 시 면허 진위 확인 → pending 자동 approved (security definer)

create or replace function public.verify_license_for_me()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row public.user_profiles%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_row
  from public.user_profiles p
  where p.user_id = v_user;

  if not found then
    raise exception 'profile_not_found';
  end if;

  if v_row.license_number is null or trim(v_row.license_number) = '' then
    raise exception 'license_number_required';
  end if;

  if v_row.license_expiry is null or trim(v_row.license_expiry) = '' then
    raise exception 'license_expiry_required';
  end if;

  update public.user_profiles
  set
    license_verified = true,
    license_status = 'approved',
    license_rejection_reason = null,
    license_verified_at = coalesce(license_verified_at, now()),
    updated_at = now()
  where user_id = v_user;

  return jsonb_build_object(
    'ok', true,
    'licenseVerified', true,
    'licenseStatus', 'approved'
  );
end;
$$;

revoke all on function public.verify_license_for_me() from public;
grant execute on function public.verify_license_for_me() to authenticated;
