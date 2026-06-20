-- 예약 52 (KG-2606-052, BYD 아토3, rental_type=hourly) 반납 지연 요금 시뮬레이션
-- 마이그레이션 20260635000000 적용 후 실행

-- 1) 예약·차량 요율 확인
select
  r.id,
  r.reservation_number,
  r.rental_type,
  r.status,
  r.is_overdue,
  coalesce(r.end_at, r.end_time) as scheduled_end,
  v.model_name,
  coalesce(v.hourly_rate, v.price_per_hour) as hourly_rate_effective,
  v.daily_overage_hourly_rate,
  v.monthly_excess_daily_price
from public.reservations r
join public.vehicles v on v.id = r.vehicle_id
where r.reservation_number = 'KG-2606-052'
   or r.id::text = '52';

-- 2) 2시간 10분 지연 반납 시뮬레이션 (3시간 × 시간당요금)
with ctx as (
  select
    r.rental_type,
    coalesce(r.end_at, r.end_time) as scheduled_end,
    coalesce(v.hourly_rate, v.price_per_hour) as hourly_rate,
    v.price_per_hour,
    v.daily_overage_hourly_rate
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  where r.reservation_number = 'KG-2606-052'
     or r.id::text = '52'
  limit 1
)
select
  ctx.rental_type,
  public.resolve_return_overdue_hourly_rate(
    ctx.rental_type,
    ctx.hourly_rate,
    ctx.price_per_hour,
    ctx.daily_overage_hourly_rate
  ) as resolved_hourly_rate,
  public.calc_return_overdue_overage(
    ctx.scheduled_end,
    ctx.scheduled_end + interval '2 hours 10 minutes',
    public.resolve_return_overdue_hourly_rate(
      ctx.rental_type,
      ctx.hourly_rate,
      ctx.price_per_hour,
      ctx.daily_overage_hourly_rate
    )
  ) as overage_calc
from ctx;

-- 기대값 (hourly_rate=10000): billedHours=3, amount=30000, rateMissing=false
