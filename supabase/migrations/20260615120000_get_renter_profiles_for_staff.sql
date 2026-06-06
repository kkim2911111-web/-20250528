-- 관리자: 예약 임차인 표시명 조회 (full_name + auth.users 이메일 fallback)

create or replace function public.get_renter_profiles_for_staff(p_user_ids uuid[])
returns table (
  user_id uuid,
  full_name text,
  email text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if v_staff is null then
    raise exception 'not_authenticated';
  end if;

  if p_user_ids is null or cardinality(p_user_ids) < 1 then
    return;
  end if;

  return query
  select
    ids.user_id,
    nullif(trim(p.full_name), '') as full_name,
    coalesce(
      nullif(trim(p.email), ''),
      nullif(trim(u.email::text), '')
    ) as email
  from unnest(p_user_ids) as ids(user_id)
  left join public.user_profiles p on p.user_id = ids.user_id
  left join auth.users u on u.id = ids.user_id
  where exists (
    select 1
    from public.staff_users s
    where s.user_id = v_staff
      and s.approved = true
      and (
        exists (
          select 1
          from public.residents r
          where r.user_id = ids.user_id
            and r.complex_id = s.complex_id
        )
        or exists (
          select 1
          from public.reservations res
          join public.vehicles v on v.id = res.vehicle_id
          where res.user_id = ids.user_id
            and v.complex_id = s.complex_id
        )
      )
  );
end;
$$;

revoke all on function public.get_renter_profiles_for_staff(uuid[]) from public;
grant execute on function public.get_renter_profiles_for_staff(uuid[]) to authenticated;
