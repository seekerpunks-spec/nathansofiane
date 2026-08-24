param(
    [string]$GodotPath = "",
    [switch]$BuildAndroid
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$economyCheck = Join-Path $PSScriptRoot "economy_check.ps1"
& $economyCheck
$analyticsCheck = Join-Path $PSScriptRoot "analytics_check.ps1"
& $analyticsCheck
$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
if (-not (Test-Path -LiteralPath $cargo)) { throw "cargo.exe introuvable" }

Push-Location (Join-Path $workspace "server")
try {
    & $cargo fmt --all -- --check
    if ($LASTEXITCODE -ne 0) { throw "cargo fmt a échoué" }
    & $cargo test
    if ($LASTEXITCODE -ne 0) { throw "cargo test a échoué" }
} finally { Pop-Location }

if (-not $GodotPath) {
    $candidates = @(
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe")
    )
    $GodotPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $GodotPath) { throw "Godot 4.7.2 introuvable; passer -GodotPath" }

$client = Join-Path $workspace "client"
$importLog = (& $GodotPath --headless --editor --path $client --quit 2>&1 | Out-String)
Write-Host $importLog
if ($LASTEXITCODE -ne 0 -or $importLog -match "SCRIPT ERROR|Parse Error|Failed to load script") {
    throw "Import Godot échoué"
}
$smokeLog = (& $GodotPath --headless --path $client "res://tests/SmokeScenes.tscn" 2>&1 | Out-String)
Write-Host $smokeLog
if ($LASTEXITCODE -ne 0 -or $smokeLog -match "SCRIPT ERROR|Parse Error|Failed to load script" -or $smokeLog -notmatch "SMOKE_SCENES_OK") {
    throw "Smoke test Godot échoué"
}

if ($BuildAndroid) {
    & (Join-Path $PSScriptRoot "build_android.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "Build Android échoué" }
}

Write-Host "CYBERSEEKER_VALIDATION_OK" -ForegroundColor Green
