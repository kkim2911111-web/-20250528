-- billing_charge_retries.charge_type: 반납지연 초과요금 'overdue_overage' 분리
-- (연장하기 재시도는 'extension' 유지)

-- ── 1) CHECK 제약 — overdue_overage 추가 (백필 전에 선행) ───────
alter table public.billing_charge_retries
  drop constraint if exists billing_charge_retries_charge_type_check;

alter table public.billing_charge_retries
  add constraint billing_charge_retries_charge_type_check
  check (charge_type in ('deductible', 'extension', 'overdue_overage'));

comment on column public.billing_charge_retries.charge_type is
  'deductible=면책금, extension=대여 연장(연장하기), overdue_overage=반납지연 초과이용요금';

-- ── 2) 기존 반납지연 초과요금 행만 마이그레이션 ─────────────────
-- extension_hours 단독 조건은 연장하기 재시도와 겹치므로 사용하지 않음.
-- reservations.overdue_overage_amount 와 금액·시간이 일치하는 행만 대상.
do $$
declare
  v_migrated integer;
begin
  update public.billing_charge_retries b
  set
    charge_type = 'overdue_overage',
    updated_at = now()
  from public.reservations r
  where b.charge_type = 'extension'
    and r.id::text = b.reservation_id
    and coalesce(r.overdue_overage_amount, 0) > 0
    and b.amount = r.overdue_overage_amount
    and (
      r.overdue_overage_hours is null
      or b.extension_hours = r.overdue_overage_hours
    );

  get diagnostics v_migrated = row_count;
  raise notice 'billing_charge_retries migrated to overdue_overage: % rows', v_migrated;
end;
$$;

-- ── 3) enqueue_overdue_overage_billing ───────────────────────────
create or replace function public.enqueue_overdue_overage_billing(
  p_reservation_id text,
  p_user_id uuid,
  p_complex_id uuid,
  p_amount integer,
  p_billed_hours integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_amount is null or p_amount <= 0 then
    return;
  end if;

  if p_billed_hours is null or p_billed_hours < 1 then
    return;
  end if;

  if exists (
    select 1
    from public.billing_charge_retries b
    where b.charge_type = 'overdue_overage'
      and b.reservation_id = p_reservation_id
      and coalesce(b.extension_hours, 0) = p_billed_hours
      and b.status = 'pending'
  ) then
    update public.billing_charge_retries b
    set
      amount = p_amount,
      complex_id = p_complex_id,
      next_retry_at = now() + interval '1 hour',
      updated_at = now()
    where b.charge_type = 'overdue_overage'
      and b.reservation_id = p_reservation_id
      and coalesce(b.extension_hours, 0) = p_billed_hours
      and b.status = 'pending';
    return;
  end if;

  insert into public.billing_charge_retries (
    charge_type,
    reservation_id,
    user_id,
    complex_id,
    amount,
    extension_hours,
    retry_count,
    max_retries,
    next_retry_at,
    status
  )
  values (
    'overdue_overage',
    p_reservation_id,
    p_user_id,
    p_complex_id,
    p_amount,
    p_billed_hours,
    0,
    3,
    now() + interval '1 hour',
    'pending'
  );
end;
$$;

comment on function public.enqueue_overdue_overage_billing(
  text, uuid, uuid, integer, integer
) is
  '반납 지연 초과요금 결제 재시도 큐 (charge_type=overdue_overage). extension_hours=청구 시간(올림).';

revoke all on function public.enqueue_overdue_overage_billing(
  text, uuid, uuid, integer, integer
) from public;
grant execute on function public.enqueue_overdue_overage_billing(
  text, uuid, uuid, integer, integer
) to service_role;
