@echo off
setlocal enabledelayedexpansion
title CyberSeeker - Installation deps (Postgres + Rust)
cd /d "%~dp0"

echo ============================================
echo   CYBERSEEKER - INSTALLATION DEPENDANCES
echo   Postgres + Rust, gratuit, via winget
echo ============================================
echo.

rem ---------- 1) POSTGRES ----------
set "PSQL="
if exist "C:\Program Files\PostgreSQL\16\bin\psql.exe" set "PSQL=C:\Program Files\PostgreSQL\16\bin\psql.exe"
if not defined PSQL if exist "C:\Program Files\PostgreSQL\15\bin\psql.exe" set "PSQL=C:\Program Files\PostgreSQL\15\bin\psql.exe"
if not defined PSQL if exist "C:\Program Files\PostgreSQL\14\bin\psql.exe" set "PSQL=C:\Program Files\PostgreSQL\14\bin\psql.exe"

if defined PSQL goto rust_step

echo [1/3] PostgreSQL pas trouve. Installation via winget...
echo       UAC : Accepter.
echo       Le wizard peut s'ouvrir :
echo         - etape PASSWORD : tape  postgres  deux fois   - IMPORTANT
echo         - tout le reste : Next
echo.
winget install -e --id PostgreSQL.PostgreSQL.16 --accept-source-agreements --accept-package-agreements
if errorlevel 1 goto pg_failed

if exist "C:\Program Files\PostgreSQL\16\bin\psql.exe" set "PSQL=C:\Program Files\PostgreSQL\16\bin\psql.exe"
if not defined PSQL if exist "C:\Program Files\PostgreSQL\15\bin\psql.exe" set "PSQL=C:\Program Files\PostgreSQL\15\bin\psql.exe"
if not defined PSQL goto pg_failed
echo.
echo [OK] PostgreSQL installe : %PSQL%
goto rust_step

:pg_failed
echo.
echo [ERREUR] Installation PostgreSQL impossible.
echo          A la main :  winget install -e --id PostgreSQL.PostgreSQL.16
echo          (mots de passe postgres dans le wizard), ou installe Docker Desktop puis relance GO.bat
echo.
pause
exit /b 1

:rust_step
rem ---------- 2) RUST ----------
set "PATH=%PATH%;%USERPROFILE%\.cargo\bin"
where cargo >nul 2>&1
if not errorlevel 1 goto db_step
echo [2/3] Rust pas trouve. Installation via winget, silencieux, 2 a 5 minutes...
winget install -e --id Rustlang.Rustup --accept-source-agreements --accept-package-agreements
if errorlevel 1 goto rust_failed
set "PATH=%PATH%;%USERPROFILE%\.cargo\bin"
where cargo >nul 2>&1
if errorlevel 1 goto rust_failed
echo [OK] Rust installe
goto db_step

:rust_failed
echo.
echo [ERREUR] Installation Rust impossible.
echo          A la main :  winget install -e --id Rustlang.Rustup
echo          puis redemarrer un terminal et relancer ce script
echo.
pause
exit /b 1

:db_step
rem ---------- 3) BASE DE DONNEES ----------
echo [3/3] Creation de la base cyberseeker...
set "PGPASSWORD=postgres"
"%PSQL%" -U postgres -h 127.0.0.1 -tAc "SELECT 1" >nul 2>&1
if errorlevel 1 goto pgpass_error
"%PSQL%" -U postgres -h 127.0.0.1 -tAc "SELECT 1 FROM pg_database WHERE datname='cyberseeker'" | findstr "1" >nul
if not errorlevel 1 goto done
"%PSQL%" -U postgres -h 127.0.0.1 -c "CREATE DATABASE cyberseeker" >nul
if errorlevel 1 goto pgpass_error
goto done

:pgpass_error
echo.
echo [ATTENTION] Connexion a Postgres impossible.
echo          Soit le mot de passe n'est pas "postgres" : modifie DATABASE_URL
echo          dans server\.env, soit le service est arrete :
echo          net start postgresql-x64-16
echo          puis relance ce script
echo.
pause
exit /b 1

:done
echo.
echo ============================================
echo   TOUT EST PRET. Relance GO.bat
echo ============================================
echo.
pause
exit /b 0
