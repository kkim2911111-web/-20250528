-- ============================================================
-- vehicles 스키마 맞춤 + 테스트 데이터 (Supabase SQL Editor → Run)
-- ============================================================
-- 컬럼명이 제각각인 기존 테이블에도 동작하도록
-- "있는 컬럼만" INSERT / UPDATE 합니다.
-- ============================================================

-- 0) 앱 연동용 컬럼 추가 (없으면 생성)
alter table public.vehicles add column if not exists complex_id uuid references public.complexes(id);
alter table public.vehicles add column if not exists model_name text;
alter table public.vehicles add column if not exists vehicle_type text;
alter table public.vehicles add column if not exists car_type text;
alter table public.vehicles add column if not exists hourly_rate integer;
alter table public.vehicles add column if not exists price_per_hour integer;
alter table public.vehicles add column if not exists parking_location text;
alter table public.vehicles add column if not exists parking_spot text;
alter table public.vehicles add column if not exists parking_photo_url text;
alter table public.vehicles add column if not exists photo_url text;
alter table public.vehicles add column if not exists is_active boolean default true;
alter table public.vehicles add column if not exists is_available boolean default true;
alter table public.vehicles add column if not exists car_number text;

do $$
begin
  begin
    alter table public.vehicles alter column car_number drop not null;
  exception when others then
    null;
  end;
end $$;

-- 1) 테스트 차량 재삽입 (동적 SQL)
do $$
declare
  v_complex_id uuid;
  v_rec record;
  v_cols text;
  v_vals text;
  v_sql text;
begin
  select id into v_complex_id
  from public.complexes
  where invite_code = 'DANJI2026'
  limit 1;

  if v_complex_id is null then
    raise exception 'DANJI2026 단지가 없습니다. create_residents_table.sql을 먼저 실행하세요.';
  end if;

  -- 같은 단지 기존 테스트 차량 삭제
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'vehicles' and column_name = 'model_name'
  ) then
    delete from public.vehicles
    where complex_id = v_complex_id
      and model_name in ('BYD 아토3', '더 뉴 스타리아');
  else
    delete from public.vehicles where complex_id = v_complex_id;
  end if;

  for v_rec in
    select *
    from (values
      ('BYD 아토3', '전기 SUV', 8000, 'B1-12',
       'https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=800&q=80'),
      ('더 뉴 스타리아', 'MPV', 12000, 'B1-08',
       'https://images.unsplash.com/photo-1519641471654-76ce0107ad1b?w=800&q=80')
    ) as t(model_name, vehicle_type, hourly_rate, parking_location, parking_photo_url)
  loop
    v_cols := 'complex_id';
    v_vals := format('%L', v_complex_id);

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='model_name') then
      v_cols := v_cols || ', model_name';
      v_vals := v_vals || ', ' || quote_literal(v_rec.model_name);
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='hourly_rate') then
      v_cols := v_cols || ', hourly_rate';
      v_vals := v_vals || ', ' || v_rec.hourly_rate::text;
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='price_per_hour') then
      v_cols := v_cols || ', price_per_hour';
      v_vals := v_vals || ', ' || v_rec.hourly_rate::text;
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='is_active') then
      v_cols := v_cols || ', is_active';
      v_vals := v_vals || ', true';
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='is_available') then
      v_cols := v_cols || ', is_available';
      v_vals := v_vals || ', true';
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='car_number') then
      v_cols := v_cols || ', car_number';
      v_vals := v_vals || ', null';
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='vehicle_type') then
      v_cols := v_cols || ', vehicle_type';
      v_vals := v_vals || ', ' || quote_literal(v_rec.vehicle_type);
    elsif exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='car_type') then
      v_cols := v_cols || ', car_type';
      v_vals := v_vals || ', ' || quote_literal(v_rec.vehicle_type);
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='parking_location') then
      v_cols := v_cols || ', parking_location';
      v_vals := v_vals || ', ' || quote_literal(v_rec.parking_location);
    elsif exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='parking_spot') then
      v_cols := v_cols || ', parking_spot';
      v_vals := v_vals || ', ' || quote_literal(v_rec.parking_location);
    end if;

    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='parking_photo_url') then
      v_cols := v_cols || ', parking_photo_url';
      v_vals := v_vals || ', ' || quote_literal(v_rec.parking_photo_url);
    elsif exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='photo_url') then
      v_cols := v_cols || ', photo_url';
      v_vals := v_vals || ', ' || quote_literal(v_rec.parking_photo_url);
    end if;

    v_sql := format('insert into public.vehicles (%s) values (%s)', v_cols, v_vals);
    execute v_sql;
  end loop;
end $$;

-- 2) 확인 (주석 해제 후 실행)
-- select column_name, data_type, is_nullable
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'vehicles'
-- order by ordinal_position;
--
-- select * from public.vehicles
-- where complex_id in (select id from public.complexes where invite_code = 'DANJI2026');
