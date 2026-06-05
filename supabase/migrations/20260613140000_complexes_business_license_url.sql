-- complexes: 사업자등록증 이미지 URL + Storage 버킷 (staff 전용)

alter table public.complexes
  add column if not exists business_license_url text;

comment on column public.complexes.business_license_url is
  '사업자등록증 Storage URL (business-documents/{complex_id}/business_license.jpg)';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'business-documents',
  'business-documents',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];

drop policy if exists "business_documents_staff_select" on storage.objects;
create policy "business_documents_staff_select"
on storage.objects for select to authenticated
using (
  bucket_id = 'business-documents'
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id::text = (storage.foldername(name))[1]
  )
);

drop policy if exists "business_documents_staff_insert" on storage.objects;
create policy "business_documents_staff_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'business-documents'
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id::text = (storage.foldername(name))[1]
  )
);

drop policy if exists "business_documents_staff_update" on storage.objects;
create policy "business_documents_staff_update"
on storage.objects for update to authenticated
using (
  bucket_id = 'business-documents'
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id::text = (storage.foldername(name))[1]
  )
);

drop policy if exists "business_documents_staff_delete" on storage.objects;
create policy "business_documents_staff_delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'business-documents'
  and exists (
    select 1
    from public.staff_users s
    where s.user_id = auth.uid()
      and s.approved = true
      and s.complex_id::text = (storage.foldername(name))[1]
  )
);
