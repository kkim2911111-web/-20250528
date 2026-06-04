-- vehicles: 임대인(업체명)
alter table public.vehicles
  add column if not exists owner_name text;

comment on column public.vehicles.owner_name is '임대인(업체명)';
