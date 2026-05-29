# Supabase Edge Functions 배포 (TOSS_SECRET_KEY 등 프로젝트 시크릿 자동 사용)
# 사용법:
#   1) supabase login   (또는 $env:SUPABASE_ACCESS_TOKEN 설정)
#   2) .\scripts\deploy-edge-functions.ps1

$ErrorActionPreference = "Stop"
$ProjectRef = "knxkmngonkzchwelpdjn"
$Root = Split-Path -Parent $PSScriptRoot

function Get-SupabaseCli {
    $local = Join-Path $env:TEMP "supabase-cli\supabase.exe"
    if (Test-Path $local) { return $local }

    $cmd = Get-Command supabase -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    Write-Host "Supabase CLI를 설치하는 중..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/supabase/cli/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -like "*windows_amd64*" } | Select-Object -First 1
    $tgz = Join-Path $env:TEMP "supabase_cli.tgz"
    $dest = Join-Path $env:TEMP "supabase-cli"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tgz
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest | Out-Null
    tar -xzf $tgz -C $dest
    return (Join-Path $dest "supabase.exe")
}

Push-Location $Root
try {
    $sb = Get-SupabaseCli
    Write-Host "==> 프로젝트 연결: $ProjectRef"
    & $sb link --project-ref $ProjectRef

    Write-Host "==> Edge Functions 배포 (기존 TOSS_SECRET_KEY / FIREBASE 시크릿 사용)"
    & $sb functions deploy payment-cancel --project-ref $ProjectRef
    & $sb functions deploy payment-confirm --project-ref $ProjectRef
    & $sb functions deploy reservation-cancel --project-ref $ProjectRef

    Write-Host ""
    Write-Host "완료. 등록된 시크릿 확인:"
    & $sb secrets list --project-ref $ProjectRef
}
finally {
    Pop-Location
}
