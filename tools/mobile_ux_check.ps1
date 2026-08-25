$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$client = Join-Path $workspace "client"
$project = Get-Content -LiteralPath (Join-Path $client "project.godot") -Raw
$main = Get-Content -LiteralPath (Join-Path $client "scenes\Main.gd") -Raw
$ui = Get-Content -LiteralPath (Join-Path $client "scripts\core\Ui.gd") -Raw
$onboarding = Get-Content -LiteralPath (Join-Path $client "scenes\screens\OnboardingScreen.gd") -Raw
$events = Get-Content -LiteralPath (Join-Path $client "scripts\core\Events.gd") -Raw
$spinPath = Join-Path $client "scenes\screens\SpinScreen.gd"
$spinLines = (Get-Content -LiteralPath $spinPath).Count
$smoke = Get-Content -LiteralPath (Join-Path $client "tests\SmokeScenes.gd") -Raw
$sources = Get-ChildItem -LiteralPath $client -Filter "*.gd" -Recurse |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
$joined = $sources -join "`n"

if ($project -notmatch 'window/stretch/aspect="expand"') { throw "Stretch responsive expand absent" }
if ($main -notmatch 'NOTIFICATION_WM_GO_BACK_REQUEST') { throw "Bouton Retour Android non géré" }
if ($main -notmatch 'dismiss_on_back') { throw "Fermeture des modales au Retour absente" }
if ($ui -notmatch 'get_display_safe_area') { throw "Safe areas système non prises en compte" }
if ($ui -notmatch 'custom_minimum_size\s*=\s*Vector2\(0, 64\)') { throw "Cible tactile standard 64 absente" }
if ($spinLines -gt 1100) { throw "SpinScreen redevient monolithique: $spinLines lignes" }
if ($onboarding -match 'apply_state\(\{\s*"spins"' -or $events -notmatch 'func reset_session' -or
    $events -notmatch '_session_generation') {
    throw "Session mobile: état fabriqué ou isolation analytics absente"
}
foreach ($component in @("SpinVisuals.gd", "SpinNetworkView.gd", "SpinNetworkActions.gd", "SpinEncounterView.gd")) {
    if (-not (Test-Path -LiteralPath (Join-Path $client "scripts\components\$component"))) {
        throw "Composant Spin absent: $component"
    }
}
foreach ($overlay in @('_render_network', 'smoke-attack', 'smoke-raid', '_show_social_result')) {
    if ($smoke -notmatch [regex]::Escape($overlay)) { throw "Smoke overlay absent: $overlay" }
}

$touchInputs = ([regex]::Matches($joined, 'custom_minimum_size\.y\s*=\s*52')).Count
$dismissibleModals = ([regex]::Matches($joined, 'add_to_group\("dismiss_on_back"\)')).Count
if ($touchInputs -lt 8) { throw "Inputs tactiles renforcés insuffisants: $touchInputs" }
if ($dismissibleModals -lt 7) { throw "Modales Retour insuffisamment couvertes: $dismissibleModals" }

$gameplayRoots = @(
    (Join-Path $client "scenes"),
    (Join-Path $client "scripts"),
    (Join-Path $workspace "server\src"),
    (Join-Path $workspace "config")
)
$petHits = Get-ChildItem -LiteralPath $gameplayRoots -File -Recurse |
    Select-String -Pattern '\b(pet|pets)\b' -CaseSensitive:$false
if ($petHits) { throw "Système Pets détecté dans le runtime" }

[pscustomobject]@{
    TouchInputs = $touchInputs
    DismissibleModals = $dismissibleModals
    SafeAreas = $true
    AndroidBack = $true
    SpinScreenLines = $spinLines
    PetsRuntimeHits = 0
} | Format-List
Write-Host "MOBILE_UX_CHECK_OK" -ForegroundColor Green
