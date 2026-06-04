-- complexes: 단지 사업자 정보 (관리자 단지 정보 화면·계약서 임대인)
alter table public.complexes
  add column if not exists business_name text;

alter table public.complexes
  add column if not exists business_registration_number text;

alter table public.complexes
  add column if not exists business_address text;

alter table public.complexes
  add column if not exists business_representative text;

alter table public.complexes
  add column if not exists business_phone text;

comment on column public.complexes.business_name is '업체명(계약서 임대인 표시)';
comment on column public.complexes.business_registration_number is '사업자등록번호';
comment on column public.complexes.business_address is '사업장 주소';
comment on column public.complexes.business_representative is '대표자명';
comment on column public.complexes.business_phone is '대표 전화';

-- 관리자: 본인 단지 complexes 사업자 정보 수정
drop policy if exists "complexes_update_own_staff" on public.complexes;
create policy "complexes_update_own_staff"
on public.complexes
for update
to authenticated
using (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.complex_id = complexes.id
  )
)
with check (
  exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.complex_id = complexes.id
  )
);
