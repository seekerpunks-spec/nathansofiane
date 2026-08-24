@echo off
setlocal
title CyberSeeker - PLAY
cd /d "%~dp0"

rem ============================================================
rem  PLAY.bat - 1 clic : serveur deja up ? + jeu direct en console
rem  Tout (logs [NET], erreurs, resultats) est visible dans la
rem  fenetre "CyberSeeker Game" qui reste ouverte apres fermeture.
rem ============================================================

rem --- 1) Localiser Godot ---
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=%~dp0tools\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" (
  echo [ERREUR] Godot introuvable. Dezippe Godot_v4.7.2-stable_win64.exe.zip
  echo          dans %USERPROFILE%\Downloads (clic droit - Extraire tout).
  pause
  exit /b 1
)

rem --- 2) Serveur up ? ---
curl -s -m 2 http://localhost:8080/health >nul 2>&1
if not errorlevel 1 goto start_game

set /a i=0
:wait_srv
curl -s -m 2 http://localhost:8080/health >nul 2>&1
if not errorlevel 1 goto start_game
set /a i+=1
if %i% geq 15 goto srv_fail
echo [..] Attente du serveur (%i%/15)...
timeout /t 2 /nobreak >nul
goto wait_srv

:srv_fail
echo.
echo [ERREUR] Serveur injoignable sur http://localhost:8080.
echo          Lance d'abord  GO.bat  (serveur) puis rejoue.
echo.
pause
exit /b 1

:start_game
echo [OK] Serveur OK. Lancement du jeu (console visible)...
start "CyberSeeker Game" cmd /k ""%GODOT%" -v --path "%~dp0client""
echo.
echo [INFO] Jeu lance dans la fenetre "CyberSeeker Game".
echo        - Logs [NET] et erreurs = visibles en bas de cette fenetre.
echo        - F11 = plein ecran.  Ferme la fenetre pour arreter.
pause
exit /b 0
