-- 1) sales_completed_reservations_v — completed + is_no_show 포함
-- 2) build_settlement_sheet_json — 취소 환불 제거, 순매출 = completed gross 합계만

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
  case
    when coalesce(r.is_no_show, false) then
      coalesce(
        public.sales_return_completed_at(
          r.returned_at,
          r.actual_end_at,
          coalesce(r.end_at, r.end_time)
        ),
        r.updated_at
      )
    else
      public.sales_return_completed_at(
        r.returned_at,
        r.actual_end_at,
        coalesce(r.end_at, r.end_time)
      )
  end as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  coalesce(r.is_no_show, false) as is_no_show,
  r.reservation_number
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'completed'
  and (
    coalesce(r.is_no_show, false) = true
    or public.sales_return_completed_at(
      r.returned_at,
      r.actual_end_at,
      coalesce(r.end_at, r.end_time)
    ) is not null
  );

comment on view public.sales_completed_reservations_v is
  '매출 집계 대상 — status=completed (is_no_show 포함), 반납완료일 또는 노쇼 actual_end/end/updated_at';

create view public.sales_extension_lines_v as
select
  scr.reservation_id_text,
  scr.complex_id,
  scr.return_completed_at,
  coalesce(re.added_price, 0)::bigint as extension_amount
from public.reservation_extensions re
inner join public.sales_completed_reservations_v scr
  on scr.reservation_id_text = re.reservation_id::text;

-- ── 정산 바텀시트 — 취소 환불 조회·차감 제거 ───────────────────
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
  v_total_paid bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_is_settled boolean := false;
  v_is_requested boolean := false;
  v_requested_at timestamptz;
  v_settled_at timestamptz;
begin
  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(p_year, p_month) as b;

  v_total_paid := public.sales_sum_gross(
    p_complex_id, v_period_start, v_period_end
  );

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
  '정산 상세 — net_revenue = completed(is_no_show 포함) gross_amount 합계, 취소환불 미차감';
