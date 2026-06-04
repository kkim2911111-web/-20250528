-- payment_orders.reservation_id ↔ reservations.id (bigint/uuid 모두 text로 연결)

alter table public.payment_orders
  add column if not exists reservation_id text;

do $$
declare
  v_type text;
begin
  select c.data_type
  into v_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'payment_orders'
    and c.column_name = 'reservation_id';

  if v_type is null then
    return;
  end if;

  if v_type <> 'text' then
    execute format(
      'alter table public.payment_orders alter column reservation_id type text using reservation_id::text'
    );
  end if;
end;
$$;

create index if not exists payment_orders_reservation_id_idx
  on public.payment_orders (reservation_id)
  where reservation_id is not null;
