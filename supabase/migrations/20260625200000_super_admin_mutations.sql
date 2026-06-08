-- ============================================================
-- 최고관리자 — 변경 RPC + 시스템 테이블
-- ============================================================

-- ── 스키마 확장 ─────────────────────────────────────────────
alter table public.user_profiles
  add column if not exists is_blacklisted boolean not null default false;

comment on column public.user_profiles.is_blacklisted is
  '블랙리스트 — 예약·서비스 제한 (최고관리자 설정)';

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (key, value)
values (
  'maintenance_mode',
  jsonb_build_object('enabled', false, 'message', '점검 중입니다. 잠시 후 다시 이용해주세요.')
)
on conflict (key) do nothing;

create table if not exists public.complex_settlements (
  id uuid primary key default gen_random_uuid(),
  complex_id uuid not null references public.complexes(id) on delete cascade,
  period_year integer not null,
  period_month integer not null check (period_month between 1 and 12),
  settled_at timestamptz not null default now(),
  settled_by uuid references auth.users(id) on delete set null,
  note text,
  unique (complex_id, period_year, period_month)
);

create index if not exists complex_settlements_period_idx
  on public.complex_settlements (period_year, period_month);

alter table public.app_settings enable row level security;
alter table public.complex_settlements enable row level security;
-- RLS: 일반 사용자 접근 없음 (RPC security definer만 사용)

-- ── 조회 보조 RPC ───────────────────────────────────────────
drop function if exists public.get_super_admin_coupons();

