-- in_use 미반납도 end_at+30분 버퍼 이후 시간대는 신규 예약 가능 (무기한 점유 해제)

create or replace function public.reservation_effective_end(
  p_status text,
  p_end timestamptz,
  p_actual_end timestamptz,
  p_returned_at timestamptz
)
returns timestamptz
language sql
stable
as $$
  select case
    when lower(trim(coalesce(p_status, ''))) = 'in_use' then
      coalesce(
        coalesce(p_end, p_actual_end) + interval '30 minutes',
        'infinity'::timestamptz
      )
    when lower(trim(coalesce(p_status, ''))) in ('returned', 'completed', 'cancelled') then
      coalesce(p_actual_end, p_returned_at, p_end) + interval '30 minutes'
    else
      p_end + interval '30 minutes'
  end;
$$;

comment on function public.reservation_effective_end(text, timestamptz, timestamptz, timestamptz) is
  '겹침 검사용 실효 종료. in_use·confirmed 등 모두 종료+30분 버퍼(in_use는 end_at 기준).';
