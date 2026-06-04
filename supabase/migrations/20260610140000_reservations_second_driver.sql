-- 제2운전자 · 결제 전 동의 시 payment_orders 임시 저장

alter table public.reservations
  add column if not exists second_driver_name text;

alter table public.reservations
  add column if not exists second_driver_license text;

alter table public.payment_orders
  add column if not exists second_driver_name text;

alter table public.payment_orders
  add column if not exists second_driver_license text;

comment on column public.reservations.second_driver_name is '제2운전자 성명';
comment on column public.reservations.second_driver_license is '제2운전자 면허번호';
