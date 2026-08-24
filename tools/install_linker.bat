@echo off
setlocal
title CyberSeeker - Installation linker MSVC (VS Build Tools)
cd /d "%~dp0"

echo ============================================
echo   CYBERSEEKER - LINKER MSVC
echo   Visual Studio Build Tools 2022, workload C++
echo   Gratuit via winget, telechargement 1-2 Go
echo ============================================
echo.

set "VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto install
"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath >nul 2>&1
if errorlevel 1 goto install
goto already

:install
echo [..] Installation des Build Tools C++...
echo      C'est le plus gros morceau : 1 a 2 Go, selon ta connection 2 a 10 minutes.
echo      Ne pas fermer la fenetre.
echo.
winget install -e --id Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements
if errorlevel 1 goto failed

"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath >nul 2>&1
if errorlevel 1 goto failed
goto ok

:failed
echo.
echo [ERREUR] Installation des Build Tools echouee.
echo          A la main :  winget install -e --id Microsoft.VisualStudio.2022.BuildTools
echo          puis relancer ce script
echo.
pause
exit /b 1

:already
echo.
echo [OK] Les Build Tools C++ sont deja presentes.
echo      Relance GO.bat
echo.
pause
exit /b 0

:ok
echo.
echo ============================================
echo   LINKER PRET. Relance GO.bat
echo ============================================
echo.
pause
exit /b 0
