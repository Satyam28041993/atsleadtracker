# Builds Flutter web and prepares atsleadtracker-web-upload for Hostinger.
# Patches service worker off + cache-busting version id.
# Usage: .\scripts\prepare_hostinger_upload.ps1
#        .\scripts\prepare_hostinger_upload.ps1 -SkipApk

param(
  [switch]$SkipApk
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$BuildId = Get-Date -Format 'yyyyMMddHHmmss'
Write-Host "Building web (build_id=$BuildId)..."

flutter pub get
flutter build web --release --base-href=/atscrm/ --pwa-strategy=none
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$BuildDir = Join-Path $Root 'build\web'
$UploadDir = Join-Path $Root 'atsleadtracker-web-upload'
$HtaccessSrc = Join-Path $PSScriptRoot 'hostinger.htaccess'

if (Test-Path $UploadDir) {
  Remove-Item $UploadDir -Recurse -Force
}
Copy-Item $BuildDir $UploadDir -Recurse
Copy-Item $HtaccessSrc (Join-Path $UploadDir '.htaccess') -Force

# version.json with unique build_id so browsers detect new deploy
$AppVersion = '1.0.0'
$BuildNumber = '1'
$PubspecPath = Join-Path $Root 'pubspec.yaml'
if (Test-Path $PubspecPath) {
  $Pubspec = Get-Content $PubspecPath -Raw
  if ($Pubspec -match 'version:\s*([^\s+]+)\+(\d+)') {
    $AppVersion = $Matches[1]
    $BuildNumber = $Matches[2]
  }
}
$VersionPath = Join-Path $UploadDir 'version.json'
@{
  app_name = 'atsleadtracker'
  version = $AppVersion
  build_number = $BuildNumber
  build_id = $BuildId
  package_name = 'atsleadtracker'
} | ConvertTo-Json | Set-Content $VersionPath

Set-Content -Path (Join-Path $UploadDir '.last_build_id') -Value $BuildId

# Disable service worker registration in flutter_bootstrap.js
$BootstrapPath = Join-Path $UploadDir 'flutter_bootstrap.js'
$Bootstrap = Get-Content $BootstrapPath -Raw
$Bootstrap = $Bootstrap -replace '_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[0-9]+"\s*\}\s*\}\);', '_flutter.loader.load({});'
$Bootstrap = $Bootstrap -replace '"mainJsPath":"main\.dart\.js"', "`"mainJsPath`":`"main.dart.js?v=$BuildId`""
Set-Content $BootstrapPath $Bootstrap -NoNewline
$Bootstrap = Get-Content $BootstrapPath -Raw

# Cache-bust bootstrap + manifest in index.html
$IndexPath = Join-Path $UploadDir 'index.html'
$Index = Get-Content $IndexPath -Raw
$Index = $Index -replace 'src="flutter_bootstrap\.js[^"]*"', "src=`"flutter_bootstrap.js?v=$BuildId`""
$Index = $Index -replace 'href="manifest\.json[^"]*"', "href=`"manifest.json?v=$BuildId`""
Set-Content $IndexPath $Index -NoNewline

# Verify
$SwPath = Join-Path $UploadDir 'flutter_service_worker.js'
if (Test-Path $SwPath) {
  Remove-Item $SwPath -Force
  Write-Host 'Removed stray flutter_service_worker.js'
}
if ($Bootstrap -notmatch '_flutter\.loader\.load\(\{\}\);') {
  Write-Warning 'flutter_bootstrap.js loader patch failed'
  exit 1
}
if ($Bootstrap -notmatch "main\.dart\.js\?v=$BuildId") {
  Write-Warning 'main.dart.js cache-bust patch failed'
  exit 1
}

@'
HOSTINGER UPLOAD — ATS CRM (Flutter Web)
======================================

Upload EVERYTHING inside this folder to:
  public_html/atscrm/

Important:
  - Include hidden file: .htaccess
  - Overwrite old files when uploading
  - URL will be: https://YOUR-DOMAIN/atscrm/

After upload (Hostinger hPanel):
  1. LiteSpeed Cache → Purge All (if enabled)
  2. Open site and press normal F5 refresh

Auto-update on refresh:
  - version.json gets a new build_id each build
  - index.html clears old service workers + cache
  - main.dart.js loads with ?v=BUILD_ID query

Rebuild this folder anytime:
  powershell -File scripts\prepare_hostinger_upload.ps1
'@ | Set-Content (Join-Path $UploadDir 'HOSTINGER_UPLOAD.txt')

if (-not $SkipApk) {
  Write-Host ""
  Write-Host "Building Android APK..."
  flutter build apk --release
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  $ApkSrc = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
  $ApkDir = Join-Path $Root 'atsleadtracker-apk-upload'
  if (Test-Path $ApkDir) { Remove-Item $ApkDir -Recurse -Force }
  New-Item -ItemType Directory -Path $ApkDir | Out-Null
  $ApkDest = Join-Path $ApkDir "ats_crm_v${AppVersion}_${BuildId}.apk"
  Copy-Item $ApkSrc $ApkDest
  Write-Host "Ready (apk):  $ApkDest"
}

Write-Host ""
Write-Host "Ready (web): $UploadDir"
Write-Host "build_id: $BuildId"
Write-Host "Upload ALL files to public_html/atscrm/ (include .htaccess)"
