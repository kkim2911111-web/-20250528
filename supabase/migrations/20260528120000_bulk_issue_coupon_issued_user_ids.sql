-- bulk_issue_coupon — 반환값에 issued_user_ids 추가 (푸시 발송 대상 식별)

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
  v_issued_user_ids uuid[] := '{}';
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
    v_issued_user_ids := array_append(v_issued_user_ids, v_user_id);
  end loop;

  return jsonb_build_object(
    'ok', true,
    'issued_count', v_issued,
    'skipped_count', v_skipped,
    'issued_user_ids', to_jsonb(v_issued_user_ids)
  );
end;
$$;

revoke all on function public.bulk_issue_coupon(text, uuid, uuid[]) from public;
grant execute on function public.bulk_issue_coupon(text, uuid, uuid[]) to authenticated;

comment on function public.bulk_issue_coupon(text, uuid, uuid[]) is
  '쿠폰 일괄 발급 — issued_count, skipped_count, issued_user_ids 반환';
