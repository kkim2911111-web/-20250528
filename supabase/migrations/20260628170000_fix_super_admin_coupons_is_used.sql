-- user_coupons 실제 컬럼: id, user_id, coupon_id, is_used, used_at, created_at
-- (expires_at는 발급 RPC에서 선택 사용)

create or replace function public.get_super_admin_coupons()
returns table (
  coupon_id text,
  code text,
  title text,
  discount_amount integer,
  min_amount integer,
  expires_at timestamptz,
  is_active boolean,
  issued_count bigint,
  used_count bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();
  return query
  select
    c.id::text,
    c.code,
    coalesce(c.title, '쿠폰')::text,
    coalesce(c.discount_amount, 0)::integer,
    coalesce(c.min_amount, 0)::integer,
    c.expires_at,
    coalesce(c.is_active, true),
    (
      select count(*)::bigint from public.user_coupons uc where uc.coupon_id = c.id
    ),
    (
      select count(*)::bigint
      from public.user_coupons uc
      where uc.coupon_id = c.id
        and (coalesce(uc.is_used, false) = true or uc.used_at is not null)
    ),
    c.created_at
  from public.coupons c
  order by c.created_at desc nulls last;
end;
$$;

revoke all on function public.get_super_admin_coupons() from public;
grant execute on function public.get_super_admin_coupons() to authenticated;
