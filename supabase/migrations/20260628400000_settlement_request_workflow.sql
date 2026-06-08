-- 정산 요청 워크플로 — 결제/취소/대여 건수, 단지관리자 요청, 최고관리자 정산

-- ── 1) complex_settlements 확장 ─────────────────────────────────
alter table public.complex_settlements
  alter column settled_at drop not null,
  alter column settled_at drop default;

alter table public.complex_settlements
  add column if not exists requested_at timestamptz,
  add column if not exists requested_by uuid references auth.users(id) on delete set null;

comment on column public.complex_settlements.requested_at is
  '단지관리자 정산 요청 시각 (settled_at 이전)';
comment on column public.complex_settlements.requested_by is
  '정산 요청한 단지관리자 user_id';

-- ── 2) 건수 집계 헬퍼 ───────────────────────────────────────────
create or replace function public.settlement_sheet_counts(
  p_complex_id uuid,
  p_period_start timestamptz,
  p_period_end timestamptz,
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
  v_payment_count bigint := 0;
  v_cancel_count bigint := 0;
  v_rental_count bigint := 0;
  v_month_start date;
  v_has_cancelled_at_col boolean := false;
begin
  v_month_start := make_date(p_year, p_month, 1);

  v_rental_count := public.sales_count_reservations(
    p_complex_id, p_period_start, p_period_end
  );

  select count(distinct po.order_id)::bigint
  into v_payment_count
  from public.sales_completed_reservations_v s
  join public.reservations r on r.id::text = s.reservation_id_text
  join public.payment_orders po
    on po.order_id = r.order_id
    and po.status = 'paid'
  where s.complex_id = p_complex_id
    and s.return_completed_at >= p_period_start
    and s.return_completed_at < p_period_end;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_cancelled_at_col then
    select count(*)::bigint
    into v_cancel_count
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status = 'cancelled'
      and date_trunc(
        'month',
        coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
      )::date = v_month_start;
  else
    select count(*)::bigint
    into v_cancel_count
    from public.reservations r
    join public.vehicles v on v.id = r.vehicle_id
    where v.complex_id = p_complex_id
      and r.status = 'cancelled'
      and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date =
        v_month_start;
  end if;

  return jsonb_build_object(
    'payment_count', coalesce(v_payment_count, 0),
    'cancel_count', coalesce(v_cancel_count, 0),
    'rental_count', coalesce(v_rental_count, 0)
  );
end;
$$;

revoke all on function public.settlement_sheet_counts(uuid, timestamptz, timestamptz, integer, integer) from public;
grant execute on function public.settlement_sheet_counts(uuid, timestamptz, timestamptz, integer, integer) to authenticated;

-- ── 3) 정산 상세 JSON 빌더 (공통) ───────────────────────────────
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
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'refund_amount'
  )
  into v_has_refund_col;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc(
            'month',
            coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
          )::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$
      into v_reservation_refund
      using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc(
          'month',
          coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
        )::date = v_month_start;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_reservation_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date =
          v_month_start;
    end if;
  end if;

  v_cancel_refund := coalesce(v_reservation_refund, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
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
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'payment_count', coalesce((v_counts->>'payment_count')::bigint, 0),
    'cancel_count', coalesce((v_counts->>'cancel_count')::bigint, 0),
    'rental_count', coalesce((v_counts->>'rental_count')::bigint, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'requested_at', v_requested_at,
    'settled_at', v_settled_at,
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.build_settlement_sheet_json(uuid, integer, integer) from public;
grant execute on function public.build_settlement_sheet_json(uuid, integer, integer) to authenticated;

-- ── 4) get_super_admin_settlement_reservations ───────────────────
drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

create function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
begin
  perform public.assert_is_super_admin();

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);

  return public.build_settlement_sheet_json(p_complex_id, v_year, v_month);
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

