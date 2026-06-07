-- 반납 검수 면책금 (사고 예약)

alter table public.reservations
  add column if not exists deductible_charged boolean not null default false,
  add column if not exists deductible_amount integer not null default 0,
  add column if not exists deductible_charged_at timestamptz,
  add column if not exists deductible_waived boolean not null default false,
  add column if not exists deductible_waived_at timestamptz;

comment on column public.reservations.deductible_charged is
  '면책금 빌링키 자동결제 완료 여부';
comment on column public.reservations.deductible_amount is
  '청구된 면책금액(원)';
comment on column public.reservations.deductible_waived is
  '관리자 면책금 면제 처리 여부';

-- 관리자 면제 (재청구·중복 면제 방지)
create or replace function public.waive_reservation_deductible_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_res public.reservations%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = trim(p_reservation_id)
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if coalesce(v_res.is_accident, false) = false then
    raise exception 'not_accident_reservation';
  end if;

  if coalesce(v_res.deductible_charged, false) = true then
    raise exception 'deductible_already_charged';
  end if;

  if coalesce(v_res.deductible_waived, false) = true then
    raise exception 'deductible_already_waived';
  end if;

  update public.reservations
  set
    deductible_waived = true,
    deductible_waived_at = now(),
    updated_at = now()
  where id = v_res.id;

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_res.id::text,
    'deductibleWaived', true
  );
end;
$$;

revoke all on function public.waive_reservation_deductible_for_staff(text) from public;
grant execute on function public.waive_reservation_deductible_for_staff(text) to authenticated;
