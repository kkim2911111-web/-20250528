-- 예약번호 체계: 단지 short_code + reservation_number (KG-2606-001)

-- ── 1) complexes.short_code ─────────────────────────────────────
alter table public.complexes
  add column if not exists short_code text;

create unique index if not exists complexes_short_code_unique_idx
  on public.complexes (short_code)
  where short_code is not null and trim(short_code) <> '';

update public.complexes set short_code = 'KG' where name = '운서역금강펜테리움';
update public.complexes set short_code = 'BD' where name = '반도유보라';
update public.complexes set short_code = 'SK' where name = '운서 SK뷰2';
update public.complexes set short_code = 'YS' where name = '유승한내들2';

comment on column public.complexes.short_code is
  '예약번호 단지 코드 (예: KG → KG-2606-001)';

-- ── 2) reservations.reservation_number ───────────────────────────
alter table public.reservations
  add column if not exists reservation_number text;

create unique index if not exists reservations_reservation_number_unique_idx
  on public.reservations (reservation_number)
  where reservation_number is not null and trim(reservation_number) <> '';

comment on column public.reservations.reservation_number is
  '표시용 예약번호 — {short_code}-{YYMM}-{순번3자리}';

-- ── 3) 단지·월별 채번 카운터 ────────────────────────────────────
create table if not exists public.reservation_number_counters (
  complex_id uuid not null references public.complexes(id) on delete cascade,
  year_month char(4) not null,
  last_seq integer not null default 0,
  primary key (complex_id, year_month)
);

revoke all on table public.reservation_number_counters from public;
grant select on table public.reservation_number_counters to authenticated;
grant all on table public.reservation_number_counters to service_role;

-- ── 4) 채번 함수 ────────────────────────────────────────────────
create or replace function public.allocate_reservation_number(
  p_complex_id uuid,
  p_reference_at timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_short text;
  v_yymm text;
  v_seq integer;
begin
  select nullif(trim(c.short_code), '')
  into v_short
  from public.complexes c
  where c.id = p_complex_id;

  if v_short is null then
    raise exception 'complex_short_code_missing';
  end if;

  v_yymm := to_char(
    coalesce(p_reference_at, now()) at time zone 'Asia/Seoul',
    'YYMM'
  );

  insert into public.reservation_number_counters as cnt (
    complex_id, year_month, last_seq
  )
  values (p_complex_id, v_yymm, 1)
  on conflict (complex_id, year_month)
  do update
    set last_seq = cnt.last_seq + 1
  returning last_seq into v_seq;

  return v_short || '-' || v_yymm || '-' || lpad(v_seq::text, 3, '0');
end;
$$;

revoke all on function public.allocate_reservation_number(uuid, timestamptz) from public;
grant execute on function public.allocate_reservation_number(uuid, timestamptz) to authenticated;
grant execute on function public.allocate_reservation_number(uuid, timestamptz) to service_role;

-- ── 5) 기존 예약 백필 + 카운터 동기화 ───────────────────────────
with numbered as (
  select
    r.id,
    c.short_code,
    to_char(
      coalesce(r.start_at, r.start_time, r.created_at, now())
        at time zone 'Asia/Seoul',
      'YYMM'
    ) as yymm,
    row_number() over (
      partition by
        v.complex_id,
        to_char(
          coalesce(r.start_at, r.start_time, r.created_at, now())
            at time zone 'Asia/Seoul',
          'YYMM'
        )
      order by r.id
    ) as seq
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.complexes c on c.id = v.complex_id
  where c.short_code is not null
    and trim(c.short_code) <> ''
    and (r.reservation_number is null or trim(r.reservation_number) = '')
)
update public.reservations r
set reservation_number =
  n.short_code || '-' || n.yymm || '-' || lpad(n.seq::text, 3, '0')
from numbered n
where r.id = n.id;

insert into public.reservation_number_counters (complex_id, year_month, last_seq)
select
  v.complex_id,
  split_part(r.reservation_number, '-', 2) as yymm,
  max(split_part(r.reservation_number, '-', 3)::integer) as max_seq
