-- 보험 만료 차량: 입주민 SELECT 제외 + 예약 차단 기준 정합성 (만료 당일 포함)

drop policy if exists "vehicles_resident_select_own_complex" on public.vehicles;

create policy "vehicles_resident_select_own_complex"
on public.vehicles
for select
to authenticated
using (
  exists (
    select 1
    from public.residents r
    where r.user_id = auth.uid()
      and r.approved = true
      and r.complex_id is not null
      and r.complex_id = vehicles.complex_id
  )
  and coalesce(vehicles.is_available, true) = true
  and coalesce(vehicles.is_under_maintenance, false) = false
  and (
    vehicles.insurance_expires_at is null
    or vehicles.insurance_expires_at >= (now() at time zone 'Asia/Seoul')::date
  )
);

create or replace function public.assert_vehicle_bookable(p_vehicle_id text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  select
    v.id,
    coalesce(v.is_available, true) as is_available,
    coalesce(v.is_under_maintenance, false) as is_under_maintenance,
    v.insurance_expires_at
  into v_row
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  if not found then
    raise exception 'vehicle_not_found';
  end if;

  if v_row.is_available is not true then
    raise exception 'vehicle_unavailable';
  end if;

  if v_row.is_under_maintenance is true then
    raise exception 'vehicle_under_maintenance';
  end if;

  if v_row.insurance_expires_at is not null
     and v_row.insurance_expires_at < (now() at time zone 'Asia/Seoul')::date then
    raise exception 'insurance_expired';
  end if;
end;
$$;

comment on function public.assert_vehicle_bookable(text) is
  '예약 가능 검사 — is_available, 점검중, 보험 만료(만료일 당일까지 유효)';
