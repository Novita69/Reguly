<#
  frun.ps1
  Wrapper untuk "flutter run" supaya otomatis menyertakan
  --dart-define-from-file=dart_define.json

  CARA PAKAI (taruh file ini di root project, sejajar pubspec.yaml):

    .\frun.ps1                  -> flutter run (device default)
    .\frun.ps1 chrome           -> flutter run -d chrome
    .\frun.ps1 192.168.1.5:5555 -> flutter run -d 192.168.1.5:5555
    .\frun.ps1 -build apk       -> flutter build apk
    .\frun.ps1 -build appbundle -> flutter build appbundle
#>

param(
    [Parameter(Position = 0)]
    [string]$Device,

    [string]$Build
)

$DefineFile = "dart_define.json"

# Cek apakah dart_define.json ada
if (-not (Test-Path $DefineFile)) {
    Write-Host "File '$DefineFile' tidak ditemukan di folder ini." -ForegroundColor Red
    Write-Host "Buat dulu file itu di root project (isi SUPABASE_URL & SUPABASE_ANON_KEY)." -ForegroundColor Yellow
    exit 1
}

if ($Build) {
    Write-Host "Menjalankan: flutter build $Build --dart-define-from-file=$DefineFile" -ForegroundColor Cyan
    flutter build $Build --dart-define-from-file=$DefineFile
}
elseif ($Device) {
    Write-Host "Menjalankan: flutter run -d $Device --dart-define-from-file=$DefineFile" -ForegroundColor Cyan
    flutter run -d $Device --dart-define-from-file=$DefineFile
}
else {
    Write-Host "Menjalankan: flutter run --dart-define-from-file=$DefineFile" -ForegroundColor Cyan
    flutter run --dart-define-from-file=$DefineFile
}
