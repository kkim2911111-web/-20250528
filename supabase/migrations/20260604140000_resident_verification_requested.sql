-- 입주민 인증 신청 여부 (승인 대기 UI 분기)

alter table public.user_profiles
  add column if not exists resident_verification_requested boolean not null default false;

comment on column public.user_profiles.resident_verification_requested is
  '입주민(주민) 인증 신청 완료 여부 — 관리자 승인 전 true';

-- 기존 residents 등록자 백필
update public.user_profiles up
set resident_verification_requested = true,
    updated_at = now()
from public.residents r
where r.user_id = up.user_id;
