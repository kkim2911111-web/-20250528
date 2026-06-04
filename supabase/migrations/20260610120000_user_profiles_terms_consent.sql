-- 회원가입 약관·마케팅 동의 시각

alter table public.user_profiles
  add column if not exists terms_agreed_at timestamptz;

alter table public.user_profiles
  add column if not exists privacy_agreed_at timestamptz;

alter table public.user_profiles
  add column if not exists marketing_agreed_at timestamptz;

comment on column public.user_profiles.terms_agreed_at is '이용약관 동의 시각';
comment on column public.user_profiles.privacy_agreed_at is '개인정보 처리방침 동의 시각';
comment on column public.user_profiles.marketing_agreed_at is '마케팅 수신 동의 시각 (미동의 시 null)';
