-- 대여 계약서 본문 (generate_rental_contract RPC가 저장)

alter table public.reservations
  add column if not exists contract_content text;

comment on column public.reservations.contract_content is '대여 계약서 전문 (결제 확정 후 생성)';
