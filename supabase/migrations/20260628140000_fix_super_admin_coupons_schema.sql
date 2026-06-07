-- coupons 실제 컬럼: id, code, title, discount_amount, min_amount, expires_at, is_active, created_at

drop function if exists public.upsert_super_admin_coupon(text, text, text, integer, integer);

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

create or replace function public.upsert_super_admin_coupon(
  p_coupon_id text default null,
  p_title text default null,
  p_discount_amount integer default 0,
  p_min_amount integer default 0
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.assert_is_super_admin();
  if p_coupon_id is null then
    insert into public.coupons (title, discount_amount, min_amount)
    values (
      coalesce(nullif(trim(p_title), ''), '쿠폰'),
      greatest(coalesce(p_discount_amount, 0), 0),
      greatest(coalesce(p_min_amount, 0), 0)
    )
    returning id into v_id;
    return v_id::text;
  end if;

  update public.coupons
  set
    title = coalesce(nullif(trim(p_title), ''), title),
    discount_amount = greatest(coalesce(p_discount_amount, discount_amount), 0),
    min_amount = greatest(coalesce(p_min_amount, min_amount), 0)
  where id::text = trim(p_coupon_id);
  if not found then
    raise exception 'coupon_not_found';
  end if;
  return trim(p_coupon_id);
end;
$$;

revoke all on function public.get_super_admin_coupons() from public;
grant execute on function public.get_super_admin_coupons() to authenticated;

revoke all on function public.upsert_super_admin_coupon(text, text, integer, integer) from public;
grant execute on function public.upsert_super_admin_coupon(text, text, integer, integer) to authenticated;
