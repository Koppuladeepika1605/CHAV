@echo off
title CHAV Telehealth System
echo ===================================================
echo           Starting CHAV Telehealth System
echo ===================================================
echo.

set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%livekit_server" (
    set "LIVEKIT_DIR=%SCRIPT_DIR%livekit_server"
    set "NODE_DIR=%SCRIPT_DIR%LiveKitApp"
    set "FLUTTER_DIR=%SCRIPT_DIR%Audio-video_calling"
) else (
    set "LIVEKIT_DIR=%SCRIPT_DIR%CHAV\livekit_server"
    set "NODE_DIR=%SCRIPT_DIR%CHAV\LiveKitApp"
    set "FLUTTER_DIR=%SCRIPT_DIR%CHAV\Audio-video_calling"
)

:: 1. Check and start LiveKit Server (Port 7880)
netstat -ano | findstr :7880 | findstr LISTENING >nul 2>&1
if %errorlevel% neq 0 (
    echo [1/3] Starting LiveKit WebRTC Server on port 7880...
    start "CHAV LiveKit Server" /min cmd /c "cd /d "%LIVEKIT_DIR%" && livekit-server.exe --dev"
) else (
    echo [1/3] LiveKit Server is already active on port 7880.
)

:: 2. Check and start Node.js Smart Web Server (Port 3000)
netstat -ano | findstr :3000 | findstr LISTENING >nul 2>&1
if %errorlevel% neq 0 (
    echo [2/3] Starting Smart Web Server on port 3000...
    start "CHAV Web Server" /min cmd /c "cd /d "%NODE_DIR%" && node server.js"
) else (
    echo [2/3] Smart Web Server is already active on port 3000.
)

:: 3. Launch CHAV Flutter Web App on Port 8080
echo [3/3] Launching CHAV Flutter Web App on Chrome (Port 8080)...
echo.
cd /d "%FLUTTER_DIR%"
flutter run -d chrome --web-port 8080