-- ── 5) get_admin_settlement_sheet (단지관리자) ──────────────────
create or replace function public.get_admin_settlement_sheet(
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_complex_id uuid;
  v_year integer;
  v_month integer;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select s.complex_id
  into v_complex_id
  from public.staff_users s
  where s.user_id = v_user
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    raise exception 'staff_not_found';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);

  return public.build_settlement_sheet_json(v_complex_id, v_year, v_month);
end;
$$;

revoke all on function public.get_admin_settlement_sheet(integer, integer) from public;
grant execute on function public.get_admin_settlement_sheet(integer, integer) to authenticated;

-- ── 6) request_settlement_for_staff ─────────────────────────────
create or replace function public.request_settlement_for_staff(
  p_year integer default null,
  p_month integer default null,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_complex_id uuid;
  v_complex_name text;
  v_year integer;
  v_month integer;
  v_settled_at timestamptz;
  v_requested_at timestamptz;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_id is not null
    and p_user_id is distinct from auth.uid()
    and coalesce(current_setting('role', true), '') <> 'service_role' then
    raise exception 'forbidden';
  end if;

  select s.complex_id, c.name
  into v_complex_id, v_complex_name
  from public.staff_users s
  join public.complexes c on c.id = s.complex_id
  where s.user_id = v_user
    and s.approved = true
  limit 1;

  if v_complex_id is null then
    raise exception 'staff_not_found';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);

  select cs.settled_at, cs.requested_at
  into v_settled_at, v_requested_at
  from public.complex_settlements cs
  where cs.complex_id = v_complex_id
    and cs.period_year = v_year
    and cs.period_month = v_month;

  if v_settled_at is not null then
    raise exception 'already_settled';
  end if;

  if v_requested_at is not null then
    return jsonb_build_object(
      'ok', true,
      'alreadyRequested', true,
      'complexId', v_complex_id,
      'complexName', v_complex_name,
      'year', v_year,
      'month', v_month
    );
  end if;

  insert into public.complex_settlements (
    complex_id, period_year, period_month, requested_at, requested_by
  )
  values (v_complex_id, v_year, v_month, now(), v_user)
  on conflict (complex_id, period_year, period_month) do update
  set
    requested_at = coalesce(complex_settlements.requested_at, now()),
    requested_by = coalesce(complex_settlements.requested_by, excluded.requested_by)
  where complex_settlements.settled_at is null;

  return jsonb_build_object(
    'ok', true,
    'alreadyRequested', false,
    'complexId', v_complex_id,
    'complexName', v_complex_name,
    'year', v_year,
    'month', v_month
  );
end;
$$;

revoke all on function public.request_settlement_for_staff(integer, integer, uuid) from public;
grant execute on function public.request_settlement_for_staff(integer, integer, uuid) to authenticated;

