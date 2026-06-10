-- 차량 점검/정비 이력 + vehicles 점검 상태 컬럼

alter table public.vehicles
  add column if not exists total_mileage integer not null default 0,
  add column if not exists is_under_maintenance boolean not null default false,
  add column if not exists maintenance_memo text;

comment on column public.vehicles.total_mileage is '누적 주행거리(km)';
comment on column public.vehicles.is_under_maintenance is '점검/정비 중 — 예약 불가';
comment on column public.vehicles.maintenance_memo is '점검중 사유 메모';

-- ── vehicle_maintenance ──────────────────────────────────────
create table if not exists public.vehicle_maintenance (
  id uuid primary key default gen_random_uuid(),
  vehicle_id bigint not null references public.vehicles(id) on delete cascade,
  complex_id uuid not null references public.complexes(id) on delete restrict,
  maintenance_type text not null
    check (maintenance_type in ('wash', 'repair', 'inspection', 'other')),
  description text,
  mileage integer,
  cost integer not null default 0 check (cost >= 0),
  performed_at timestamptz not null,
  staff_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists vehicle_maintenance_vehicle_id_idx
  on public.vehicle_maintenance (vehicle_id);

create index if not exists vehicle_maintenance_complex_id_idx
  on public.vehicle_maintenance (complex_id);

create index if not exists vehicle_maintenance_performed_at_idx
  on public.vehicle_maintenance (performed_at desc);

comment on table public.vehicle_maintenance is
  '차량 정비·세차·점검 이력 (단지 staff 조회/등록)';

alter table public.vehicle_maintenance enable row level security;
alter table public.vehicle_maintenance force row level security;

drop policy if exists vehicle_maintenance_staff_select on public.vehicle_maintenance;
create policy vehicle_maintenance_staff_select
on public.vehicle_maintenance
for select
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = vehicle_maintenance.complex_id
  )
);

drop policy if exists vehicle_maintenance_staff_insert on public.vehicle_maintenance;
create policy vehicle_maintenance_staff_insert
on public.vehicle_maintenance
for insert
to authenticated
with check (
  staff_id = auth.uid()
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id = vehicle_maintenance.complex_id
  )
  and exists (
    select 1
    from public.vehicles v
    where v.id = vehicle_maintenance.vehicle_id
      and v.complex_id = vehicle_maintenance.complex_id
  )
);
