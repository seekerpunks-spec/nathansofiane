param(
    [string]$GodotPath = "",
    [string]$ApiBaseUrl = "",
    [string]$ApiSecondaryAuthBaseUrl = "",
    [string]$ApiDevAddress = "dev-player-0001",
    [string]$ApiSecondaryDevAddress = "dev-player-0002",
    [string]$TestDatabaseUrl = "postgres://postgres:postgres@localhost:5432/cyberseeker_test",
    [switch]$BuildAndroid
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$economyCheck = Join-Path $PSScriptRoot "economy_check.ps1"
& $economyCheck
$analyticsCheck = Join-Path $PSScriptRoot "analytics_check.ps1"
& $analyticsCheck
$securityCheck = Join-Path $PSScriptRoot "security_check.ps1"
& $securityCheck
$mobileCheck = Join-Path $PSScriptRoot "mobile_ux_check.ps1"
& $mobileCheck
$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
if (-not (Test-Path -LiteralPath $cargo)) { throw "cargo.exe introuvable" }

Push-Location (Join-Path $workspace "server")
try {
    & $cargo fmt --all -- --check
    if ($LASTEXITCODE -ne 0) { throw "cargo fmt a échoué" }
    # Tests DB fail-closed : sans base de test les tests Postgres paniquent au
    # lieu de passer au vert en silence (bug corrige en R26). La gate prouve en
    # plus que chaque test DB s'est execute en comptant les marqueurs emis.
    $env:CYBERSEEKER_TEST_DATABASE_URL = $TestDatabaseUrl
    Remove-Item Env:\CYBERSEEKER_ALLOW_DB_TEST_SKIP -ErrorAction SilentlyContinue
    # EAP=Stop transforme le stderr anodin de cargo (Compiling/Finished) en
    # erreur fatale des qu'on redirige 2>&1 : on detend le temps de la capture.
    $ErrorActionPreference = "Continue"
    $testLog = (& $cargo test -- --nocapture 2>&1 | Out-String)
    $ErrorActionPreference = "Stop"
    Write-Host $testLog
    if ($LASTEXITCODE -ne 0) { throw "cargo test a echoue" }
    $expectedDbTests = (Select-String -Path (Join-Path $workspace "server\src\*.rs") `
        -Pattern "testdb::connect\(" -AllMatches | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
    if (-not $expectedDbTests -or $expectedDbTests -lt 1) { throw "aucun appel au helper de test DB dans les sources - gate invalide" }
    $ranDbTests = ([regex]::Matches($testLog, "DB_TEST_RAN: ")).Count
    $skippedDbTests = ([regex]::Matches($testLog, "DB_TEST_SKIPPED: ")).Count
    if ($skippedDbTests -gt 0) { throw "$skippedDbTests test(s) Postgres sautes - la gate exige une base de test reelle" }
    if ($ranDbTests -ne $expectedDbTests) { throw "tests Postgres executes : $ranDbTests/$expectedDbTests - execution vacueuse detectee" }
    Write-Host "DB_TESTS_PROVEN: $ranDbTests/$expectedDbTests" -ForegroundColor Green
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
foreach ($resolution in @("360x800", "540x1170", "720x1280")) {
    $smokeLog = (& $GodotPath --headless --resolution $resolution --path $client "res://tests/SmokeScenes.tscn" 2>&1 | Out-String)
    Write-Host $smokeLog
    if ($LASTEXITCODE -ne 0 -or $smokeLog -match "SCRIPT ERROR|Parse Error|Failed to load script|SMOKE_SCENES_FAILED|SMOKE_CHECK_FAILED" -or $smokeLog -notmatch "SMOKE_SCENES_OK") {
        throw "Smoke test Godot echoue a la resolution $resolution"
    }
}

if ($ApiBaseUrl) {
    & (Join-Path $PSScriptRoot "api_contract_check.ps1") `
        -BaseUrl $ApiBaseUrl -DevAddress $ApiDevAddress
    if ($LASTEXITCODE -ne 0) { throw "Contrats API échoués" }
    if (-not $ApiSecondaryAuthBaseUrl) {
        throw "Gate HTTP incomplète : passer -ApiSecondaryAuthBaseUrl avec une seconde instance DEV_AUTH partageant DB/JWT"
    }
    & (Join-Path $PSScriptRoot "social_contract_check.ps1") `
        -BaseUrl $ApiBaseUrl -SecondaryAuthBaseUrl $ApiSecondaryAuthBaseUrl `
        -AlphaAddress $ApiDevAddress -BetaAddress $ApiSecondaryDevAddress
    if ($LASTEXITCODE -ne 0) { throw "Contrats sociaux API échoués" }
}

if ($BuildAndroid) {
    & (Join-Path $PSScriptRoot "build_android.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "Build Android échoué" }
}

Write-Host "CYBERSEEKER_VALIDATION_OK" -ForegroundColor Green
