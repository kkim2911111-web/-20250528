-- 회원가입 온보딩: 토스 카드 등록용 결제 주문

create or replace function public.prepare_signup_card_order()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_order_id text;
  v_amount integer := 100;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1 from public.residents r where r.user_id = v_user
  ) then
    raise exception 'resident_not_registered';
  end if;

  v_order_id := 'signup_card_' || floor(extract(epoch from now()) * 1000)::bigint
    || '_' || substr(md5(random()::text), 1, 8);

  insert into public.payment_orders (
    order_id,
    user_id,
    vehicle_id,
    vehicle_name,
    start_time,
    end_time,
    total_price,
    status
  ) values (
    v_order_id,
    v_user,
    'signup_card',
    '결제카드 등록',
    now(),
    now() + interval '1 hour',
    v_amount,
    'pending'
  );

  return jsonb_build_object(
    'orderId', v_order_id,
    'amount', v_amount,
    'orderName', '단지카 결제카드 등록',
    'customerKey', v_user::text
  );
end;
$$;

revoke all on function public.prepare_signup_card_order() from public;
grant execute on function public.prepare_signup_card_order() to authenticated;
