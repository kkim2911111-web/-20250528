-- 정산 순매출 = sales_sum_gross 통일 (환불은 sales_completed_reservations_v에서 1회 차감)
-- 집계·환불 재계산 없음 — build_settlement_sheet_json 재배포 + 표시용 필드만 확장

drop function if exists public.build_settlement_sheet_json(uuid, integer, integer);

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
  v_items jsonb := '[]'::jsonb;
  v_payment_items jsonb := '[]'::jsonb;
  v_cancel_items jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_requested_at timestamptz;
  v_settled_at timestamptz;
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', row_data.reservation_id,
        'reservation_number', row_data.reservation_number,
        'renter_name', row_data.renter_name,
        'total_price', row_data.total_price,
        'status', row_data.status,
        'paid_amount', row_data.paid_amount,
        'refund_amount', row_data.refund_amount,
        'rental_type', row_data.rental_type,
        'start_at', row_data.start_at,
        'end_at', row_data.end_at,
        'rental_started_at', row_data.rental_started_at,
        'returned_at', row_data.returned_at,
        'actual_end_at', row_data.actual_end_at,
        'is_no_show', row_data.is_no_show
      )
      order by row_data.sort_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      s.reservation_id_text as reservation_id,
      s.reservation_number,
      coalesce(
        nullif(trim(up.full_name), ''),
        nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
        '이름 미등록'
      ) as renter_name,
      coalesce(s.gross_amount, 0)::bigint as total_price,
      s.status,
      public.reservation_card_paid_amount(s.reservation_id_text) as paid_amount,
      coalesce(r.refund_amount, 0)::bigint as refund_amount,
      coalesce(r.rental_type, 'hourly') as rental_type,
      s.start_at,
      s.end_at,
      s.rental_started_at,
      s.returned_at,
      s.actual_end_at,
      s.is_no_show,
      s.return_completed_at as sort_at
    from public.sales_completed_reservations_v s
    left join public.reservations r on r.id::text = s.reservation_id_text
    left join public.user_profiles up on up.user_id = s.user_id
    where s.complex_id = p_complex_id
      and s.return_completed_at >= v_period_start
      and s.return_completed_at < v_period_end
  ) row_data;

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
        'paid_amount', public.reservation_card_paid_amount(r.id::text),
        'refund_amount', coalesce(r.refund_amount, 0),
        'cancel_reason', public.cancel_reason_display_label(r.cancel_reason)
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

  select coalesce(sum(coalesce(r.refund_amount, 0)), 0)::bigint
  into v_cancel_refund
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where v.complex_id = p_complex_id
    and r.status = 'cancelled'
    and coalesce(r.is_no_show, false) = false
    and date_trunc(
      'month',
      coalesce(r.cancelled_at, r.updated_at) at time zone 'Asia/Seoul'
    )::date = v_month_start;

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

revoke all on function public.build_settlement_sheet_json(uuid, integer, integer) from public;
grant execute on function public.build_settlement_sheet_json(uuid, integer, integer) to authenticated;

comment on function public.build_settlement_sheet_json(uuid, integer, integer) is
  '정산 상세 — net_revenue=sales_sum_gross(뷰 1회 환불차감), cancel_refund는 표시용, items에 paid/refund 표시 필드';

-- 최고관리자 전체 예약 — 환불 뱃지 표시용 (기존 refund_amount 컬럼만 노출)
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
  is_no_show boolean,
  start_at timestamptz,
  end_at timestamptz,
  total_price integer,
  paid_amount bigint,
  refund_amount bigint,
  rental_type text,
  rental_started_at timestamptz,
  returned_at timestamptz,
  actual_end_at timestamptz,
  created_at timestamptz,
  cancelled_at timestamptz,
  pickup_photos text[],
  return_photos text[]
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
    coalesce(r.is_no_show, false) as is_no_show,
    coalesce(r.start_at, r.start_time) as start_at,
    coalesce(r.end_at, r.end_time) as end_at,
    coalesce(r.total_price, 0) as total_price,
    public.reservation_card_paid_amount(r.id::text) as paid_amount,
    coalesce(r.refund_amount, 0)::bigint as refund_amount,
    coalesce(r.rental_type, 'hourly') as rental_type,
    r.rental_started_at,
    r.returned_at,
    r.actual_end_at,
    r.created_at,
    r.cancelled_at,
    coalesce(r.pickup_photos, '{}'::text[]) as pickup_photos,
    coalesce(r.return_photos, '{}'::text[]) as return_photos
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.complexes c on c.id = v.complex_id
  left join public.user_profiles up on up.user_id = r.user_id
  order by
    case
      when lower(trim(r.status)) = 'cancelled'
        then coalesce(r.cancelled_at, r.updated_at)
      else coalesce(r.start_at, r.start_time)
    end desc nulls last;
end;
$$;

revoke all on function public.get_super_admin_reservations() from public;
grant execute on function public.get_super_admin_reservations() to authenticated;

comment on function public.get_super_admin_reservations() is
  '최고관리자 전체 예약 — paid_amount/refund_amount 표시용(재계산 없음)';
