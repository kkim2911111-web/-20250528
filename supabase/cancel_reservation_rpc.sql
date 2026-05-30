-- ============================================================
-- 예약 취소 = 행 삭제 (cancelled 상태 제약 없이 목록에서 즉시 제거)
-- Supabase SQL Editor → Run
-- ============================================================

alter table public.reservations
  drop constraint if exists reservations_status_check;

alter table public.reservations
  add constraint reservations_status_check
  check (status in (
    'pending', 'confirmed', 'in_use', 'returned', 'completed', 'cancelled'
  ));

drop function if exists public.cancel_reservation_for_me(uuid, uuid);

create or replace function public.cancel_reservation_for_me(
  p_reservation_id text,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_row public.reservations%rowtype;
  v_start timestamptz;
  v_id text := nullif(trim(p_reservation_id), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations r
  where r.id::text = v_id
    and r.user_id = v_user
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status not in ('confirmed', 'pending') then
    raise exception 'invalid_status';
  end if;

  v_start := coalesce(v_row.start_at, v_row.start_time);
  if v_start is null then
    raise exception 'invalid_start_time';
  end if;

  if v_start <= now() + interval '1 hour' then
    raise exception 'cancel_too_late';
  end if;

  delete from public.reservations
  where id::text = v_id
    and user_id = v_user;

  if v_row.order_id is not null then
    update public.payment_orders
    set status = 'cancelled', updated_at = now()
    where order_id = v_row.order_id
      and user_id = v_user;
  end if;

  return jsonb_build_object(
    'reservationId', v_id,
    'deleted', true,
    'orderId', v_row.order_id,
    'paymentKey', v_row.payment_key,
    'totalPrice', v_row.total_price
  );
end;
$$;

revoke all on function public.cancel_reservation_for_me(text, uuid) from public;
grant execute on function public.cancel_reservation_for_me(text, uuid) to authenticated;
grant execute on function public.cancel_reservation_for_me(text, uuid) to service_role;

-- RPC 미적용/오류 시 클라이언트 DELETE fallback (대여 1시간 전 confirmed/pending)
drop policy if exists "reservations_delete_own_pending" on public.reservations;
drop policy if exists "reservations_delete_own_cancellable" on public.reservations;
create policy "reservations_delete_own_cancellable"
on public.reservations
for delete to authenticated
using (
  user_id = auth.uid()
  and status in ('pending', 'confirmed')
  and coalesce(start_at, start_time) > now() + interval '1 hour'
);
