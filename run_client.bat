@echo off
setlocal
title CyberSeeker - Lanceur client Godot

rem --- 1) Localiser Godot (if exist directs, pas de for loop) ---
set "GODOT="

set "P1=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "P2=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe"
set "P3=%~dp0tools\Godot_v4.7.2-stable_win64.exe"

if exist "%P1%" (
    set "GODOT=%P1%"
    goto :godot_found
)
if exist "%P2%" (
    rem Accepter seulement si c'est un fichier, pas un dossier
    if not exist "%P2%\" (
        set "GODOT=%P2%"
        goto :godot_found
    )
)
if exist "%P3%" (
    set "GODOT=%P3%"
    goto :godot_found
)

rem --- Pas trouve ---
echo [ERREUR] Godot.exe introuvable.
echo.
echo Chemins testes :
echo   1. %P1%
echo   2. %P2%  (dossier detecte, pas un fichier)
echo   3. %P3%
echo.
echo Solution : va dans Downloads, dezippe "Godot_v4.7.2-stable_win64.exe.zip"
echo   (clic droit - Extraire tout), puis relance ce fichier.
echo.
pause
exit /b 1

:godot_found

rem --- 2) Verifier le serveur ---
curl -s -m 2 http://localhost:8080/health >nul 2>&1
if errorlevel 1 (
    echo [ATTENTION] Serveur CyberSeeker injoignable sur http://localhost:8080
    echo            Lance d'abord :  GO.bat   (ou cd server ^&^& cargo run)
    echo            Sans le serveur le client affichera "HORS LIGNE".
    echo.
) else (
    echo [OK] Serveur OK sur http://localhost:8080
)

echo [OK] Godot : %GODOT%
echo Lancement de l'editeur Godot sur client/ ...
echo Dans Godot : appuie sur F5 pour jouer.
echo.
"%GODOT%" --path "%~dp0client" -e
pause
