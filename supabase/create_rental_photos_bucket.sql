-- ============================================================
-- Supabase Storage: rental-photos 버킷 (퍼블릭 읽기)
-- Supabase SQL Editor → Run
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'rental-photos',
  'rental-photos',
  true,
  5242880, -- 5MB per file
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
set
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];

-- 본인 폴더(user_id/reservation_id/...)에만 업로드
drop policy if exists "rental_photos_insert_own" on storage.objects;
create policy "rental_photos_insert_own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'rental-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- 본인 폴더 파일만 수정·삭제
drop policy if exists "rental_photos_update_own" on storage.objects;
create policy "rental_photos_update_own"
on storage.objects for update to authenticated
using (
  bucket_id = 'rental-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "rental_photos_delete_own" on storage.objects;
create policy "rental_photos_delete_own"
on storage.objects for delete to authenticated
using (
  bucket_id = 'rental-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- 퍼블릭 버킷이므로 select는 anon/authenticated 모두 허용
drop policy if exists "rental_photos_select_public" on storage.objects;
create policy "rental_photos_select_public"
on storage.objects for select to public
using (bucket_id = 'rental-photos');
