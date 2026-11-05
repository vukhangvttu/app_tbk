# Tao zip sach cua app_tbk (< 25MB) de up len Muse
# Cach dung: copy file nay vao thu muc goc project app_tbk (noi co pubspec.yaml),
# click phai -> Run with PowerShell, hoac chay: powershell -ExecutionPolicy Bypass -File .\tao_zip_app_tbk.ps1
# Ket qua: app_tbk_clean.zip nam ngay tren Desktop

$ErrorActionPreference = "Stop"
$src = $PSScriptRoot
if (-not (Test-Path (Join-Path $src "pubspec.yaml"))) {
    Write-Host "LOI: Khong thay pubspec.yaml. Hay copy script nay vao thu muc goc cua project app_tbk roi chay lai." -ForegroundColor Red
    pause; exit 1
}

$tmp = Join-Path $env:TEMP "app_tbk_clean_src"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null

# Chi copy source, bo het thu muc build/cache nang
$excludeDirs = @("build", ".dart_tool", ".gradle", ".git", ".idea", "Pods", ".symlinks", "ephemeral", ".kotlin", "DerivedData")
robocopy $src $tmp /E /XD $excludeDirs /XF "*.apk" "*.aab" "*.ipa" | Out-Null

$dest = Join-Path ([Environment]::GetFolderPath("Desktop")) "app_tbk_clean.zip"
if (Test-Path $dest) { Remove-Item $dest -Force }
Compress-Archive -Path "$tmp\*" -DestinationPath $dest -CompressionLevel Optimal

$sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 2)
Write-Host ""
Write-Host "XONG: $dest ($sizeMB MB)" -ForegroundColor Green
if ($sizeMB -lt 25) { Write-Host "Duoi 25MB - up truc tiep len chat duoc." -ForegroundColor Green }
else { Write-Host "Van tren 25MB - hay up file nay len Google Drive roi gui link cho Muse." -ForegroundColor Yellow }
Remove-Item $tmp -Recurse -Force
pause
