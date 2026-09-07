@echo off
setlocal
rem Same one-click launcher as the desktop shortcut; no editor or APK build.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\launch_game.ps1"
exit /b 0
