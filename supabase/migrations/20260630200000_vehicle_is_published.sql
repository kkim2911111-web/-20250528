-- 차량 노출 상태: is_published (노출/대기) 분리
-- 사전점검(2026-05-28): 보험 유효 + is_available=false 1대
--   id=28 카니발9 (운서역금강펜테리움) — 크론 잔재 가능성

-- ── 1) 컬럼 추가 ───────────────────────────────────────────
alter table public.vehicles
  add column if not exists is_published boolean not null default false;

comment on column public.vehicles.is_published is
  '입주민 노출 여부. false=대기(미노출), true=노출 의도';

create index if not exists vehicles_published_idx
  on public.vehicles (complex_id, is_published);

-- ── 2) 기존 데이터: is_available → is_published (2A) ────────
update public.vehicles
set is_published = coalesce(is_available, true);

-- ── 3) 크론 잔재 보정: 보험 유효 + is_available=false ───────
--    (의도적 대기와 동일 패턴이나, 갱신 후 is_available 미복구 차량 노출 복구)
update public.vehicles
set is_published = true
where coalesce(is_available, true) = false
  and coalesce(is_under_maintenance, false) = false
  and (
    insurance_expires_at is null
    or insurance_expires_at >= (now() at time zone 'Asia/Seoul')::date
  );

-- ── 4) 입주민 RLS: is_available 제거, is_published 적용 ─────
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
  and coalesce(vehicles.is_published, false) = true
  and coalesce(vehicles.is_under_maintenance, false) = false
  and (
    vehicles.insurance_expires_at is null
    or vehicles.insurance_expires_at >= (now() at time zone 'Asia/Seoul')::date
  )
);

-- ── 5) 예약 가능 검사: is_published 기준 ────────────────────
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
    coalesce(v.is_published, false) as is_published,
    coalesce(v.is_under_maintenance, false) as is_under_maintenance,
    v.insurance_expires_at
  into v_row
  from public.vehicles v
  where v.id::text = p_vehicle_id;

  if not found then
    raise exception 'vehicle_not_found';
  end if;

  if v_row.is_published is not true then
    raise exception 'vehicle_unpublished';
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
  '예약 가능 검사 — is_published, 점검중, 보험 만료(만료일 당일까지 유효)';