from public.reservations r
join public.vehicles v on v.id = r.vehicle_id
where r.reservation_number is not null
  and r.reservation_number ~ '^[A-Z]+-[0-9]{4}-[0-9]{3}$'
group by v.complex_id, split_part(r.reservation_number, '-', 2)
on conflict (complex_id, year_month) do update
  set last_seq = excluded.last_seq;

-- ── 6) INSERT 트리거 — 신규 예약 자동 채번 ─────────────────────
create or replace function public.reservations_set_reservation_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
  v_ref timestamptz;
begin
  if NEW.reservation_number is not null and trim(NEW.reservation_number) <> '' then
    return NEW;
  end if;

  select v.complex_id
  into v_complex_id
  from public.vehicles v
  where v.id = NEW.vehicle_id;

  if v_complex_id is null then
    raise exception 'vehicle_not_found';
  end if;

  v_ref := coalesce(NEW.start_at, NEW.start_time, NEW.created_at, now());
  NEW.reservation_number :=
    public.allocate_reservation_number(v_complex_id, v_ref);
  return NEW;
end;
$$;

drop trigger if exists reservations_before_insert_reservation_number
  on public.reservations;

create trigger reservations_before_insert_reservation_number
before insert on public.reservations
for each row
execute function public.reservations_set_reservation_number();

-- ── 7) RLS — reservation_number 는 reservations 행 정책으로 조회 ─
comment on column public.reservations.reservation_number is
  '표시용 예약번호. SELECT 은 reservations_select_own / staff / same_complex 정책 적용.';

-- ── 8) 매출 View — reservation_number 포함 ─────────────────────
drop view if exists public.sales_extension_lines_v;
drop view if exists public.sales_completed_reservations_v;

create view public.sales_completed_reservations_v as
select
  r.id,
  r.id::text as reservation_id_text,
  r.user_id,
  r.vehicle_id,
  v.complex_id,
  coalesce(v.model_name, '차량') as vehicle_name,
  coalesce(r.total_price, 0)::bigint as gross_amount,
  r.status,
  r.returned_at,
  r.actual_end_at,
  public.sales_return_completed_at(r.returned_at, r.actual_end_at) as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  coalesce(r.is_no_show, false) as is_no_show,
  r.reservation_number
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'completed'
  and public.sales_return_completed_at(r.returned_at, r.actual_end_at) is not null;

create view public.sales_extension_lines_v as
select
  scr.reservation_id_text,
  scr.complex_id,
  scr.return_completed_at,
  coalesce(re.added_price, 0)::bigint as extension_amount
from public.reservation_extensions re
inner join public.sales_completed_reservations_v scr
  on scr.reservation_id_text = re.reservation_id::text;

