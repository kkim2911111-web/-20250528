-- photos_uploaded UPDATE RLS 진단 (Supabase SQL Editor)
-- :reservation_id 를 실제 예약 id 로 바꿔 실행

-- 1) 컬럼 존재
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'reservations'
  and column_name in ('photos_uploaded', 'pickup_photos', 'user_id', 'id');

-- 2) 현재 값
select id, user_id, status, photos_uploaded,
       coalesce(cardinality(pickup_photos), 0) as pickup_count
from public.reservations
where id = :reservation_id;  -- bigint면 숫자, uuid면 따옴표

-- 3) UPDATE RLS 정책
select polname, polcmd, pg_get_expr(polqual, polrelid) as using_expr,
       pg_get_expr(polwithcheck, polrelid) as with_check_expr
from pg_policy
where polrelid = 'public.reservations'::regclass
  and polcmd in ('w', '*');  -- update

-- 4) 본인 예약 UPDATE 정책 없으면 추가 (SQL Editor — service role)
-- drop policy if exists "reservations_update_own" on public.reservations;
-- create policy "reservations_update_own"
-- on public.reservations for update to authenticated
-- using (user_id = auth.uid())
-- with check (user_id = auth.uid());
