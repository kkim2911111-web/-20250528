-- 예약번호 created_at 기준 마이그레이션 롤백
-- 선행: reservation_number_change_log 에
--       migration_batch = 'created_at_baseline_20260631900000' 백업이 있어야 함
--
-- Supabase SQL Editor에서 실행

begin;

-- 1) 번호 해제 (유니크 충돌 방지)
update public.reservations r
set reservation_number = null
where exists (
  select 1
  from public.reservation_number_change_log l
  where l.migration_batch = 'created_at_baseline_20260631900000'
    and l.reservation_id = r.id::text
    and l.old_reservation_number is not null
);

-- 2) 백업 값 복원
update public.reservations r
set reservation_number = l.old_reservation_number
from public.reservation_number_change_log l
where l.migration_batch = 'created_at_baseline_20260631900000'
  and l.reservation_id = r.id::text
  and l.old_reservation_number is not null
  and trim(l.old_reservation_number) <> '';

-- 3) 카운터 재동기화 (복원된 번호 기준)
delete from public.reservation_number_counters;

insert into public.reservation_number_counters (complex_id, year_month, last_seq)
select
  v.complex_id,
  split_part(r.reservation_number, '-', 2) as yymm,
  max(split_part(r.reservation_number, '-', 3)::integer) as max_seq
from public.reservations r
join public.vehicles v on v.id = r.vehicle_id
where r.reservation_number is not null
  and r.reservation_number ~ '^[A-Z]+-[0-9]{4}-[0-9]{3}$'
group by v.complex_id, split_part(r.reservation_number, '-', 2);

-- 4) 트리거 — 이용 시작월 기준으로 되돌리려면 아래 주석 해제 후 commit
-- create or replace function public.reservations_set_reservation_number() ...

commit;

-- 롤백 후 검증:
-- select count(*) from reservation_number_change_log
--   where migration_batch = 'created_at_baseline_20260631900000';
-- select reservation_id, old_reservation_number, new_reservation_number
--   from reservation_number_change_log
--   where migration_batch = 'created_at_baseline_20260631900000'
--   and old_reservation_number is distinct from new_reservation_number
--   limit 20;
