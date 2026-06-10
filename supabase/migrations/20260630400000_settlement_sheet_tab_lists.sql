-- 정산 바텀시트 탭 목록 — payment_items / cancel_items (스키마 변경 없음, RPC 반환만 확장)
-- 결제건수: 결제일(KST 월) 기준 paid payment_orders
-- 대여건수: 반납완료일 기준 sales_completed_reservations_v (기존 items)
-- 취소건수: 취소일(KST 월) 기준 cancelled (노쇼 제외)

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

  select count(*)::bigint
  into v_payment_count
  from public.payment_orders po
  inner join public.reservations r on (
    (r.order_id is not null and po.order_id = r.order_id)
    or (po.reservation_id is not null and po.reservation_id = r.id::text)
    or po.order_id like 'ext_' || r.id::text || '_%'
  )
  inner join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and po.status = 'paid'
    and coalesce(po.vehicle_id, '') <> 'signup_card'
    and date_trunc(
      'month',
      coalesce(po.updated_at, po.created_at) at time zone 'Asia/Seoul'
    )::date = v_month_start;

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
      and coalesce(r.is_no_show, false) = false
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
      and coalesce(r.is_no_show, false) = false
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

comment on function public.settlement_sheet_counts(uuid, timestamptz, timestamptz, integer, integer) is
  '정산 건수 — payment_count=결제일(KST월) paid orders, cancel_count=취소월 cancelled(노쇼제외), rental_count=반납완료 completed';

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
  v_items jsonb := '[]'::jsonb;
  v_payment_items jsonb := '[]'::jsonb;
  v_cancel_items jsonb := '[]'::jsonb;
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
        'actual_end_at', s.actual_end_at,
        'is_no_show', s.is_no_show
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'order_id', po.order_id,
        'reservation_id', r.id::text,
        'reservation_number', r.reservation_number,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'paid_at', coalesce(po.updated_at, po.created_at),
        'payment_amount', coalesce(po.total_price, 0)
      )
      order by coalesce(po.updated_at, po.created_at) desc nulls last
    ),
    '[]'::jsonb
  )
  into v_payment_items
  from public.payment_orders po
  inner join public.reservations r on (
    (r.order_id is not null and po.order_id = r.order_id)
    or (po.reservation_id is not null and po.reservation_id = r.id::text)
    or po.order_id like 'ext_' || r.id::text || '_%'
  )
  inner join public.vehicles v on v.id = r.vehicle_id
  left join public.user_profiles up on up.user_id = r.user_id
  where v.complex_id = p_complex_id
    and po.status = 'paid'
    and coalesce(po.vehicle_id, '') <> 'signup_card'
    and date_trunc(
      'month',
      coalesce(po.updated_at, po.created_at) at time zone 'Asia/Seoul'
    )::date = v_month_start;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'reservation_id', r.id::text,
              'reservation_number', r.reservation_number,
              'renter_name', coalesce(
                nullif(trim(up.full_name), ''),
                nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
                '이름 미등록'
              ),
              'cancelled_at', coalesce(r.cancelled_at, r.updated_at),
              'paid_amount', coalesce(r.total_price, 0),
              'refund_amount', coalesce(r.refund_amount, 0),
              'cancel_reason', case
                when r.rental_started_at is not null then '관리자 강제취소'
                else '고객취소'
              end
            )
            order by coalesce(r.cancelled_at, r.updated_at) desc nulls last
          ),
          '[]'::jsonb
        )
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        left join public.user_profiles up on up.user_id = r.user_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc(
            'month',
            coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
          )::date = $2
      $sql$
      into v_cancel_items
      using p_complex_id, v_month_start;
    else
      execute $sql$
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'reservation_id', r.id::text,
              'reservation_number', r.reservation_number,
              'renter_name', coalesce(
                nullif(trim(up.full_name), ''),
                nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
                '이름 미등록'
              ),
              'cancelled_at', r.updated_at,
              'paid_amount', coalesce(r.total_price, 0),
              'refund_amount', coalesce(r.refund_amount, 0),
              'cancel_reason', case
                when r.rental_started_at is not null then '관리자 강제취소'
                else '고객취소'
              end
            )
            order by r.updated_at desc nulls last
          ),
          '[]'::jsonb
        )
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        left join public.user_profiles up on up.user_id = r.user_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.is_no_show, false) = false
          and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date = $2
      $sql$
      into v_cancel_items
      using p_complex_id, v_month_start;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'reservation_id', r.id::text,
            'reservation_number', r.reservation_number,
            'renter_name', coalesce(
              nullif(trim(up.full_name), ''),
              nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
              '이름 미등록'
            ),
            'cancelled_at', coalesce(r.cancelled_at, r.updated_at),
            'paid_amount', coalesce(r.total_price, 0),
            'refund_amount', coalesce(r.total_price, 0),
            'cancel_reason', case
              when r.rental_started_at is not null then '관리자 강제취소'
              else '고객취소'
            end
          )
          order by coalesce(r.cancelled_at, r.updated_at) desc nulls last
        ),
        '[]'::jsonb
      )
      into v_cancel_items
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      left join public.user_profiles up on up.user_id = r.user_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc(
          'month',
          coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
        )::date = v_month_start;
    else
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'reservation_id', r.id::text,
            'reservation_number', r.reservation_number,
            'renter_name', coalesce(
              nullif(trim(up.full_name), ''),
              nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
              '이름 미등록'
            ),
            'cancelled_at', r.updated_at,
            'paid_amount', coalesce(r.total_price, 0),
            'refund_amount', coalesce(r.total_price, 0),
            'cancel_reason', case
              when r.rental_started_at is not null then '관리자 강제취소'
              else '고객취소'
            end
          )
          order by r.updated_at desc nulls last
        ),
        '[]'::jsonb
      )
      into v_cancel_items
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      left join public.user_profiles up on up.user_id = r.user_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.is_no_show, false) = false
        and date_trunc('month', r.updated_at at time zone 'Asia/Seoul')::date =
          v_month_start;
    end if;
  end if;

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
    'cancel_refund', 0,
    'net_revenue', coalesce(v_total_paid, 0),
    'items', coalesce(v_items, '[]'::jsonb),
    'payment_items', coalesce(v_payment_items, '[]'::jsonb),
    'cancel_items', coalesce(v_cancel_items, '[]'::jsonb),
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

comment on function public.build_settlement_sheet_json(uuid, integer, integer) is
  '정산 상세 — items=반납완료, payment_items=결제일월, cancel_items=취소월, 건수=목록 길이와 동일 조건';
