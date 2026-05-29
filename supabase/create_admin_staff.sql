-- ============================================================
-- 관리자(지점) 계정 + 차량 확장 컬럼 + RLS
-- Supabase SQL Editor → Run
-- ============================================================

alter table public.complexes add column if not exists admin_invite_code text;

update public.complexes
set admin_invite_code = 'ADMIN-DANJI2026'
where invite_code = 'DANJI2026'
  and admin_invite_code is null;

create unique index if not exists complexes_admin_invite_code_uniq
  on public.complexes (admin_invite_code)
  where admin_invite_code is not null;

-- 지점 관리자
create table if not exists public.staff_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  complex_id uuid not null references public.complexes(id) on delete restrict,
  display_name text not null,
  role text not null default 'branch_admin'
    check (role in ('branch_admin')),
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.staff_users add column if not exists approved boolean not null default false;

create index if not exists staff_users_complex_id_idx
  on public.staff_users (complex_id);

drop trigger if exists staff_users_set_updated_at on public.staff_users;
create trigger staff_users_set_updated_at
before update on public.staff_users
for each row execute function public.set_updated_at();

alter table public.staff_users enable row level security;

drop policy if exists "staff_select_own" on public.staff_users;
create policy "staff_select_own"
on public.staff_users for select to authenticated
using (user_id = auth.uid());

-- 본인 정보 수정 (approved 는 본인이 변경 불가)
drop policy if exists "staff_update_own" on public.staff_users;
create policy "staff_update_own"
on public.staff_users for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and approved = (
    select s.approved from public.staff_users s where s.user_id = auth.uid()
  )
);

-- vehicles 확장
alter table public.vehicles add column if not exists fuel_type text;
alter table public.vehicles add column if not exists insurance_company text;
alter table public.vehicles add column if not exists insurance_policy_number text;
alter table public.vehicles add column if not exists insurance_expires_at date;
alter table public.vehicles add column if not exists last_latitude double precision;
alter table public.vehicles add column if not exists last_longitude double precision;
alter table public.vehicles add column if not exists last_location_updated_at timestamptz;

-- 관리자 차량 CRUD (승인된 관리자만)
drop policy if exists "vehicles_staff_manage" on public.vehicles;
create policy "vehicles_staff_manage"
on public.vehicles for all to authenticated
using (
  exists (
    select 1 from public.staff_users s
    where s.user_id = auth.uid()
      and s.complex_id = vehicles.complex_id
      and s.approved = true
  )
)
with check (
  exists (
    select 1 from public.staff_users s
    where s.user_id = auth.uid()
      and s.complex_id = vehicles.complex_id
      and s.approved = true
  )
);

-- 관리자 — 지점 예약 조회 (승인된 관리자만)
drop policy if exists "reservations_staff_select_complex" on public.reservations;
create policy "reservations_staff_select_complex"
on public.reservations for select to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    join public.vehicles v on v.complex_id = s.complex_id
    where s.user_id = auth.uid()
      and s.approved = true
      and v.id = reservations.vehicle_id
  )
);

drop policy if exists "reservations_staff_update_complex" on public.reservations;
create policy "reservations_staff_update_complex"
on public.reservations for update to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    join public.vehicles v on v.complex_id = s.complex_id
    where s.user_id = auth.uid()
      and s.approved = true
      and v.id = reservations.vehicle_id
  )
)
with check (
  exists (
    select 1
    from public.staff_users s
    join public.vehicles v on v.complex_id = s.complex_id
    where s.user_id = auth.uid()
      and s.approved = true
      and v.id = reservations.vehicle_id
  )
);

-- 관리자 회원가입 RPC
create or replace function public.register_staff_for_me(
  p_display_name text,
  p_admin_invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_complex_name text;
  v_code text := nullif(trim(p_admin_invite_code), '');
  v_name text := nullif(trim(p_display_name), '');
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if v_name is null then
    raise exception 'invalid_display_name';
  end if;

  if v_code is null then
    raise exception 'invalid_admin_invite_code';
  end if;

  if exists (select 1 from public.staff_users where user_id = v_user) then
    raise exception 'staff_already_registered';
  end if;

  select c.id, c.name
  into v_complex_id, v_complex_name
  from public.complexes c
  where upper(c.admin_invite_code) = upper(v_code)
  limit 1;

  if v_complex_id is null then
    raise exception 'admin_invite_not_found';
  end if;

  insert into public.staff_users (user_id, complex_id, display_name, approved)
  values (v_user, v_complex_id, v_name, false);

  return jsonb_build_object(
    'userId', v_user,
    'complexId', v_complex_id,
    'complexName', v_complex_name,
    'displayName', v_name,
    'approved', false
  );
end;
$$;

revoke all on function public.register_staff_for_me(text, text) from public;
grant execute on function public.register_staff_for_me(text, text) to authenticated;

-- 반납 검수 완료
create or replace function public.complete_return_inspection_for_staff(
  p_reservation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_res public.reservations%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select r.*
  into v_res
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.staff_users s on s.complex_id = v.complex_id
    and s.user_id = v_user
    and s.approved = true
  where r.id::text = p_reservation_id
  for update;

  if not found then
    raise exception 'reservation_not_found';
  end if;

  if v_res.status <> 'returned' then
    raise exception 'invalid_status';
  end if;

  update public.reservations
  set status = 'completed'
  where id = v_res.id;

  return jsonb_build_object('reservationId', p_reservation_id, 'status', 'completed');
end;
$$;

revoke all on function public.complete_return_inspection_for_staff(text) from public;
grant execute on function public.complete_return_inspection_for_staff(text) to authenticated;
