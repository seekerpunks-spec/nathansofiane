@echo off
setlocal
cd /d "%~dp0"

rem Charge l'environnement MSVC (link.exe) si les Build Tools sont presentes
set "VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto no_vs
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%I"
if not defined VSPATH goto no_vs
echo [OK] Environnement MSVC charge
call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
goto run

:no_vs

echo [ATTENTION] VS Build Tools C++ non detectees.
echo            Si erreur "link.exe not found" : lance install_linker.bat a la racine, puis relance GO.bat

:run

cargo run
