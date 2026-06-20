-- 예약번호 채번 기준: 이용 시작월 → 예약 생성 시점(created_at) 연월
-- 1) 변경 전 매핑 백업 테이블
-- 2) 전체 예약번호 재계산 (created_at 순, 단지·연월별 1부터)
-- 3) 신규 INSERT 트리거도 created_at 기준

-- ── 0) 백업·롤백용 로그 테이블 (멱등) ───────────────────────────
create table if not exists public.reservation_number_change_log (
  id bigserial primary key,
  migration_batch text not null,
  reservation_id text not null,
  complex_id uuid,
  old_reservation_number text,
  new_reservation_number text,
  reservation_created_at timestamptz,
  recorded_at timestamptz not null default now()
);

create index if not exists reservation_number_change_log_batch_idx
  on public.reservation_number_change_log (migration_batch);

create index if not exists reservation_number_change_log_reservation_idx
  on public.reservation_number_change_log (reservation_id);

comment on table public.reservation_number_change_log is
  '예약번호 변경 이력 — reservation_number_rollback.sql 로 복구';

alter table public.reservation_number_change_log enable row level security;

revoke all on table public.reservation_number_change_log from public;
revoke all on table public.reservation_number_change_log from anon;
revoke all on table public.reservation_number_change_log from authenticated;
grant select, insert, update, delete on table public.reservation_number_change_log to service_role;

-- ── 1) 변경 전 스냅샷 백업 ─────────────────────────────────────
insert into public.reservation_number_change_log (
  migration_batch,
  reservation_id,
  complex_id,
  old_reservation_number,
  new_reservation_number,
  reservation_created_at
)
select
  'created_at_baseline_20260631900000',
  r.id::text,
  v.complex_id,
  r.reservation_number,
  null,
  r.created_at
from public.reservations r
join public.vehicles v on v.id = r.vehicle_id
join public.complexes c on c.id = v.complex_id
where c.short_code is not null
  and trim(c.short_code) <> ''
  and not exists (
    select 1
    from public.reservation_number_change_log l
    where l.migration_batch = 'created_at_baseline_20260631900000'
      and l.reservation_id = r.id::text
  );

-- ── 2) 유니크 충돌 방지 — 기존 번호 해제 후 재부여 ───────────────
update public.reservations r
set reservation_number = null
from public.vehicles v
join public.complexes c on c.id = v.complex_id
where r.vehicle_id = v.id
  and c.short_code is not null
  and trim(c.short_code) <> ''
  and r.reservation_number is not null;

with numbered as (
  select
    r.id,
    c.short_code,
    to_char(
      coalesce(r.created_at, r.updated_at, now()) at time zone 'Asia/Seoul',
      'YYMM'
    ) as yymm,
    row_number() over (
      partition by
        v.complex_id,
        to_char(
          coalesce(r.created_at, r.updated_at, now()) at time zone 'Asia/Seoul',
          'YYMM'
        )
      order by coalesce(r.created_at, r.updated_at, now()), r.id
    ) as seq
  from public.reservations r
  join public.vehicles v on v.id = r.vehicle_id
  join public.complexes c on c.id = v.complex_id
  where c.short_code is not null
    and trim(c.short_code) <> ''
)
update public.reservations r
set reservation_number =
  n.short_code || '-' || n.yymm || '-' || lpad(n.seq::text, 3, '0')
from numbered n
where r.id = n.id;

update public.reservation_number_change_log l
set new_reservation_number = r.reservation_number
from public.reservations r
where l.migration_batch = 'created_at_baseline_20260631900000'
  and l.reservation_id = r.id::text;

-- ── 3) 카운터 재동기화 ───────────────────────────────────────────
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

-- ── 4) 채번 함수 — created_at 연월 ─────────────────────────────
create or replace function public.allocate_reservation_number(
  p_complex_id uuid,
  p_reference_at timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_short text;
  v_yymm text;
  v_seq integer;
begin
  select nullif(trim(c.short_code), '')
  into v_short
  from public.complexes c
  where c.id = p_complex_id;

  if v_short is null then
    raise exception 'complex_short_code_missing';
  end if;

  v_yymm := to_char(
    coalesce(p_reference_at, now()) at time zone 'Asia/Seoul',
    'YYMM'
  );

  insert into public.reservation_number_counters as cnt (
    complex_id, year_month, last_seq
  )
  values (p_complex_id, v_yymm, 1)
  on conflict (complex_id, year_month)
  do update
    set last_seq = cnt.last_seq + 1
  returning last_seq into v_seq;

  return v_short || '-' || v_yymm || '-' || lpad(v_seq::text, 3, '0');
end;
$$;

comment on function public.allocate_reservation_number(uuid, timestamptz) is
  '예약번호 채번 — p_reference_at 은 예약 created_at (KST YYMM)';

-- ── 5) INSERT 트리거 — created_at 기준 ─────────────────────────
create or replace function public.reservations_set_reservation_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex_id uuid;
  v_ref timestamptz;
begin
  if NEW.reservation_number is not null and trim(NEW.reservation_number) <> '' then
    return NEW;
  end if;

  select v.complex_id
  into v_complex_id
  from public.vehicles v
  where v.id = NEW.vehicle_id;

  if v_complex_id is null then
    raise exception 'vehicle_not_found';
  end if;

  v_ref := coalesce(NEW.created_at, now());
  NEW.reservation_number :=
    public.allocate_reservation_number(v_complex_id, v_ref);
  return NEW;
end;
$$;

comment on column public.reservations.reservation_number is
  '표시용 예약번호 — {short_code}-{YYMM}-{순번3자리}, YYMM=created_at(KST)';
