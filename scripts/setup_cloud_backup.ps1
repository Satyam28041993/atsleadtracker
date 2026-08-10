# One-time setup for automatic Firestore backups (every 3 days).
# Requires: Firebase Blaze plan, Firebase CLI, Google Cloud SDK (gcloud).

$ErrorActionPreference = "Stop"
$ProjectId = "atsleadtracker"
$BucketName = "atsleadtracker-firestore-backups"
$Region = "asia-south1"

Write-Host "=== ATS Lead Tracker - Cloud Backup Setup ===" -ForegroundColor Cyan
Write-Host "Project: $ProjectId"
Write-Host "Bucket:  gs://$BucketName"
Write-Host ""

Write-Host "[1/5] Setting active GCP project..." -ForegroundColor Yellow
gcloud config set project $ProjectId

Write-Host "[2/5] Enabling required APIs..." -ForegroundColor Yellow
gcloud services enable firestore.googleapis.com cloudfunctions.googleapis.com cloudscheduler.googleapis.com storage.googleapis.com

Write-Host "[3/5] Creating Cloud Storage bucket (skip if already exists)..." -ForegroundColor Yellow
$bucketExists = gsutil ls -b "gs://$BucketName" 2>$null
if (-not $bucketExists) {
  gsutil mb -p $ProjectId -l $Region "gs://$BucketName"
  Write-Host "Bucket created." -ForegroundColor Green
} else {
  Write-Host "Bucket already exists." -ForegroundColor Green
}

Write-Host "[4/5] Installing function dependencies..." -ForegroundColor Yellow
Push-Location "$PSScriptRoot\..\functions"
npm install
Pop-Location

Write-Host "[5/5] Deploying scheduled backup function..." -ForegroundColor Yellow
Push-Location "$PSScriptRoot\.."
firebase deploy --only functions:scheduledFirestoreBackup
Pop-Location

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Green
Write-Host "Backups will run every 3 days at 3:00 AM IST."
Write-Host "Storage path: gs://$BucketName/automatic/"
Write-Host "Check status in app: Settings -> Automatic Cloud Backup"
Write-Host ""
Write-Host "To download a backup:" -ForegroundColor Cyan
Write-Host "  Google Cloud Console -> Storage -> $BucketName -> automatic -> latest folder"
Write-Host ""
Write-Host "To restore full database (admin only):" -ForegroundColor Cyan
Write-Host "  gcloud firestore import gs://$BucketName/automatic/FOLDER_NAME"
