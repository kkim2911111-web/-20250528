-- ============================================================
-- 대여 연장 (rental extension) — 스키마 + RPC
-- Supabase SQL Editor → Run
-- 선행: early_return_rental.sql (reservation_effective_end), rental_rpcs.sql
-- ============================================================

-- ---------------------------------------------------------------------------
-- 0) 긴급 상담 대표번호 (앱 팝업 → 전화 연결)
-- ---------------------------------------------------------------------------

create table if not exists public.app_support_contacts (
  key text primary key,
  value text not null,
  label text,
  updated_at timestamptz not null default now()
);

insert into public.app_support_contacts (key, value, label)
values ('emergency_phone', '010-4455-6676', '긴급 상담 대표번호')
on conflict (key) do update
set value = excluded.value,
    label = excluded.label,
    updated_at = now();

alter table public.app_support_contacts enable row level security;

drop policy if exists "app_support_contacts_select_authenticated"
  on public.app_support_contacts;
create policy "app_support_contacts_select_authenticated"
on public.app_support_contacts for select to authenticated
using (true);

create or replace function public.get_emergency_phone()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select value from public.app_support_contacts where key = 'emergency_phone' limit 1),
    '010-4455-6676'
  );
$$;

grant execute on function public.get_emergency_phone() to authenticated;

-- ---------------------------------------------------------------------------
-- 1) reservations — 연장 요약 컬럼
-- ---------------------------------------------------------------------------

alter table public.reservations
  add column if not exists original_end_at timestamptz;

comment on column public.reservations.original_end_at is
  '최초 예약 종료 시각 (연장 전). 첫 연장 시 end_at 스냅샷.';

alter table public.reservations
  add column if not exists extension_count integer not null default 0;

comment on column public.reservations.extension_count is
  '연장 횟수 (성공한 apply_rental_extension_for_me 누적)';

alter table public.reservations
  add column if not exists extension_price_total integer not null default 0;

comment on column public.reservations.extension_price_total is
  '연장으로 추가된 요금 합계(원). total_price 에 반영됨.';

alter table public.reservations
  drop constraint if exists reservations_extension_count_nonneg;

alter table public.reservations
  add constraint reservations_extension_count_nonneg
  check (extension_count >= 0);

alter table public.reservations
  drop constraint if exists reservations_extension_price_total_nonneg;

alter table public.reservations
  add constraint reservations_extension_price_total_nonneg
  check (extension_price_total >= 0);

-- 기존 데이터: original_end_at 백필
update public.reservations
set original_end_at = coalesce(original_end_at, end_at, end_time)
where original_end_at is null
  and coalesce(end_at, end_time) is not null;

-- ---------------------------------------------------------------------------
-- 2) reservation_extensions — 연장 이력
--    reservations.id = bigint 기준 (uuid DB는 p_reservation_id text + id::text 비교)
-- ---------------------------------------------------------------------------

drop table if exists public.reservation_extensions cascade;

create table public.reservation_extensions (
  id uuid primary key default gen_random_uuid(),
  reservation_id bigint not null references public.reservations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  vehicle_id text not null,
  extension_hours integer not null check (extension_hours > 0),
  previous_end_at timestamptz not null,
  new_end_at timestamptz not null,
  added_price integer not null default 0 check (added_price >= 0),
  extension_seq integer not null check (extension_seq > 0),
  created_at timestamptz not null default now(),
  constraint reservation_extensions_end_after_prev
    check (new_end_at > previous_end_at)
);

create index if not exists reservation_extensions_reservation_id_idx
  on public.reservation_extensions (reservation_id, created_at desc);

create index if not exists reservation_extensions_user_id_idx
  on public.reservation_extensions (user_id, created_at desc);

alter table public.reservation_extensions enable row level security;

drop policy if exists "reservation_extensions_select_own"
  on public.reservation_extensions;
create policy "reservation_extensions_select_own"
on public.reservation_extensions for select to authenticated
using (user_id = auth.uid());

-- insert는 RPC(security definer)에서만

