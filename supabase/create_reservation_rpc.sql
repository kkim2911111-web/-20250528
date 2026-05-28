-- ============================================================
-- 예약 RPC (RLS/vehicle_id 타입 문제 우회 + 검증)
-- Supabase SQL Editor → Run
-- ============================================================

create or replace function public.create_reservation_for_me(
  p_vehicle_id text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_total_price integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_vehicle_id_type text;
  v_res_id text;
  v_sql text;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'invalid_time_range';
  end if;

  select r.complex_id into v_complex_id
  from public.residents r
  where r.user_id = v_user and r.approved = true;

  if v_complex_id is null then
    raise exception 'not_approved';
  end if;

  if not exists (
    select 1
    from public.vehicles v
    where v.id::text = p_vehicle_id
      and v.complex_id = v_complex_id
  ) then
    raise exception 'vehicle_not_in_complex';
  end if;

  -- 시간 겹침 (start_time/end_time 또는 start_at/end_at)
  if exists (
    select 1 from public.reservations r
    where r.vehicle_id::text = p_vehicle_id
      and coalesce(r.status, 'pending') in ('pending', 'confirmed')
      and coalesce(r.start_time, r.start_at) < p_end_time
      and coalesce(r.end_time, r.end_at) > p_start_time
  ) then
    raise exception 'time_overlap';
  end if;

  select c.data_type into v_vehicle_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'vehicles'
    and c.column_name = 'id';

  v_sql := format(
    $f$
    insert into public.reservations (
      user_id, vehicle_id, start_time, end_time, start_at, end_at, total_price, status
    ) values (
      $1, $2::%s, $3, $4, $5, $6, $7, 'pending'
    ) returning id::text
    $f$,
    v_vehicle_id_type
  );

  execute v_sql
    using v_user, p_vehicle_id, p_start_time, p_end_time,
          p_start_time, p_end_time, coalesce(p_total_price, 0)
    into v_res_id;

  return jsonb_build_object('id', v_res_id, 'status', 'pending');
end;
$$;

revoke all on function public.create_reservation_for_me(text, timestamptz, timestamptz, integer) from public;
grant execute on function public.create_reservation_for_me(text, timestamptz, timestamptz, integer) to authenticated;

-- RLS insert 정책도 id::text 비교로 보강
drop policy if exists "reservations_insert_own" on public.reservations;
create policy "reservations_insert_own"
on public.reservations for insert to authenticated
with check (
  user_id = auth.uid()
  and coalesce(status, 'pending') = 'pending'
  and exists (
    select 1 from public.residents r
    where r.user_id = auth.uid() and r.approved = true
  )
  and exists (
    select 1 from public.vehicles v
    join public.residents r on r.complex_id = v.complex_id
    where v.id::text = vehicle_id::text
      and r.user_id = auth.uid()
      and r.approved = true
  )
);
