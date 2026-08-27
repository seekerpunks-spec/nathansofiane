@echo off
rem Lanceur de diagnostic : ouvre le jeu (console visible) ET garde un log
rem dans game_run.log (racine du projet). Utiliser PLAY.bat pour un lancement
rem classique sans log.
setlocal
title CyberSeeker Game
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=%~dp0tools\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo [ERREUR] Godot introuvable.
  pause
  exit /b 1
)
powershell -NoProfile -Command "& '%GODOT%' -v --path '%~dp0client' 2>&1 | Tee-Object -FilePath '%~dp0game_run.log'"
echo.
echo --- Godot ferme (code %ERRORLEVEL%). Log complet : game_run.log ---
pause