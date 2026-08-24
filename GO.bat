@echo off
setlocal enabledelayedexpansion
title CyberSeeker - GO (serveur + client)
cd /d "%~dp0"

echo ============================================
echo   CYBERSEEKER - LANCEUR TOUT-EN-UN
echo ============================================
echo.

rem --- 1) .env ---
if not exist "server\.env" copy "server\.env.example" "server\.env" >nul
if not exist "server\.env" echo [ATTENTION] server\.env absent, le serveur va peut-etre rater.

rem --- 2) Postgres sur le port 5432 ? ---
call :port_up 5432
if not errorlevel 1 goto check_cargo

rem Docker dispo ?
where docker >nul 2>&1
if errorlevel 1 goto check_psql

echo [..] Docker detecte, Postgres pas actif. Verif du container...
docker ps -a --format "{{.Names}}" 2>nul | findstr /b cyberseeker-pg >nul
if errorlevel 1 (
  echo [..] Demarrage du container Postgres. Premiere fois = telechargement de l'image, ca peut prendre un moment
  docker run -d --name cyberseeker-pg -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=cyberseeker postgres:16
) else (
  echo [..] Container deja la, redemarrage
  docker start cyberseeker-pg >nul 2>&1
)

set /a i=0
:wait_pg
call :port_up 5432
if not errorlevel 1 goto check_cargo
set /a i+=1
if !i! geq 30 goto pg_fail
echo [..] Attente de Postgres (!i!/30)...
timeout /t 2 /nobreak >nul
goto wait_pg

:pg_fail
echo.
echo [ERREUR] Postgres via Docker ne repond pas apres 60 secondes. Dernieres lignes des logs :
docker logs --tail 20 cyberseeker-pg 2>&1
echo.
pause
exit /b 1

:check_psql
where psql >nul 2>&1
if not errorlevel 1 goto pg_installed

:pg_missing
echo.
echo [ERREUR] Ni Postgres actif, ni Docker, ni psql trouve.
echo          Option A : demarrer le daemon Docker puis relancer GO.bat
echo          Option B : installer Postgres :  winget install -e --id PostgreSQL.PostgreSQL.16
echo                     puis :  createdb cyberseeker
echo                     puis ajuster DATABASE_URL dans server\.env si besoin
echo.
pause
exit /b 1

:pg_installed
echo.
echo [ERREUR] psql est installe mais rien n'ecoute sur le port 5432.
echo          Demarrer le service Postgres :  net start postgresql-x64-16  (ou via Services.msc)
echo          puis relancer GO.bat
echo.
pause
exit /b 1

rem --- 3) Cargo / Rust ---
:check_cargo
where cargo >nul 2>&1
if errorlevel 1 goto no_cargo
goto start_server

:no_cargo
echo.
echo [ERREUR] Cargo/Rust introuvable. Installer gratuitement :
echo          winget install -e --id Rustlang.Rustup
echo          puis redemarrer ce terminal et relancer GO.bat
echo.
pause
exit /b 1

rem --- 4) Lancer le serveur ---
:start_server
echo.
echo [OK] Deps OK. Lancement du serveur. Premiere compilation : 1 a 3 minutes, sois patient.
start "CyberSeeker Server" /D "%~dp0server" cmd /k run_server.bat
set /a i=0
:wait_srv
curl -s -m 2 http://localhost:8080/health >nul 2>&1
if not errorlevel 1 goto launch_client
set /a i+=1
if !i! geq 120 goto srv_fail
echo [..] Attente du serveur (!i!/120)...
timeout /t 2 /nobreak >nul
goto wait_srv

:srv_fail
echo.
echo [ERREUR] Le serveur n'est pas up apres ~4 minutes.
echo          Regarder la fenetre "CyberSeeker Server" pour l'erreur exacte (compile Rust ou base de donnees)
echo.
pause
exit /b 1

:launch_client
echo.
echo [OK] Serveur OK. Lancement du client Godot...
call "%~dp0run_client.bat"
echo.
echo --- Fin de GO.bat ---
pause
exit /b 0

rem --- utils : le port %1 ecoute-t-il ? ---
:port_up
netstat -an | findstr "LISTENING" | findstr /i ":%1 " >nul
if errorlevel 1 exit /b 1
exit /b 0
