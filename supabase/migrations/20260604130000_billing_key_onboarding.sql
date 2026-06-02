-- 온보딩: 빌링키 저장 + 진행 단계 (결제 실패 시 단계 유지)

alter table public.user_profiles
  add column if not exists toss_billing_key text;

alter table public.user_profiles
  add column if not exists onboarding_step integer not null default 0;

comment on column public.user_profiles.toss_billing_key is
  '토스페이먼츠 빌링키 (자동결제용)';

comment on column public.user_profiles.onboarding_step is
  '회원가입 위저드 진행 단계 0~4 (입주민~완료직전), 뒤로가지 않음';
