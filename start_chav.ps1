Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "          Starting CHAV Telehealth System          " -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$root = $PSScriptRoot

if (Test-Path "$root\livekit_server") {
    $livekitDir = "$root\livekit_server"
    $nodeDir = "$root\LiveKitApp"
    $flutterDir = "$root\Audio-video_calling"
} else {
    $livekitDir = "$root\CHAV\livekit_server"
    $nodeDir = "$root\CHAV\LiveKitApp"
    $flutterDir = "$root\CHAV\Audio-video_calling"
}

# 1. LiveKit WebRTC Server (Port 7880)
$livekitRunning = Get-NetTCPConnection -LocalPort 7880 -State Listen -ErrorAction SilentlyContinue
if (-not $livekitRunning) {
    Write-Host "[1/3] Starting LiveKit Server (Port 7880)..." -ForegroundColor Yellow
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c cd /d `"$livekitDir`" && livekit-server.exe --dev" -WindowStyle Minimized
} else {
    Write-Host "[1/3] LiveKit Server is already active on port 7880." -ForegroundColor Green
}

# 2. Node.js Smart Web Server (Port 3000)
$webRunning = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
if (-not $webRunning) {
    Write-Host "[2/3] Starting Node.js Web Server (Port 3000)..." -ForegroundColor Yellow
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c cd /d `"$nodeDir`" && node server.js" -WindowStyle Minimized
} else {
    Write-Host "[2/3] Smart Web Server is already active on port 3000." -ForegroundColor Green
}

# 3. Flutter Web App (Port 8080)
Write-Host "[3/3] Launching CHAV Flutter Application on Chrome (Port 8080)..." -ForegroundColor Green
Write-Host ""
Set-Location $flutterDir
flutter run -d chrome --web-port 8080
