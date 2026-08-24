@echo off
setlocal
title CyberSeeker - Diagnostic / reparation linker MSVC
cd /d "%~dp0"

echo ============================================
echo   CYBERSEEKER - LINKER MSVC : CHECK + FIX
echo ============================================
echo.

set "VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto no_installer

for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%I"

if not defined VSPATH goto missing

echo [OK] Composant C++ trouve dans :
echo      %VSPATH%
echo.
echo Emplacement de link.exe :
dir /b "%VSPATH%\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe" 2>nul
echo.
echo [OK] Tout est la. Relance GO.bat, le serveur va charger cet environnement tout seul.
pause
exit /b 0

:missing
echo [ATTENTION] Visual Studio est present mais le composant C++ (VC Tools) manque.
echo            Je l'ajoute maintenant : 200-500 MB, quelques minutes.
echo            Si UAC : Accepter.
echo.
set "VSPATH="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -property installationPath`) do set "VSPATH=%%I"
if not defined VSPATH goto no_installer
"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vs_installer.exe" modify --installpath "%VSPATH%" --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --quiet --wait --norestart
if errorlevel 1 goto fix_failed

set "VSPATH="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%I"
if not defined VSPATH goto fix_failed
echo.
echo [OK] Composant C++ ajoute. Relance GO.bat.
pause
exit /b 0

:fix_failed
echo.
echo [ERREUR] Ajout du composant C++ impossible automatiquement.
echo          A la main :
echo            1. Ouvre "Visual Studio Installer" (menu demarrer)
echo            2. Modifie sur ton installation
echo            3. Coche "Developpement desktop avec C++"
echo            4. Installe, puis relance GO.bat
echo.
pause
exit /b 1

:no_installer
echo.
echo [ERREUR] L'installeur Visual Studio n'est pas trouve.
echo          Lance install_linker.bat a la racine, il gera tout via winget.
echo.
pause
exit /b 1
