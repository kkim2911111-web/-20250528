-- INSERT 시 type(레거시) 기준으로 category 자동 설정 (Edge Function 호환)
create or replace function public.notifications_sync_category_from_type()
returns trigger
language plpgsql
as $$
begin
  if new.category is null or new.category = 'user' then
    if coalesce(new.type, '') like 'admin%' then
      new.category := 'super_admin';
    elsif coalesce(new.type, '') like 'staff_%' then
      new.category := 'admin';
    elsif new.category is null then
      new.category := 'user';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_sync_category_from_type on public.notifications;
create trigger notifications_sync_category_from_type
  before insert on public.notifications
  for each row
  execute function public.notifications_sync_category_from_type();