-- ---------------------------------------------------------------------------
-- 3) emergency_consultation_requests — 긴급 상담 요청 로그
-- ---------------------------------------------------------------------------

drop table if exists public.emergency_consultation_requests cascade;

create table public.emergency_consultation_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reservation_id bigint references public.reservations(id) on delete set null,
  request_type text not null default 'extension_blocked'
    check (request_type in ('extension_blocked', 'extension_other', 'manual')),
  phone_number text not null default '010-4455-6676',
  reason_code text,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists emergency_consultation_requests_user_id_idx
  on public.emergency_consultation_requests (user_id, created_at desc);

create index if not exists emergency_consultation_requests_reservation_id_idx
  on public.emergency_consultation_requests (reservation_id)
  where reservation_id is not null;

alter table public.emergency_consultation_requests enable row level security;

drop policy if exists "emergency_consultation_requests_select_own"
  on public.emergency_consultation_requests;
create policy "emergency_consultation_requests_select_own"
on public.emergency_consultation_requests for select to authenticated
using (user_id = auth.uid());

drop policy if exists "emergency_consultation_requests_insert_own"
  on public.emergency_consultation_requests;
create policy "emergency_consultation_requests_insert_own"
on public.emergency_consultation_requests for insert to authenticated
with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4) 겹침 — 연장 구간 (current_end, new_end] 에 다른 예약 있는지
--    reservation_effective_end 는 early_return_rental.sql 에 정의됨
-- ---------------------------------------------------------------------------

drop function if exists public.check_rental_extension_for_me(uuid, integer);
drop function if exists public.apply_rental_extension_for_me(uuid, integer);
drop function if exists public.log_emergency_consultation_for_me(uuid, text, text, jsonb);

create or replace function public.reservation_blocks_extension_window(
  p_vehicle_id text,
  p_exclude_reservation_id bigint,
  p_window_start timestamptz,
  p_window_end timestamptz
)
returns table (
  blocking_reservation_id bigint,
  blocking_start_at timestamptz,
  blocking_end_at timestamptz,
  blocking_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    coalesce(r.start_at, r.start_time),
    public.reservation_effective_end(
      r.status,
      coalesce(r.end_at, r.end_time),
      r.actual_end_at,
      r.returned_at
    ),
    r.status
  from public.reservations r
  where r.vehicle_id::text = p_vehicle_id::text
    and r.id <> p_exclude_reservation_id
    and coalesce(r.status, 'pending') in ('confirmed', 'in_use')
    and coalesce(r.start_at, r.start_time) < p_window_end
    and public.reservation_effective_end(
          r.status,
          coalesce(r.end_at, r.end_time),
          r.actual_end_at,
          r.returned_at
        ) > p_window_start
  order by coalesce(r.start_at, r.start_time)
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 5) RPC — 연장 가능 여부 조회 (앱에서 연장 버튼 / 사전 검사)
--    조건: in_use, 종료 1시간 전~종료 시각 사이, 겹침 없음
-- ---------------------------------------------------------------------------

