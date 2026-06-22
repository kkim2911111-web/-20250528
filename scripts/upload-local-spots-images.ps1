# local_spots 시드 이미지 → Supabase Storage (local-spots-images)
# 사전: supabase login · 프로젝트 link · 버킷 마이그레이션 적용
#
# 사용:
#   .\scripts\upload-local-spots-images.ps1
#   .\scripts\upload-local-spots-images.ps1 -ProjectRef knxkmngonkzchwelpdjn

param(
  [string]$ProjectRef = 'knxkmngonkzchwelpdjn',
  [string]$SeedDir = 'assets/local_spots_seed'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$files = @(
  '유진심.jpg',
  '마레테이블.jpg',
  '은행나무집.jpg',
  '북해도스위트.jpg'
)

Write-Host "==> Storage 버킷 확인 (마이그레이션 미적용 시: supabase db push)"
foreach ($name in $files) {
  $local = Join-Path $SeedDir $name
  if (-not (Test-Path $local)) {
    throw "파일 없음: $local — 먼저 네이버 URL에서 다운로드하세요."
  }
  $dest = "ss://local-spots-images/$name"
  Write-Host "업로드: $name -> $dest"
  supabase storage cp $local $dest --experimental
}

Write-Host ""
Write-Host "==> DB image_url 업데이트 SQL (Supabase SQL Editor 또는 db push)"
Write-Host @"
update public.local_spots set image_url = 'https://$ProjectRef.supabase.co/storage/v1/object/public/local-spots-images/%EC%9C%A0%EC%A7%84%EC%8B%AC.jpg' where name = '유진심';
update public.local_spots set image_url = 'https://$ProjectRef.supabase.co/storage/v1/object/public/local-spots-images/%EB%A7%88%EB%A0%88%ED%85%8C%EC%9D%B4%EB%B8%94.jpg' where name = '마레테이블';
update public.local_spots set image_url = 'https://$ProjectRef.supabase.co/storage/v1/object/public/local-spots-images/%EC%9D%80%ED%96%89%EB%82%98%EB%AC%B4%EC%A7%91.jpg' where name = '은행나무집';
update public.local_spots set image_url = 'https://$ProjectRef.supabase.co/storage/v1/object/public/local-spots-images/%EB%B6%81%ED%95%B4%EB%8F%84%EC%8A%A4%EC%9C%84%ED%8A%B8.jpg' where name = '북해도스위트';
"@
