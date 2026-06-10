-- 보험 만료 푸시: 갱신 전 매일 1회 (발송일 기록) · 갱신 시 플래그 초기화

alter table public.vehicles
  add column if not exists insurance_expired_push_sent_at date;

comment on column public.vehicles.insurance_expired_push_sent_at is
  '보험 만료 후 관리자 푸시 마지막 발송일(KST). 동일 일자 중복 발송 방지.';

create or replace function public.reset_vehicle_insurance_push_on_renewal()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_today date;
begin
  if NEW.insurance_expires_at is distinct from OLD.insurance_expires_at then
    v_today := (now() at time zone 'Asia/Seoul')::date;
    if NEW.insurance_expires_at is null
       or NEW.insurance_expires_at >= v_today then
      NEW.insurance_warn_7d_sent_at := null;
      NEW.insurance_expired_push_sent_at := null;
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists vehicles_insurance_renewal_reset on public.vehicles;

create trigger vehicles_insurance_renewal_reset
before update on public.vehicles
for each row
execute function public.reset_vehicle_insurance_push_on_renewal();

-- is_published 이후에도 보험 만료 차단 유지 확인 (RLS·예약 검사)
comment on policy "vehicles_resident_select_own_complex" on public.vehicles is
  '입주민 차량 — is_published·점검중·보험만료(만료일 당일까지 유효) 제외';
