-- billing_charge_retries charge_type 분류 점검 (마이그레이션 20260637000000 적용 후)

select
  charge_type,
  status,
  count(*) as cnt
from public.billing_charge_retries
group by charge_type, status
order by charge_type, status;

-- 반납지연으로 보이는 extension 잔존 (마이그레이션 후 0이어야 함)
select
  b.id,
  b.charge_type,
  b.reservation_id,
  b.amount,
  b.extension_hours,
  b.status,
  r.overdue_overage_amount,
  r.overdue_overage_hours,
  r.overdue_overage_charged
from public.billing_charge_retries b
join public.reservations r on r.id::text = b.reservation_id
where b.charge_type = 'extension'
  and coalesce(r.overdue_overage_amount, 0) > 0
  and b.amount = r.overdue_overage_amount;

-- overdue_overage 행 (예: 예약 52)
select
  b.*,
  r.reservation_number,
  r.overdue_overage_amount,
  r.overdue_overage_hours
from public.billing_charge_retries b
join public.reservations r on r.id::text = b.reservation_id
where b.charge_type = 'overdue_overage'
order by b.created_at desc;
