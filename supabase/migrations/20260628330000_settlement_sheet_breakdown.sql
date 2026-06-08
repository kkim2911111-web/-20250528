-- 정산 상세 바텀시트 — 총결제/취소환불/순매출 (기존 뷰·테이블 조회만)

drop function if exists public.get_super_admin_settlement_reservations(uuid, integer, integer);

create function public.get_super_admin_settlement_reservations(
  p_complex_id uuid,
  p_year integer default null,
  p_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_total_paid bigint := 0;
  v_cancel_refund bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_has_refund_col boolean := false;
  v_has_cancelled_at_col boolean := false;
begin
  perform public.assert_is_super_admin();

  if p_complex_id is null then
    raise exception 'complex_id_required';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Asia/Seoul')::integer);
  v_month := coalesce(p_month, extract(month from now() at time zone 'Asia/Seoul')::integer);
  select b.period_start, b.period_end
  into v_period_start, v_period_end
  from public.sales_month_bounds(v_year, v_month) as b;

  v_total_paid := public.sales_total_revenue(
    p_complex_id, v_period_start, v_period_end
  );

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'refund_amount'
  )
  into v_has_refund_col;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'cancelled_at'
  )
  into v_has_cancelled_at_col;

  if v_has_refund_col then
    if v_has_cancelled_at_col then
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and coalesce(r.cancelled_at, r.updated_at) >= $2
          and coalesce(r.cancelled_at, r.updated_at) < $3
      $sql$
      into v_cancel_refund
      using p_complex_id, v_period_start, v_period_end;
    else
      execute $sql$
        select coalesce(sum(coalesce(r.refund_amount, r.total_price, 0)), 0)::bigint
        from public.reservations r
        join public.vehicles v on v.id = r.vehicle_id
        where v.complex_id = $1
          and r.status = 'cancelled'
          and r.updated_at >= $2
          and r.updated_at < $3
      $sql$
      into v_cancel_refund
      using p_complex_id, v_period_start, v_period_end;
    end if;
  else
    if v_has_cancelled_at_col then
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_cancel_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and coalesce(r.cancelled_at, r.updated_at) >= v_period_start
        and coalesce(r.cancelled_at, r.updated_at) < v_period_end;
    else
      select coalesce(sum(coalesce(r.total_price, 0)), 0)::bigint
      into v_cancel_refund
      from public.reservations r
      join public.vehicles v on v.id = r.vehicle_id
      where v.complex_id = p_complex_id
        and r.status = 'cancelled'
        and r.updated_at >= v_period_start
        and r.updated_at < v_period_end;
    end if;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', s.reservation_id_text,
        'renter_name', coalesce(
          nullif(trim(up.full_name), ''),
          nullif(split_part(nullif(trim(up.email), ''), '@', 1), ''),
          '이름 미등록'
        ),
        'total_price', coalesce(s.gross_amount, 0),
        'start_at', s.start_at,
        'end_at', s.end_at,
        'rental_started_at', s.rental_started_at,
        'returned_at', s.returned_at,
        'actual_end_at', s.actual_end_at
      )
      order by s.return_completed_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.sales_completed_reservations_v s
  left join public.user_profiles up on up.user_id = s.user_id
  where s.complex_id = p_complex_id
    and s.return_completed_at >= v_period_start
    and s.return_completed_at < v_period_end;

  return jsonb_build_object(
    'total_paid', coalesce(v_total_paid, 0),
    'cancel_refund', coalesce(v_cancel_refund, 0),
    'net_revenue', coalesce(v_total_paid, 0) - coalesce(v_cancel_refund, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_super_admin_settlement_reservations(uuid, integer, integer) from public;
grant execute on function public.get_super_admin_settlement_reservations(uuid, integer, integer) to authenticated;

comment on function public.get_super_admin_settlement_reservations(uuid, integer, integer) is
  '정산 상세 — total_paid(sales_total_revenue), cancel_refund(cancelled·refund_amount), items(sales_completed_reservations_v)';
