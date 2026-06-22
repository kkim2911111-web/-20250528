-- ============================================================
-- local_spots 이미지 — Supabase Storage (public read)
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'local-spots-images',
  'local-spots-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "local_spots_images_select_public" on storage.objects;
create policy "local_spots_images_select_public"
on storage.objects
for select
to public
using (bucket_id = 'local-spots-images');

-- 업로드·수정·삭제는 service_role (Dashboard / CLI / 서버 스크립트)
drop policy if exists "local_spots_images_insert_service" on storage.objects;
create policy "local_spots_images_insert_service"
on storage.objects
for insert
to service_role
with check (bucket_id = 'local-spots-images');

drop policy if exists "local_spots_images_update_service" on storage.objects;
create policy "local_spots_images_update_service"
on storage.objects
for update
to service_role
using (bucket_id = 'local-spots-images');

drop policy if exists "local_spots_images_delete_service" on storage.objects;
create policy "local_spots_images_delete_service"
on storage.objects
for delete
to service_role
using (bucket_id = 'local-spots-images');
