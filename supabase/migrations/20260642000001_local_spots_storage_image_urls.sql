-- ============================================================
-- local_spots image_url → Storage public URL
-- 프로젝트: knxkmngonkzchwelpdjn
-- ============================================================

update public.local_spots
set image_url = 'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EC%9C%A0%EC%A7%84%EC%8B%AC.jpg'
where name = '유진심';

update public.local_spots
set image_url = 'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EB%A7%88%EB%A0%88%ED%85%8C%EC%9D%B4%EB%B8%94.jpg'
where name = '마레테이블';

update public.local_spots
set image_url = 'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EC%9D%80%ED%96%89%EB%82%98%EB%AC%B4%EC%A7%91.jpg'
where name = '은행나무집';

update public.local_spots
set image_url = 'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EB%B6%81%ED%95%B4%EB%8F%84%EC%8A%A4%EC%9C%84%ED%8A%B8.jpg'
where name = '북해도스위트';
