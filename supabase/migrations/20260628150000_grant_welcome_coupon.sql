-- 온보딩 완료 시 가입 축하 쿠폰 자동 발급

create or replace function public.grant_welcome_coupon(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_coupon_id uuid;
  v_user_coupon_id uuid;
  v_expires_at timestamptz;
  v_title constant text := '가입 축하 쿠폰';
begin
  if v_caller is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is distinct from v_caller then
    raise exception 'forbidden';
  end if;

  select c.id
  into v_coupon_id
  from public.coupons c
  where c.title = v_title
  order by c.created_at asc nulls last
  limit 1;

  if v_coupon_id is null then
    insert into public.coupons (
      title,
      discount_amount,
      min_amount,
      is_active
    )
    values (v_title, 5000, 5000, true)
    returning id into v_coupon_id;
  end if;

  if exists (
    select 1
    from public.user_coupons uc
    where uc.user_id = p_user_id
      and uc.coupon_id = v_coupon_id
  ) then
    return jsonb_build_object(
      'ok', true,
      'granted', false,
      'skipped', true,
      'reason', 'already_issued',
      'couponId', v_coupon_id::text
    );
  end if;

  v_expires_at := now() + interval '30 days';

  insert into public.user_coupons (
    user_id,
    coupon_id,
    expires_at,
    is_used
  )
  values (
    p_user_id,
    v_coupon_id,
    v_expires_at,
    false
  )
  returning id into v_user_coupon_id;

  return jsonb_build_object(
    'ok', true,
    'granted', true,
    'skipped', false,
    'userCouponId', v_user_coupon_id::text,
    'couponId', v_coupon_id::text,
    'expiresAt', v_expires_at
  );
end;
$$;

revoke all on function public.grant_welcome_coupon(uuid) from public;
grant execute on function public.grant_welcome_coupon(uuid) to authenticated;