create or replace function public.check_rental_extension_for_me(
  p_reservation_id text,
  p_extension_hours integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_end timestamptz;
  v_new_end timestamptz;
  v_window_start timestamptz;
  v_block record;
  v_next_id text;
  v_next_start timestamptz;
  v_next_status text;
  v_price_per_hour integer;
  v_added_price integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_extension_hours is null or p_extension_hours < 1 then
    raise exception 'invalid_extension_hours';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
    and user_id = v_user;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_row.status <> 'in_use' then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'invalid_status',
      'message', '대여 중(in_use)인 예약만 연장할 수 있습니다.',
      'status', v_row.status,
      'emergencyPhone', public.get_emergency_phone()
    );
  end if;

  v_end := coalesce(v_row.end_at, v_row.end_time);
  if v_end is null then
    raise exception 'invalid_end_time';
  end if;

  v_window_start := v_end - interval '1 hour';

  if now() < v_window_start then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'too_early',
      'message', '대여 종료 1시간 전부터 연장 신청이 가능합니다.',
      'scheduledEndAt', v_end,
      'extensionWindowStartAt', v_window_start,
      'emergencyPhone', public.get_emergency_phone()
    );
  end if;

  if now() >= v_end then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'too_late',
      'message', '예약 종료 시각이 지나 연장할 수 없습니다.',
      'scheduledEndAt', v_end,
      'emergencyPhone', public.get_emergency_phone()
    );
  end if;

  v_new_end := v_end + (p_extension_hours || ' hours')::interval;

  -- 동일 차량 · 현재 예약 종료 시각 이후 confirmed/in_use 예약
  select
    r.id::text,
    coalesce(r.start_at, r.start_time),
    r.status
  into v_next_id, v_next_start, v_next_status
  from public.reservations r
  where r.vehicle_id = v_row.vehicle_id
    and r.id is distinct from v_row.id
    and r.status in ('confirmed', 'in_use')
    and coalesce(r.start_at, r.start_time) > v_end
  order by coalesce(r.start_at, r.start_time)
  limit 1;

  if v_next_id is not null then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'next_reservation_exists',
      'message', '다음 예약이 있어 연장할 수 없습니다.',
      'blockingReservationId', v_next_id,
      'blockingStartAt', v_next_start,
      'blockingStatus', v_next_status,
      'scheduledEndAt', v_end,
      'requestedNewEndAt', v_new_end,
      'extensionHours', p_extension_hours,
      'emergencyPhone', public.get_emergency_phone(),
      'showEmergencyConsultation', false
    );
  end if;

  -- 연장 구간 (current_end, new_end] 과 겹치는 다른 예약 (confirmed/in_use)
  select *
  into v_block
  from public.reservation_blocks_extension_window(
    v_row.vehicle_id::text,
    v_row.id,
    v_end,
    v_new_end
  )
  limit 1;

  if found then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'next_reservation_exists',
      'message', '다음 예약이 있어 연장할 수 없습니다.',
      'blockingReservationId', v_block.blocking_reservation_id::text,
      'blockingStartAt', v_block.blocking_start_at,
      'blockingEndAt', v_block.blocking_end_at,
      'blockingStatus', v_block.blocking_status,
      'scheduledEndAt', v_end,
      'requestedNewEndAt', v_new_end,
      'extensionHours', p_extension_hours,
      'emergencyPhone', public.get_emergency_phone(),
      'showEmergencyConsultation', false
    );
  end if;

  select coalesce(v.price_per_hour, 0)::integer
  into v_price_per_hour
  from public.vehicles v
  where v.id::text = v_row.vehicle_id::text;

  v_added_price := v_price_per_hour * p_extension_hours;

  return jsonb_build_object(
    'eligible', true,
    'reason', null,
    'reservationId', v_row.id::text,
    'extensionHours', p_extension_hours,
    'scheduledEndAt', v_end,
    'newEndAt', v_new_end,
    'addedPrice', v_added_price,
    'currentTotalPrice', v_row.total_price,
    'newTotalPrice', v_row.total_price + v_added_price,
    'extensionCount', v_row.extension_count,
    'emergencyPhone', public.get_emergency_phone()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) RPC — 연장 적용
-- ---------------------------------------------------------------------------

drop function if exists public.apply_rental_extension_for_me(text, integer);