-- ── 9) 정산 시트 JSON — reservation_number ─────────────────────
create or replace function public.build_settlement_sheet_json(
  p_complex_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_month_start date;
  v_total_paid bigint := 0;
  v_cancel_refund bigint := 0;
  v_reservation_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_requested_at timestamptz;
  v_settled_at timestamptz;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_month_start := make_date(p_year, p_month, 1);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(p_year, p_month) as b;

  v_total_paid := public.sales_sum_gross(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations'
      and column_name = 'refund_amount'
  ) into v_has_refund_col;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reservations'
      and column_name = 'cancelled_at'
  ) into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1 and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc('month', coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul')::date = $2
      $sql$ into v_reservation_refund using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1 and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$ into v_reservation_refund using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc('month', coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul')::date = v_month_start;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = v_month_start;
    end if;
  end if;

  v_cancel_refund := coalesce(v_reservation_refund, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'reservation_number', s.reservation_number,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  v_counts := public.settlement_sheet_counts(
    p_complex_id, v_period_start, v_period_end, p_year, p_month
  );

  select
    cs.settled_at is not null,
    cs.requested_at is not null and cs.settled_at is null,
    cs.requested_at,
    cs.settled_at
  into v_is_settled, v_is_requested, v_requested_at, v_settled_at
  from public.complex_settlements cs
  where cs.complex_id = p_complex_id
    and cs.period_year = p_year
    and cs.period_month = p_month;

  return jsonb_build_object(
    'complex_id', p_complex_id,
    'year', p_year,
    'month', p_month,
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'items', coalesce(v_items, '[]'::jsonb),
    'payment_count', coalesce((v_counts->>'payment_count')::bigint, 0),
    'cancel_count', coalesce((v_counts->>'cancel_count')::bigint, 0),
    'rental_count', coalesce((v_counts->>'rental_count')::bigint, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'requested_at', v_requested_at,
    'settled_at', v_settled_at
  );
end;
$$;

-- ── 10) 관리자 예약 RPC — reservation_number ───────────────────
drop function if exists public.get_admin_completed_reservations(integer, integer);

create or replace function public.get_admin_completed_reservations(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  reservation_number text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  return_type text,
  is_no_show boolean,
  second_driver_name text,
  second_driver_license text,
  sort_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid() and s.approved = true
    limit 1
  )
  select
    r.id::text as reservation_id,
    r.reservation_number,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone,
    r.status,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    r.return_type,
    coalesce(r.is_no_show, false) as is_no_show,
    nullif(trim(r.second_driver_name), '') as second_driver_name,
    nullif(trim(r.second_driver_license), '') as second_driver_license,
    coalesce(
      r.returned_at, r.actual_end_at, r.updated_at,
      r.end_at, r.end_time, r.start_at, r.start_time
    ) as sort_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join staff_complex sc on sc.complex_id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  where r.status = 'completed'
     or (r.status = 'cancelled' and coalesce(r.is_no_show, false) = true)
  order by sort_at desc nulls last
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

drop function if exists public.get_admin_reservations_with_conflict(integer, integer);

create or replace function public.get_admin_reservations_with_conflict(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  reservation_id text,
  reservation_number text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_started_at timestamptz,
  updated_at timestamptz,
  next_start_at timestamptz,
  next_renter_name text,
  next_renter_phone text,
  is_conflict_risk boolean,
  second_driver_name text,
  second_driver_license text
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_complex as (
    select s.complex_id
    from public.staff_users s
    where s.user_id = auth.uid() and s.approved = true
    limit 1
  ),
  scoped as (
    select
      r.id,
      r.reservation_number,
      r.vehicle_id,
      r.user_id,
      r.status,
      coalesce(r.start_at, r.start_time) as start_at,
      coalesce(r.end_at, r.end_time) as end_at,
      coalesce(r.total_price, 0) as total_price,
      r.rental_started_at,
      r.updated_at,
      nullif(trim(r.second_driver_name), '') as second_driver_name,
      nullif(trim(r.second_driver_license), '') as second_driver_license,
      coalesce(v.model_name, '차량') as vehicle_name,
      v.car_number,
      coalesce(
        nullif(trim(up.full_name), ''),
        nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as renter_name,
      coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    join staff_complex sc on sc.complex_id = v.complex_id
    left join public.user_profiles up on up.user_id = r.user_id
    where r.status in ('pending', 'confirmed', 'in_use', 'returning')
      and r.status not in ('returned', 'completed', 'cancelled')
  )
  select
    s.id::text as reservation_id,
    s.reservation_number,
    s.vehicle_name,
    s.car_number,
    s.renter_name,
    s.renter_phone,
    s.status,
    s.start_at,
    s.end_at,
    s.total_price,
    s.rental_started_at,
    s.updated_at,
    next_res.next_start_at,
    next_res.next_renter_name,
    next_res.next_renter_phone,
    (s.status = 'in_use' and next_res.next_start_at is not null) as is_conflict_risk,
    s.second_driver_name,
    s.second_driver_license
  from scoped s
  left join lateral (
    select
      coalesce(n.start_at, n.start_time) as next_start_at,
      coalesce(
        nullif(trim(nup.full_name), ''),
        nullif(split_part(nullif(trim(nup.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as next_renter_name,
      coalesce(nullif(trim(nup.phone), ''), '미등록') as next_renter_phone
    from public.reservations n
    left join public.user_profiles nup on nup.user_id = n.user_id
    where n.vehicle_id = s.vehicle_id
      and n.id <> s.id
      and n.status in ('pending', 'confirmed', 'in_use')
      and n.status not in ('returned', 'completed', 'cancelled')
      and coalesce(n.start_at, n.start_time) <= s.end_at + interval '30 minutes'
      and coalesce(n.start_at, n.start_time) >= s.end_at - interval '5 minutes'
    order by coalesce(n.start_at, n.start_time)
    limit 1
  ) next_res on true
  order by s.start_at desc nulls last
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.get_admin_completed_reservations(integer, integer) from public;
grant execute on function public.get_admin_completed_reservations(integer, integer) to authenticated;

revoke all on function public.get_admin_reservations_with_conflict(integer, integer) from public;
grant execute on function public.get_admin_reservations_with_conflict(integer, integer) to authenticated;

-- ── 11) 최고관리자 전체 예약 RPC ────────────────────────────────
drop function if exists public.get_super_admin_reservations();

create or replace function public.get_super_admin_reservations()
returns table (
  reservation_id text,
  reservation_number text,
  complex_id uuid,
  complex_name text,
  vehicle_id text,
  vehicle_name text,
  car_number text,
  renter_name text,
  renter_phone text,
  status text,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  rental_started_at timestamptz,
  returned_at timestamptz,
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
    r.id::text as reservation_id,
    r.reservation_number,
    v.complex_id,
    c.name as complex_name,
    r.vehicle_id::text as vehicle_id,
    coalesce(v.model_name, '차량') as vehicle_name,
    v.car_number,
    coalesce(
      nullif(trim(up.full_name), ''),
      nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
      '이름 미등록'
    ) as renter_name,
    coalesce(nullif(trim(up.phone), ''), '미등록') as renter_phone,
    r.status,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    r.rental_started_at,
    r.returned_at,
    r.created_at
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.complexes c on c.id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  order by coalesce(r.start_at, r.start_time) desc nulls last;
end;
$$;

revoke all on function public.get_super_admin_reservations() from public;
grant execute on function public.get_super_admin_reservations() to authenticated;

-- ── 12) 입주민 상세 대여 이력 — reservation_number ─────────────
create or replace function public.get_super_admin_resident_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  perform public.assert_is_super_admin();

  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  select jsonb_build_object(
    'user_id', res.user_id::text,
    'complex_id', res.complex_id::text,
    'complex_name', c.name,
    'building', res.building,
    'unit', res.unit,
    'approved', res.approved,
    'full_name', up.full_name,
    'phone', up.phone,
    'email', coalesce(up.email, au.email::text),
    'created_at', res.created_at,
    'is_blacklisted', coalesce(up.is_blacklisted, false),
    'license_verified', coalesce(up.license_verified, false),
    'license_status', coalesce(up.license_status, 'none'),
    'license_number', up.license_number,
    'license_expiry', up.license_expiry,
    'points', coalesce(up.points, 0),
    'coupon_count', (
      select count(*)::integer
      from public.user_coupons uc
      where uc.user_id = res.user_id
        and coalesce(uc.is_used, false) = false
    ),
    'rental_count', (
      select count(*)::integer
      from public.reservations r
      where r.user_id = res.user_id
    ),
    'rentals', coalesce((
      select jsonb_agg(row_data order by sort_at desc nulls last)
      from (
        select
          coalesce(r.start_at, r.start_time) as sort_at,
          jsonb_build_object(
            'reservation_id', r.id::text,
            'reservation_number', r.reservation_number,
            'vehicle_name', coalesce(v.model_name, '차량'),
            'start_at', coalesce(r.start_at, r.start_time),
            'end_at', coalesce(r.end_at, r.end_time),
            'total_price', coalesce(r.total_price, 0),
            'status', r.status,
            'second_driver_name', nullif(trim(r.second_driver_name), ''),
            'second_driver_license', nullif(trim(r.second_driver_license), '')
          ) as row_data
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where r.user_id = res.user_id
      ) rental_rows
    ), '[]'::jsonb)
  )
  into v_result
  from public.residents res
  join public.complexes c on c.id = res.complex_id
  left join public.user_profiles up on up.user_id = res.user_id
  left join auth.users au on au.id = res.user_id
  where res.user_id = p_user_id;

  if v_result is null then
    raise exception 'resident_not_found';
  end if;

  return v_result;
end;
$$;
