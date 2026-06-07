-- 쿠폰 등록 시 code NOT NULL 충족

drop function if exists public.upsert_super_admin_coupon(text, text, integer, integer);
drop function if exists public.upsert_super_admin_coupon(text, text, integer, integer, text);

create or replace function public.upsert_super_admin_coupon(
  p_coupon_id text default null,
  p_title text default null,
  p_discount_amount integer default 0,
  p_min_amount integer default 0,
  p_code text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_code text;
begin
  perform public.assert_is_super_admin();

  if p_coupon_id is null then
    v_code := coalesce(
      nullif(trim(p_code), ''),
      'COUPON_' || (extract(epoch from clock_timestamp()) * 1000)::bigint::text
    );

    insert into public.coupons (title, discount_amount, min_amount, code)
    values (
      coalesce(nullif(trim(p_title), ''), '쿠폰'),
      greatest(coalesce(p_discount_amount, 0), 0),
      greatest(coalesce(p_min_amount, 0), 0),
      v_code
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

revoke all on function public.upsert_super_admin_coupon(text, text, integer, integer, text) from public;
grant execute on function public.upsert_super_admin_coupon(text, text, integer, integer, text) to authenticated;