create or replace function public.get_super_admin_coupons()
returns table (
  coupon_id text,
  title text,
  description text,
  discount_amount integer,
  min_payment_amount integer,
  issued_count bigint,
  used_count bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();
  return query
  select
    c.id::text,
    coalesce(c.title, c.name, '쿠폰')::text,
    c.description,
    coalesce(c.discount_amount, 0)::integer,
    coalesce(c.min_payment_amount, 0)::integer,
    (
      select count(*)::bigint from public.user_coupons uc where uc.coupon_id = c.id
    ),
    (
      select count(*)::bigint
      from public.user_coupons uc
      where uc.coupon_id = c.id
        and (uc.is_used = true or uc.used_at is not null or uc.status = 'used')
    ),
    c.created_at
  from public.coupons c
  order by c.created_at desc nulls last;
end;
$$;

drop function if exists public.get_super_admin_banners();

create or replace function public.get_super_admin_banners()
returns table (
  banner_id bigint,
  sub_title text,
  main_title text,
  description text,
  is_active boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();
  return query
  select b.id, b.sub_title, b.main_title, b.description, b.is_active, b.created_at
  from public.banners b
  order by b.id asc;
end;
$$;

create or replace function public.get_super_admin_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_maintenance jsonb;
begin
  perform public.assert_is_super_admin();
  select s.value into v_maintenance from public.app_settings s where s.key = 'maintenance_mode';
  return jsonb_build_object(
    'maintenance', coalesce(v_maintenance, jsonb_build_object('enabled', false, 'message', ''))
  );
end;
$$;

-- 정산 RPC에 settled 여부 추가 (재정의)
drop function if exists public.get_super_admin_revenue(integer, integer);

create function public.get_super_admin_revenue(
  p_year integer default null,
  p_month integer default null
)
returns table (
  complex_id uuid,
  complex_name text,
  period_year integer,
  period_month integer,
  reservation_count bigint,
  gross_revenue bigint,
  paid_order_count bigint,
  paid_order_amount bigint,
  extension_revenue bigint,
  is_settled boolean,
  settled_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
begin
  perform public.assert_is_super_admin();
  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'Asia/Seoul');
  v_period_end := v_period_start + interval '1 month';

  return query
  with complexes_all as (select c.id, c.name from public.complexes c),
  res_sales as (
    select v.complex_id, count(*)::bigint as reservation_count,
      coalesce(sum(r.total_price), 0)::bigint as gross_revenue
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where r.status in ('confirmed','in_use','returning','returned','completed')
      and coalesce(r.start_at, r.start_time) >= v_period_start
      and coalesce(r.start_at, r.start_time) < v_period_end
    group by v.complex_id
  ),
  paid_orders as (
    select v.complex_id, count(*)::bigint as paid_order_count,
      coalesce(sum(po.total_price), 0)::bigint as paid_order_amount
    from public.payment_orders po
    join public.vehicles v on v.id::text = po.vehicle_id::text
    where po.status = 'paid'
      and po.created_at >= v_period_start and po.created_at < v_period_end
    group by v.complex_id
  ),
  extensions as (
    select v.complex_id, coalesce(sum(re.added_price), 0)::bigint as extension_revenue
    from public.reservation_extensions re
    join public.reservations r on r.id::text = re.reservation_id::text
    join public.vehicles v on v.id = r.vehicle_id
    where re.created_at >= v_period_start and re.created_at < v_period_end
    group by v.complex_id
  )
  select ca.id, ca.name, v_year, v_month,
    coalesce(rs.reservation_count, 0), coalesce(rs.gross_revenue, 0),
    coalesce(po.paid_order_count, 0), coalesce(po.paid_order_amount, 0),
    coalesce(ex.extension_revenue, 0),
    (cs.id is not null), cs.settled_at
  from complexes_all ca
  left join res_sales rs on rs.complex_id = ca.id
  left join paid_orders po on po.complex_id = ca.id
  left join extensions ex on ex.complex_id = ca.id
  left join public.complex_settlements cs
    on cs.complex_id = ca.id and cs.period_year = v_year and cs.period_month = v_month
  order by coalesce(rs.gross_revenue, 0) desc, ca.name asc nulls last;
end;
$$;

-- ── 변경 RPC ────────────────────────────────────────────────
create or replace function public.upsert_super_admin_complex(
  p_complex_id uuid default null,
  p_name text default null,
  p_invite_code text default null,
  p_admin_invite_code text default null,
  p_business_name text default null,
  p_business_phone text default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.assert_is_super_admin();
  if p_complex_id is null then
    if nullif(trim(p_name), '') is null then raise exception 'name_required'; end if;
    insert into public.complexes (name, invite_code, admin_invite_code, business_name, business_phone)
    values (trim(p_name), nullif(trim(p_invite_code), ''), nullif(trim(p_admin_invite_code), ''),
      nullif(trim(p_business_name), ''), nullif(trim(p_business_phone), ''))
    returning id into v_id;
    return v_id;
  end if;
  update public.complexes set
    name = coalesce(nullif(trim(p_name), ''), name),
    invite_code = coalesce(nullif(trim(p_invite_code), ''), invite_code),
    admin_invite_code = coalesce(nullif(trim(p_admin_invite_code), ''), admin_invite_code),
    business_name = coalesce(nullif(trim(p_business_name), ''), business_name),
    business_phone = coalesce(nullif(trim(p_business_phone), ''), business_phone)
  where id = p_complex_id;
  if not found then raise exception 'complex_not_found'; end if;
  return p_complex_id;
end; $$;

create or replace function public.delete_super_admin_complex(p_complex_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  delete from public.complexes where id = p_complex_id;
  if not found then raise exception 'complex_not_found'; end if;
end; $$;

create or replace function public.upsert_super_admin_vehicle(
  p_vehicle_id text default null,
  p_complex_id uuid default null,
  p_model_name text default null,
  p_vehicle_type text default 'SUV',
  p_fuel_type text default null,
  p_price_per_hour integer default 0,
  p_car_number text default null,
  p_is_available boolean default true
)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_new_id text;
begin
  perform public.assert_is_super_admin();
  if p_vehicle_id is null then
    if p_complex_id is null then raise exception 'complex_id_required'; end if;
    insert into public.vehicles (complex_id, model_name, vehicle_type, fuel_type, price_per_hour, car_number, is_available)
    values (p_complex_id, coalesce(nullif(trim(p_model_name), ''), '차량'), coalesce(p_vehicle_type, 'SUV'),
      nullif(trim(p_fuel_type), ''), greatest(coalesce(p_price_per_hour, 0), 0),
      nullif(trim(p_car_number), ''), coalesce(p_is_available, true))
    returning id into v_id;
    return v_id::text;
  end if;
  update public.vehicles set
    complex_id = coalesce(p_complex_id, complex_id),
    model_name = coalesce(nullif(trim(p_model_name), ''), model_name),
    vehicle_type = coalesce(nullif(trim(p_vehicle_type), ''), vehicle_type),
    fuel_type = coalesce(nullif(trim(p_fuel_type), ''), fuel_type),
    price_per_hour = greatest(coalesce(p_price_per_hour, price_per_hour), 0),
    car_number = coalesce(nullif(trim(p_car_number), ''), car_number),
    is_available = coalesce(p_is_available, is_available),
    updated_at = now()
  where id::text = trim(p_vehicle_id);
  if not found then raise exception 'vehicle_not_found'; end if;
  return trim(p_vehicle_id);
end; $$;

create or replace function public.delete_super_admin_vehicle(p_vehicle_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  delete from public.vehicles where id::text = trim(p_vehicle_id);
  if not found then raise exception 'vehicle_not_found'; end if;
end; $$;

create or replace function public.set_super_admin_staff_approved(p_user_id uuid, p_approved boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  update public.staff_users set approved = p_approved, updated_at = now() where user_id = p_user_id;
  if not found then raise exception 'staff_not_found'; end if;
end; $$;

create or replace function public.set_super_admin_staff_complex(p_user_id uuid, p_complex_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  update public.staff_users set complex_id = p_complex_id, updated_at = now() where user_id = p_user_id;
  if not found then raise exception 'staff_not_found'; end if;
end; $$;

create or replace function public.delete_super_admin_staff(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  delete from public.staff_users where user_id = p_user_id;
  if not found then raise exception 'staff_not_found'; end if;
end; $$;

create or replace function public.set_super_admin_resident_approved(p_user_id uuid, p_approved boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  update public.residents set approved = p_approved, updated_at = now() where user_id = p_user_id;
  if not found then raise exception 'resident_not_found'; end if;
end; $$;

create or replace function public.delete_super_admin_resident(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  delete from public.residents where user_id = p_user_id;
  if not found then raise exception 'resident_not_found'; end if;
end; $$;

create or replace function public.set_super_admin_user_blacklist(p_user_id uuid, p_blacklisted boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  update public.user_profiles set is_blacklisted = p_blacklisted, updated_at = now() where user_id = p_user_id;
  if not found then raise exception 'profile_not_found'; end if;
end; $$;

create or replace function public.force_super_admin_license_approved(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  update public.user_profiles set
    license_verified = true, license_status = 'approved', license_rejection_reason = null,
    license_verified_at = now(), license_verified_by = auth.uid(), updated_at = now()
  where user_id = p_user_id;
  if not found then raise exception 'profile_not_found'; end if;
end; $$;

create or replace function public.upsert_super_admin_coupon(
  p_coupon_id text default null,
  p_title text default null,
  p_description text default null,
  p_discount_amount integer default 0,
  p_min_payment_amount integer default 0
)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.assert_is_super_admin();
  if p_coupon_id is null then
    insert into public.coupons (title, description, discount_amount, min_payment_amount)
    values (coalesce(nullif(trim(p_title), ''), '쿠폰'), nullif(trim(p_description), ''),
      greatest(coalesce(p_discount_amount, 0), 0), greatest(coalesce(p_min_payment_amount, 0), 0))
    returning id into v_id;
    return v_id::text;
  end if;
  update public.coupons set
    title = coalesce(nullif(trim(p_title), ''), title),
    description = coalesce(nullif(trim(p_description), ''), description),
    discount_amount = greatest(coalesce(p_discount_amount, discount_amount), 0),
    min_payment_amount = greatest(coalesce(p_min_payment_amount, min_payment_amount), 0)
  where id::text = trim(p_coupon_id);
  if not found then raise exception 'coupon_not_found'; end if;
  return trim(p_coupon_id);
end; $$;

create or replace function public.delete_super_admin_coupon(p_coupon_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  delete from public.coupons where id::text = trim(p_coupon_id);
  if not found then raise exception 'coupon_not_found'; end if;
end; $$;

create or replace function public.issue_super_admin_coupon(p_user_id uuid, p_coupon_id text, p_expires_at timestamptz default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.assert_is_super_admin();
  insert into public.user_coupons (user_id, coupon_id, expires_at, is_used)
  values (p_user_id, trim(p_coupon_id)::uuid, p_expires_at, false)
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.force_super_admin_cancel_reservation(p_reservation_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res public.reservations%rowtype;
begin
  perform public.assert_is_super_admin();
  select * into v_res from public.reservations where id::text = trim(p_reservation_id) for update;
  if not found then raise exception 'reservation_not_found'; end if;
  if v_res.status in ('cancelled', 'completed') then raise exception 'invalid_status'; end if;
  update public.reservations set status = 'cancelled', updated_at = now() where id = v_res.id;
  return jsonb_build_object('ok', true, 'reservationId', v_res.id::text);
end; $$;

create or replace function public.force_super_admin_complete_reservation(p_reservation_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res public.reservations%rowtype;
begin
  perform public.assert_is_super_admin();
  select * into v_res from public.reservations where id::text = trim(p_reservation_id) for update;
  if not found then raise exception 'reservation_not_found'; end if;
  update public.reservations set status = 'completed', updated_at = now() where id = v_res.id;
  return jsonb_build_object('ok', true, 'reservationId', v_res.id::text);
end; $$;

create or replace function public.mark_super_admin_settlement(
  p_complex_id uuid, p_year integer, p_month integer, p_note text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  insert into public.complex_settlements (complex_id, period_year, period_month, settled_by, note)
  values (p_complex_id, p_year, p_month, auth.uid(), nullif(trim(p_note), ''))
  on conflict (complex_id, period_year, period_month) do update set
    settled_at = now(), settled_by = auth.uid(), note = excluded.note;
end; $$;

create or replace function public.upsert_super_admin_banner(
  p_banner_id bigint default null,
  p_sub_title text default '',
  p_main_title text default '',
  p_description text default '',
  p_is_active boolean default true
)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public.assert_is_super_admin();
  if p_banner_id is null then
    insert into public.banners (sub_title, main_title, description, is_active)
    values (coalesce(p_sub_title, ''), coalesce(p_main_title, ''), coalesce(p_description, ''), coalesce(p_is_active, true))
    returning id into v_id;
    return v_id;
  end if;
  update public.banners set sub_title = coalesce(p_sub_title, sub_title), main_title = coalesce(p_main_title, main_title),
    description = coalesce(p_description, description), is_active = coalesce(p_is_active, is_active)
  where id = p_banner_id;
  if not found then raise exception 'banner_not_found'; end if;
  return p_banner_id;
end; $$;

create or replace function public.delete_super_admin_banner(p_banner_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  delete from public.banners where id = p_banner_id;
  if not found then raise exception 'banner_not_found'; end if;
end; $$;

create or replace function public.upsert_super_admin_notice(
  p_notice_id uuid default null,
  p_complex_id uuid default null,
  p_title text default null,
  p_content text default '',
  p_is_active boolean default true
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.assert_is_super_admin();
  if p_notice_id is null then
    insert into public.notices (complex_id, title, content, is_active)
    values (p_complex_id, coalesce(nullif(trim(p_title), ''), '공지'), coalesce(p_content, ''), coalesce(p_is_active, true))
    returning id into v_id;
    return v_id;
  end if;
  update public.notices set complex_id = p_complex_id,
    title = coalesce(nullif(trim(p_title), ''), title), content = coalesce(p_content, content),
    is_active = coalesce(p_is_active, is_active)
  where id = p_notice_id;
  if not found then raise exception 'notice_not_found'; end if;
  return p_notice_id;
end; $$;

create or replace function public.delete_super_admin_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  delete from public.notices where id = p_notice_id;
  if not found then raise exception 'notice_not_found'; end if;
end; $$;

create or replace function public.set_super_admin_maintenance(
  p_enabled boolean, p_message text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_is_super_admin();
  insert into public.app_settings (key, value, updated_at)
  values ('maintenance_mode', jsonb_build_object(
    'enabled', coalesce(p_enabled, false),
    'message', coalesce(nullif(trim(p_message), ''), '점검 중입니다. 잠시 후 다시 이용해주세요.')
  ), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end; $$;

-- 권한
revoke all on function public.get_super_admin_coupons() from public;
revoke all on function public.get_super_admin_banners() from public;
revoke all on function public.get_super_admin_settings() from public;
grant execute on function public.get_super_admin_coupons() to authenticated;
grant execute on function public.get_super_admin_banners() to authenticated;
grant execute on function public.get_super_admin_settings() to authenticated;
grant execute on function public.get_super_admin_revenue(integer, integer) to authenticated;

revoke all on function public.upsert_super_admin_complex(uuid,text,text,text,text,text) from public;
revoke all on function public.delete_super_admin_complex(uuid) from public;
revoke all on function public.upsert_super_admin_vehicle(text,uuid,text,text,text,integer,text,boolean) from public;
revoke all on function public.delete_super_admin_vehicle(text) from public;
revoke all on function public.set_super_admin_staff_approved(uuid,boolean) from public;
revoke all on function public.set_super_admin_staff_complex(uuid,uuid) from public;
revoke all on function public.delete_super_admin_staff(uuid) from public;
revoke all on function public.set_super_admin_resident_approved(uuid,boolean) from public;
revoke all on function public.delete_super_admin_resident(uuid) from public;
revoke all on function public.set_super_admin_user_blacklist(uuid,boolean) from public;
revoke all on function public.force_super_admin_license_approved(uuid) from public;
revoke all on function public.upsert_super_admin_coupon(text,text,text,integer,integer) from public;
revoke all on function public.delete_super_admin_coupon(text) from public;
revoke all on function public.issue_super_admin_coupon(uuid,text,timestamptz) from public;
revoke all on function public.force_super_admin_cancel_reservation(text) from public;
revoke all on function public.force_super_admin_complete_reservation(text) from public;
revoke all on function public.mark_super_admin_settlement(uuid,integer,integer,text) from public;
revoke all on function public.upsert_super_admin_banner(bigint,text,text,text,boolean) from public;
revoke all on function public.delete_super_admin_banner(bigint) from public;
revoke all on function public.upsert_super_admin_notice(uuid,uuid,text,text,boolean) from public;
revoke all on function public.delete_super_admin_notice(uuid) from public;
revoke all on function public.set_super_admin_maintenance(boolean,text) from public;

grant execute on function public.upsert_super_admin_complex(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.delete_super_admin_complex(uuid) to authenticated;
grant execute on function public.upsert_super_admin_vehicle(text,uuid,text,text,text,integer,text,boolean) to authenticated;
grant execute on function public.delete_super_admin_vehicle(text) to authenticated;
grant execute on function public.set_super_admin_staff_approved(uuid,boolean) to authenticated;
grant execute on function public.set_super_admin_staff_complex(uuid,uuid) to authenticated;
grant execute on function public.delete_super_admin_staff(uuid) to authenticated;
grant execute on function public.set_super_admin_resident_approved(uuid,boolean) to authenticated;
grant execute on function public.delete_super_admin_resident(uuid) to authenticated;
grant execute on function public.set_super_admin_user_blacklist(uuid,boolean) to authenticated;
grant execute on function public.force_super_admin_license_approved(uuid) to authenticated;
grant execute on function public.upsert_super_admin_coupon(text,text,text,integer,integer) to authenticated;
grant execute on function public.delete_super_admin_coupon(text) to authenticated;
grant execute on function public.issue_super_admin_coupon(uuid,text,timestamptz) to authenticated;
grant execute on function public.force_super_admin_cancel_reservation(text) to authenticated;
grant execute on function public.force_super_admin_complete_reservation(text) to authenticated;
grant execute on function public.mark_super_admin_settlement(uuid,integer,integer,text) to authenticated;
grant execute on function public.upsert_super_admin_banner(bigint,text,text,text,boolean) to authenticated;
grant execute on function public.delete_super_admin_banner(bigint) to authenticated;
grant execute on function public.upsert_super_admin_notice(uuid,uuid,text,text,boolean) to authenticated;
grant execute on function public.delete_super_admin_notice(uuid) to authenticated;
grant execute on function public.set_super_admin_maintenance(boolean,text) to authenticated;

-- 최고관리자 계정 부여 (이미 있으면 스킵)
update public.user_profiles up
set is_super_admin = true, updated_at = now()
from auth.users au
where au.id = up.user_id
  and lower(au.email) = lower('kkim000@naver.com')
  and up.is_super_admin is distinct from true;
