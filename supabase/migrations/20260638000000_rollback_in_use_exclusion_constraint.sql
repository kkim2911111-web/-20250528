-- 응급 롤백: 20260636000000 infinity 기반 exclude가 순차 confirmed 예약의 in_use(문열림) 전환을 막음.
-- reservation_effective_end(infinity) + reservations_overlap_exists는 유지 — 신규 예약·결제 겹침만 RPC에서 차단.

alter table public.reservations
  drop constraint if exists reservations_no_overlap_active;

-- 20260601150000과 동일: 예약 시간(end_at) 기준 exclude. in_use도 스케줄 종료 시각까지만 DB 점유.
alter table public.reservations
  add constraint reservations_no_overlap_active
  exclude using gist (
    vehicle_id with =,
    tstzrange(
      coalesce(start_at, start_time),
      coalesce(end_at, end_time),
      '[)'
    ) with &&
  )
  where (status in ('pending', 'confirmed', 'in_use'));

comment on constraint reservations_no_overlap_active on public.reservations is
  'active 예약끼리 시간 겹침 방지(스케줄 end_at 기준). in_use 미반납 연장 점유는 reservations_overlap_exists·앱에서 처리.';
