-- ============================================================
-- 홈 화면 — 우리동네 맛집 (local_spots)
-- anon/authenticated: SELECT only · INSERT/UPDATE/DELETE: service_role
-- ============================================================

create table if not exists public.local_spots (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  short_name text not null,
  description text not null default '',
  image_url text not null default '',
  rating numeric(2, 1) not null default 0,
  tags text[] not null default '{}',
  distance_text text not null default '',
  is_featured boolean not null default false,
  phone_number text,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists local_spots_sort_order_idx
  on public.local_spots (sort_order, created_at);

comment on table public.local_spots is '홈 우리동네 맛집 카드 데이터';
comment on column public.local_spots.short_name is '카드 표시용 짧은 가게명';
comment on column public.local_spots.distance_text is '거리·이동시간 (예: 도보 5분)';

alter table public.local_spots enable row level security;

drop policy if exists "local_spots_select_anon" on public.local_spots;
create policy "local_spots_select_anon"
on public.local_spots
for select
to anon
using (true);

drop policy if exists "local_spots_select_authenticated" on public.local_spots;
create policy "local_spots_select_authenticated"
on public.local_spots
for select
to authenticated
using (true);

revoke all on table public.local_spots from anon, authenticated;
grant select on table public.local_spots to anon, authenticated;
grant all on table public.local_spots to service_role;

-- 초기 데이터 (중복 실행 방지)
insert into public.local_spots (
  name,
  short_name,
  description,
  image_url,
  rating,
  tags,
  distance_text,
  is_featured,
  sort_order
)
select
  v.name,
  v.short_name,
  v.description,
  v.image_url,
  v.rating,
  v.tags,
  v.distance_text,
  v.is_featured,
  v.sort_order
from (
  values
    (
      '유진심',
      '유진심',
      '해물찜·현지인맛집',
      'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EC%9C%A0%EC%A7%84%EC%8B%AC.jpg',
      4.9::numeric(2, 1),
      array['해물찜', '현지인맛집']::text[],
      '도보 5분',
      true,
      1
    ),
    (
      '마레테이블',
      '마레테이블',
      '오션뷰·데이트',
      'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EB%A7%88%EB%A0%88%ED%85%8C%EC%9D%B4%EB%B8%94.jpg',
      4.8::numeric(2, 1),
      array['오션뷰', '데이트']::text[],
      '차량 8분',
      false,
      2
    ),
    (
      '은행나무집',
      '은행나무집',
      '굴밥·30년전통',
      'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EC%9D%80%ED%96%89%EB%82%98%EB%AC%B4%EC%A7%91.jpg',
      5.0::numeric(2, 1),
      array['굴밥', '30년전통']::text[],
      '도보 12분',
      false,
      3
    ),
    (
      '북해도스위트',
      '북해도스위트',
      '카페·디저트',
      'https://knxkmngonkzchwelpdjn.supabase.co/storage/v1/object/public/local-spots-images/%EB%B6%81%ED%95%B4%EB%8F%84%EC%8A%A4%EC%9C%84%ED%8A%B8.jpg',
      4.7::numeric(2, 1),
      array['카페', '디저트']::text[],
      '도보 8분',
      false,
      4
    )
) as v(
  name,
  short_name,
  description,
  image_url,
  rating,
  tags,
  distance_text,
  is_featured,
  sort_order
)
where not exists (
  select 1
  from public.local_spots ls
  where ls.name = v.name
);
