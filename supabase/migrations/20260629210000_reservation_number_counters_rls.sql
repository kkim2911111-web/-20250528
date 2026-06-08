-- reservation_number_counters — RLS 활성화, service_role 전용

revoke all on table public.reservation_number_counters from public;
revoke all on table public.reservation_number_counters from anon;
revoke all on table public.reservation_number_counters from authenticated;

grant all on table public.reservation_number_counters to service_role;

alter table public.reservation_number_counters enable row level security;

comment on table public.reservation_number_counters is
  '예약번호 단지·월별 순번 — RLS 활성, service_role 및 security definer RPC만 접근';
