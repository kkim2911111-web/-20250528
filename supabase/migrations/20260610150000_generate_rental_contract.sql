-- generate_rental_contract RPC (자차: 가입 반영)
-- 동일 정의: supabase/generate_rental_contract.sql

create or replace function public.generate_rental_contract(
  p_reservation_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_res public.reservations%rowtype;
  v_profile public.user_profiles%rowtype;
  v_vehicle_name text;
  v_start timestamptz;
  v_end timestamptz;
  v_original integer;
  v_paid integer;
  v_extension_total integer := 0;
  v_contract text;
  v_second_name text;
  v_second_license text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_res
  from public.reservations r
  where r.id = p_reservation_id
    and r.user_id = v_user;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  select * into v_profile
  from public.user_profiles up
  where up.user_id = v_user;

  select coalesce(v.model_name, '차량') into v_vehicle_name
  from public.vehicles v
  where v.id::text = v_res.vehicle_id::text;

  v_start := coalesce(v_res.start_time, v_res.start_at);
  v_end := coalesce(v_res.end_time, v_res.end_at);

  select coalesce(po.original_price, po.total_price, v_res.total_price, 0),
         coalesce(po.total_price, v_res.total_price, 0)
  into v_original, v_paid
  from public.payment_orders po
  where po.user_id = v_user
    and (
      po.reservation_id::text = p_reservation_id::text
      or (v_res.order_id is not null and po.order_id = v_res.order_id)
    )
  order by po.updated_at desc nulls last, po.created_at desc
  limit 1;

  if v_original is null or v_original = 0 then
    v_original := coalesce(v_res.total_price, 0);
  end if;
  if v_paid is null or v_paid = 0 then
    v_paid := coalesce(v_res.total_price, 0);
  end if;

  select coalesce(sum(re.added_price), 0) into v_extension_total
  from public.reservation_extensions re
  where re.reservation_id = p_reservation_id
    and re.user_id = v_user;

  v_second_name := nullif(trim(v_res.second_driver_name), '');
  v_second_license := nullif(trim(v_res.second_driver_license), '');

  v_contract := format(
    E'단지카 자동차 대여 계약서\n\n■ 예약 정보\n예약번호: %s\n차량: %s\n대여기간: %s ~ %s\n\n■ 임차인\n성명: %s\n연락처: %s\n면허번호: %s\n',
    p_reservation_id::text,
    coalesce(v_vehicle_name, '차량'),
    to_char(v_start at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI'),
    to_char(v_end at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI'),
    coalesce(nullif(trim(v_profile.full_name), ''), '—'),
    coalesce(nullif(trim(v_profile.phone), ''), '—'),
    coalesce(nullif(trim(v_profile.license_number), ''), '—')
  );

  if v_second_name is not null then
    v_contract := v_contract || format(
      E'\n■ 제2운전자\n성명: %s\n면허번호: %s\n',
      v_second_name,
      coalesce(v_second_license, '—')
    );
  end if;

  v_contract := v_contract || format(
    E'\n■ 요금\n예약 금액(정가): %s원\n결제 금액: %s원\n',
    to_char(v_original, 'FM999,999,999'),
    to_char(v_paid, 'FM999,999,999')
  );

  if v_extension_total > 0 then
    v_contract := v_contract || format(
      E'연장 결제 합계: %s원\n총 누적 결제액: %s원\n',
      to_char(v_extension_total, 'FM999,999,999'),
      to_char(v_paid + v_extension_total, 'FM999,999,999')
    );
  end if;

  v_contract := v_contract || (
    E'\n■ 보험 및 면책\n'
    || E'등록 차량은 자동차종합보험(대인·대물·자손)에 가입되어 있습니다.\n'
    || E'대인: 무한\n'
    || E'대물: 2,000만원\n'
    || E'자손: 1,500만원\n'
    || E'자차: 가입 (보험증권별 차량보상 설정금액)\n'
    || E'수리비 50만원 미만: 전액 본인 부담(제조사 서비스센터 견적 참조)\n'
    || E'수리비 50만원 이상: 면책금 50만원 납부 후 보험처리\n\n'
    || E'■ 준수사항\n'
    || E'음주·무면허·고의사고 시 보험처리가 불가합니다.\n'
    || E'계약자 본인(제2운전자 등록 시 해당 운전자 포함)만 운전할 수 있습니다.\n'
    || E'반납 지연 시 추가 요금이 발생할 수 있습니다.\n'
    || E'흡연·반려동물 오염 시 세차비 및 휴차료가 청구될 수 있습니다.\n'
    || E'GPS·시동차단 장치를 임의로 훼손하지 않습니다.\n\n'
    || E'■ 회사\n'
    || E'GT컴퍼니(단지카)\n'
    || E'본 계약서는 단지카 자동차대여약관 및 서비스 이용약관에 따릅니다.\n'
    || E'계약서 생성일시: '
    || to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI')
  );

  update public.reservations
  set contract_content = v_contract
  where id = p_reservation_id
    and user_id = v_user;

  return jsonb_build_object(
    'ok', true,
    'reservationId', p_reservation_id::text,
    'contractLength', length(v_contract)
  );
end;
$$;

revoke all on function public.generate_rental_contract(bigint) from public;
grant execute on function public.generate_rental_contract(bigint) to authenticated;
