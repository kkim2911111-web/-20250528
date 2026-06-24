-- sales_completed_reservations_v — gross_amount에 반납지연·연장 요금 포함

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
  (
    coalesce(r.total_price, 0)
    + coalesce(r.overdue_overage_amount, 0)
    + coalesce(r.extension_price_total, 0)
  )::bigint as gross_amount,
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
  )

union all

select
  r.id,
  r.id::text as reservation_id_text,
  r.user_id,
  r.vehicle_id,
  v.complex_id,
  coalesce(v.model_name, '차량') as vehicle_name,
  greatest(
    public.reservation_card_paid_amount(r.id::text)
      - coalesce(r.refund_amount, 0)::bigint,
    0::bigint
  ) as gross_amount,
  r.status,
  r.returned_at,
  r.actual_end_at,
  coalesce(r.cancelled_at, r.updated_at) as return_completed_at,
  coalesce(r.start_at, r.start_time) as start_at,
  coalesce(r.end_at, r.end_time) as end_at,
  r.rental_started_at,
  false as is_no_show,
  r.reservation_number
from public.reservations r
inner join public.vehicles v on v.id = r.vehicle_id
where r.status = 'cancelled'
  and r.cancel_reason = 'customer'
  and coalesce(r.is_no_show, false) = false
  and (
    r.payment_status in ('paid', 'confirmed')
    or r.payment_key is not null
    or exists (
      select 1
      from public.payment_orders po
      where po.status in ('paid', 'confirmed')
        and (
          (r.order_id is not null and po.order_id = r.order_id)
          or (po.reservation_id is not null and po.reservation_id = r.id::text)
        )
    )
  )
  and greatest(
    public.reservation_card_paid_amount(r.id::text)
      - coalesce(r.refund_amount, 0)::bigint,
    0::bigint
  ) > 0;

comment on view public.sales_completed_reservations_v is
  '매출 집계 — completed(반납완료·노쇼, gross=total+지연+연장) + 고객취소 잔여매출';

create view public.sales_extension_lines_v as
select
  scr.reservation_id_text,
  scr.complex_id,
  scr.return_completed_at,
  coalesce(re.added_price, 0)::bigint as extension_amount
from public.reservation_extensions re
inner join public.sales_completed_reservations_v scr
  on scr.reservation_id_text = re.reservation_id::text;

comment on view public.sales_extension_lines_v is
  '매출 집계 대상 연장 요금 — sales_completed_reservations_v와 동일 예약만.';
