-- vehicles.updated_at 누락 보정
-- upsert_super_admin_vehicle · delete_super_admin_vehicle · 강제취소 등에서 참조

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

alter table public.vehicles
  add column if not exists updated_at timestamptz not null default now();

update public.vehicles
set updated_at = coalesce(created_at, now())
where updated_at is null;

drop trigger if exists vehicles_set_updated_at on public.vehicles;
create trigger vehicles_set_updated_at
before update on public.vehicles
for each row execute function public.set_updated_at();

comment on column public.vehicles.updated_at is '차량 정보 최종 수정 시각';
