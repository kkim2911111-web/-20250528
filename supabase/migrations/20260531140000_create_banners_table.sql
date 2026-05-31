-- ============================================================
-- 홈 화면 이벤트 배너
-- ============================================================

create table if not exists public.banners (
  id bigint generated always as identity primary key,
  sub_title text not null default '',
  main_title text not null default '',
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists banners_active_id_idx
  on public.banners (is_active, id)
  where is_active = true;

alter table public.banners enable row level security;

drop policy if exists "banners_select_active" on public.banners;
create policy "banners_select_active"
on public.banners
for select to authenticated
using (is_active = true);

comment on table public.banners is '홈 화면 하단 이벤트 배너';
comment on column public.banners.sub_title is '상단 작은 텍스트';
comment on column public.banners.main_title is '하단 큰 텍스트';
comment on column public.banners.description is '하단 설명 텍스트';

-- 초기 데이터 (중복 실행 방지)
insert into public.banners (sub_title, main_title, description, is_active)
select
  '카셰어링·렌트카 타러 이동하시나요?',
  '저는 엘리베이터만 타면 됩니다 🛗',
  '지역 밀착형 카셰어링 서비스',
  true
where not exists (
  select 1
  from public.banners
  where main_title = '저는 엘리베이터만 타면 됩니다 🛗'
);