-- ── 7) mark_super_admin_settlement — settled_at 기준 ────────────
create or replace function public.mark_super_admin_settlement(
  p_complex_id uuid,
  p_year integer,
  p_month integer,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_is_super_admin();

  insert into public.complex_settlements (
    complex_id, period_year, period_month, settled_at, settled_by, note
  )
  values (
    p_complex_id, p_year, p_month, now(), auth.uid(), nullif(trim(p_note), '')
  )
  on conflict (complex_id, period_year, period_month) do update
  set
    settled_at = now(),
    settled_by = auth.uid(),
    note = coalesce(excluded.note, complex_settlements.note);
end;
$$;

-- ── 8) get_super_admin_revenue — is_requested 추가 ─────────────
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
  is_requested boolean,
  settled_at timestamptz,
  requested_at timestamptz
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
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  return query
  with complexes_all as (
    select c.id, c.name from public.complexes c
  ),
  res_sales as (
    select
      s.complex_id,
      count(*)::bigint as reservation_count,
      coalesce(sum(s.gross_amount), 0)::bigint as gross_revenue
    from public.sales_completed_reservations_v s
    where s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.complex_id
  ),
  extensions as (
    select
      e.complex_id,
      coalesce(sum(e.extension_amount), 0)::bigint as extension_revenue
    from public.sales_extension_lines_v e
    where e.return_completed_at >= v_period_start
      and e.return_completed_at < v_period_end
    group by e.complex_id
  ),
  paid_orders as (
    select
      s.complex_id,
      count(distinct po.order_id)::bigint as paid_order_count,
      coalesce(sum(po.total_price), 0)::bigint as paid_order_amount
    from public.sales_completed_reservations_v s
    join public.reservations r on r.id::text = s.reservation_id_text
    join public.payment_orders po
      on po.order_id = r.order_id
      and po.status = 'paid'
    where s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.complex_id
  )
  select
    ca.id,
    ca.name,
    v_year,
    v_month,
    coalesce(rs.reservation_count, 0),
    coalesce(rs.gross_revenue, 0),
    coalesce(po.paid_order_count, 0),
    coalesce(po.paid_order_amount, 0),
    coalesce(ex.extension_revenue, 0),
    (cs.settled_at is not null),
    (cs.requested_at is not null and cs.settled_at is null),
    cs.settled_at,
    cs.requested_at
  from complexes_all ca
  left join res_sales rs on rs.complex_id = ca.id
  left join paid_orders po on po.complex_id = ca.id
  left join extensions ex on ex.complex_id = ca.id
  left join public.complex_settlements cs
    on cs.complex_id = ca.id
    and cs.period_year = v_year
    and cs.period_month = v_month
  order by
    coalesce(rs.gross_revenue, 0) + coalesce(ex.extension_revenue, 0) desc,
    ca.name asc nulls last;
end;
$$;

revoke all on function public.get_super_admin_revenue(integer, integer) from public;
grant execute on function public.get_super_admin_revenue(integer, integer) to authenticated;

-- ── 9) get_admin_sales_summary — 정산 상태 필드 ─────────────────
drop function if exists public.get_admin_sales_summary(uuid, integer, integer);

create or replace function public.get_admin_sales_summary(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
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
  v_gross bigint := 0;
  v_extension bigint := 0;
  v_count bigint := 0;
  v_vehicle_count integer := 0;
  v_rows jsonb := '[]'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  select count(*)::integer
  into v_vehicle_count
  from public.vehicles v
  where v.complex_id = p_complex_id;

  v_count := public.sales_count_reservations(p_complex_id, v_period_start, v_period_end);
  v_gross := public.sales_sum_gross(p_complex_id, v_period_start, v_period_end);
  v_extension := public.sales_sum_extension(p_complex_id, v_period_start, v_period_end);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vehicle_name', row_data.vehicle_name,
        'amount', row_data.amount,
        'count', row_data.cnt
      )
      order by row_data.amount desc nulls last
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      s.vehicle_name,
      coalesce(sum(s.gross_amount), 0)::bigint as amount,
      count(*)::bigint as cnt
    from public.sales_completed_reservations_v s
    where s.complex_id = p_complex_id
      and s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
    group by s.vehicle_name
  ) row_data;

  select
    cs.settled_at is not null,
    cs.requested_at is not null and cs.settled_at is null
  into v_is_settled, v_is_requested
  from public.complex_settlements cs
  where cs.complex_id = p_complex_id
    and cs.period_year = v_year
    and cs.period_month = v_month;

  return jsonb_build_object(
    'gross_revenue', coalesce(v_gross, 0),
    'extension_revenue', coalesce(v_extension, 0),
    'total_revenue', coalesce(v_gross, 0) + coalesce(v_extension, 0),
    'reservation_count', coalesce(v_count, 0),
    'vehicle_count', coalesce(v_vehicle_count, 0),
    'is_settled', coalesce(v_is_settled, false),
    'is_requested', coalesce(v_is_requested, false),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

-- ── 10) 관리자 알림 type — 정산 요청 ────────────────────────────
create or replace function public.is_admin_notification_type(p_type text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_type, '') like 'admin%'
      or coalesce(p_type, '') like 'staff_%'
      or coalesce(p_type, '') = 'admin_settlement_request';
$$;