create or replace function public.apply_rental_extension_for_me(
  p_reservation_id text,
  p_extension_hours integer default 1,
  p_payment_key text default null,
  p_payment_order_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id text := nullif(trim(p_reservation_id), '');
  v_row public.reservations%rowtype;
  v_check jsonb;
  v_end timestamptz;
  v_new_end timestamptz;
  v_added_price integer;
  v_seq integer;
  v_now timestamptz := now();
  v_payment_key text := nullif(trim(p_payment_key), '');
  v_order_id text := nullif(trim(p_payment_order_id), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_id is null then
    raise exception 'invalid_reservation_id';
  end if;

  v_check := public.check_rental_extension_for_me(v_id, p_extension_hours);
  if coalesce((v_check->>'eligible')::boolean, false) is not true then
    raise exception '%', coalesce(v_check->>'reason', 'extension_not_eligible');
  end if;

  v_added_price := coalesce((v_check->>'addedPrice')::integer, 0);

  if v_added_price > 0 and v_payment_key is null then
    raise exception 'payment_required';
  end if;

  select *
  into v_row
  from public.reservations
  where id::text = v_id
    and user_id = v_user
  for update;

  v_end := coalesce(v_row.end_at, v_row.end_time);
  v_new_end := v_end + (p_extension_hours || ' hours')::interval;
  v_seq := v_row.extension_count + 1;

  update public.reservations
  set
    original_end_at = coalesce(original_end_at, v_end),
    end_at = v_new_end,
    end_time = v_new_end,
    extension_count = v_seq,
    extension_price_total = extension_price_total + v_added_price,
    total_price = total_price + v_added_price,
    updated_at = v_now
  where id::text = v_id;

  insert into public.reservation_extensions (
    reservation_id,
    user_id,
    vehicle_id,
    extension_hours,
    previous_end_at,
    new_end_at,
    added_price,
    extension_seq,
    payment_order_id,
    payment_key,
    payment_status
  ) values (
    v_row.id,
    v_user,
    v_row.vehicle_id::text,
    p_extension_hours,
    v_end,
    v_new_end,
    v_added_price,
    v_seq,
    v_order_id,
    v_payment_key,
    case when v_payment_key is not null then 'paid' else null end
  );

  return jsonb_build_object(
    'ok', true,
    'reservationId', v_row.id::text,
    'extensionHours', p_extension_hours,
    'previousEndAt', v_end,
    'newEndAt', v_new_end,
    'addedPrice', v_added_price,
    'extensionCount', v_seq,
    'newTotalPrice', v_row.total_price + v_added_price,
    'paymentKey', v_payment_key,
    'paymentOrderId', v_order_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7) RPC — 긴급 상담 요청 로그 (연장 불가 → 전화 연결 전)
-- ---------------------------------------------------------------------------

create or replace function public.log_emergency_consultation_for_me(
  p_reservation_id text default null,
  p_request_type text default 'extension_blocked',
  p_reason_code text default null,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_phone text := public.get_emergency_phone();
  v_id uuid;
  v_reservation_id bigint;
  v_res_id_text text := nullif(trim(p_reservation_id), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_request_type not in ('extension_blocked', 'extension_other', 'manual') then
    raise exception 'invalid_request_type';
  end if;

  if v_res_id_text is not null then
    select r.id
    into v_reservation_id
    from public.reservations r
    where r.id::text = v_res_id_text
      and r.user_id = v_user;

    if not found then
      raise exception 'reservation_not_found';
    end if;
  end if;

  insert into public.emergency_consultation_requests (
    user_id,
    reservation_id,
    request_type,
    phone_number,
    reason_code,
    context
  ) values (
    v_user,
    v_reservation_id,
    p_request_type,
    v_phone,
    p_reason_code,
    coalesce(p_context, '{}'::jsonb)
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'requestId', v_id::text,
    'phoneNumber', v_phone,
    'requestType', p_request_type
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8) 권한
-- ---------------------------------------------------------------------------

revoke all on function public.check_rental_extension_for_me(text, integer) from public;
grant execute on function public.check_rental_extension_for_me(text, integer) to authenticated;

revoke all on function public.apply_rental_extension_for_me(text, integer, text, text) from public;
grant execute on function public.apply_rental_extension_for_me(text, integer, text, text) to authenticated;

revoke all on function public.log_emergency_consultation_for_me(text, text, text, jsonb) from public;
grant execute on function public.log_emergency_consultation_for_me(text, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 확인 쿼리
-- ---------------------------------------------------------------------------
-- select * from public.app_support_contacts;
-- select public.get_emergency_phone();
-- select public.check_rental_extension_for_me('123', 1);
