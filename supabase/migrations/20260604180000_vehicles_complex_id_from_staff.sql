-- vehicles.complex_id: 관리자(staff_users) 단지 자동 연결

alter table public.vehicles
  add column if not exists complex_id uuid references public.complexes(id) on delete restrict;

create or replace function public.set_vehicle_complex_from_staff()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
begin
  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = auth.uid()
  limit 1;

  if v_complex_id is null then
    return new;
  end if;

  if tg_op = 'INSERT' or new.complex_id is null then
    new.complex_id := v_complex_id;
  end if;

  return new;
end;
$$;

drop trigger if exists vehicles_set_complex_from_staff on public.vehicles;
create trigger vehicles_set_complex_from_staff
before insert or update on public.vehicles
for each row
execute function public.set_vehicle_complex_from_staff();
