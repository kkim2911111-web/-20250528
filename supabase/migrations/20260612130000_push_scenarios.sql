-- FCM 시나리오: 입주민 심사 RPC + 리마인더 로그

create table if not exists public.push_reminder_log (
  id uuid primary key default gen_random_uuid(),
  reservation_id text not null,
  scenario text not null,
  sent_at timestamptz not null default now(),
  unique (reservation_id, scenario)
);

create index if not exists push_reminder_log_reservation_idx
  on public.push_reminder_log (reservation_id);

alter table public.push_reminder_log enable row level security;

-- 서비스 롤만 사용 (Edge Function)

-- 입주민 인증 심사 목록 (관리자)
create or replace function public.list_resident_reviews_for_staff()
returns table (
  user_id uuid,
  full_name text,
  building text,
  unit text,
  requested_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex uuid;
begin
  select s.complex_id into v_complex
  from public.staff_users s
  where s.user_id = auth.uid() and s.approved = true;

  if v_complex is null then
    raise exception 'not_staff';
  end if;

  return query
  select
    r.user_id,
    coalesce(p.full_name, p.email, '입주민') as full_name,
    r.building,
    r.unit,
    coalesce(r.updated_at, r.created_at) as requested_at
  from public.residents r
  left join public.user_profiles p on p.user_id = r.user_id
  where r.complex_id = v_complex
    and r.approved = false
    and coalesce(p.resident_verification_requested, false) = true
  order by requested_at desc nulls last;
end;
$$;

revoke all on function public.list_resident_reviews_for_staff() from public;
grant execute on function public.list_resident_reviews_for_staff() to authenticated;

-- 입주민 인증 승인/거절 (관리자)
create or replace function public.review_resident_for_staff(
  p_user_id uuid,
  p_approved boolean,
  p_rejection_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complex uuid;
begin
  select s.complex_id into v_complex
  from public.staff_users s
  where s.user_id = auth.uid() and s.approved = true;

  if v_complex is null then
    raise exception 'not_staff';
  end if;

  if p_user_id is null then
    raise exception 'invalid_user';
  end if;

  if not exists (
    select 1 from public.residents r
    where r.user_id = p_user_id and r.complex_id = v_complex
  ) then
    raise exception 'resident_not_found';
  end if;

  update public.residents
  set approved = p_approved,
      updated_at = now()
  where user_id = p_user_id
    and complex_id = v_complex;

  if p_approved then
    update public.user_profiles
    set resident_verification_requested = false,
        updated_at = now()
    where user_id = p_user_id;
  end if;
end;
$$;

revoke all on function public.review_resident_for_staff(uuid, boolean, text) from public;
grant execute on function public.review_resident_for_staff(uuid, boolean, text) to authenticated;
