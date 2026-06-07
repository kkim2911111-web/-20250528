-- 최고관리자 쿠폰 일괄 발급
-- p_user_ids 지정 시 해당 유저만, 없으면 p_complex_id 단지 전체, 둘 다 없으면 전체 입주민

create or replace function public.bulk_issue_coupon(
  p_coupon_id text,
  p_complex_id uuid default null,
  p_user_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coupon_id uuid;
  v_user_id uuid;
  v_issued integer := 0;
  v_skipped integer := 0;
  v_has_user_ids boolean;
begin
  perform public.assert_is_super_admin();

  if p_coupon_id is null or trim(p_coupon_id) = '' then
    raise exception 'coupon_id_required';
  end if;

  v_coupon_id := trim(p_coupon_id)::uuid;

  if not exists (
    select 1 from public.coupons c where c.id = v_coupon_id
  ) then
    raise exception 'coupon_not_found';
  end if;

  v_has_user_ids := p_user_ids is not null and cardinality(p_user_ids) > 0;

  for v_user_id in
    select distinct r.user_id
    from public.residents r
    where case
      when v_has_user_ids then r.user_id = any(p_user_ids)
      when p_complex_id is not null then r.complex_id = p_complex_id
      else true
    end
  loop
    if exists (
      select 1
      from public.user_coupons uc
      where uc.user_id = v_user_id
        and uc.coupon_id = v_coupon_id
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into public.user_coupons (user_id, coupon_id, is_used)
    values (v_user_id, v_coupon_id, false);

    v_issued := v_issued + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'issued_count', v_issued,
    'skipped_count', v_skipped
  );
end;
$$;

revoke all on function public.bulk_issue_coupon(text, uuid, uuid[]) from public;
grant execute on function public.bulk_issue_coupon(text, uuid, uuid[]) to authenticated;
