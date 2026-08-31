$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$client = Join-Path $workspace "client"
$project = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "project.godot") -Raw
$main = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "scenes\Main.gd") -Raw
$ui = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "scripts\core\Ui.gd") -Raw
$onboarding = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "scenes\screens\OnboardingScreen.gd") -Raw
$events = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "scripts\core\Events.gd") -Raw
$missions = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "scenes\screens\MissionsScreen.gd") -Raw
$spinPath = Join-Path $client "scenes\screens\SpinScreen.gd"
$spinLines = (Get-Content -Encoding UTF8 -LiteralPath $spinPath).Count
$smoke = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "tests\SmokeScenes.gd") -Raw
$sources = Get-ChildItem -LiteralPath $client -Filter "*.gd" -Recurse |
    ForEach-Object { Get-Content -Encoding UTF8 -LiteralPath $_.FullName -Raw }
$joined = $sources -join "`n"

if ($project -notmatch 'window/stretch/aspect="expand"') { throw "Stretch responsive expand absent" }
if ($main -notmatch 'NOTIFICATION_WM_GO_BACK_REQUEST') { throw "Bouton Retour Android non géré" }
if ($main -notmatch 'dismiss_on_back') { throw "Fermeture des modales au Retour absente" }
if ($ui -notmatch 'get_display_safe_area') { throw "Safe areas système non prises en compte" }
if ($ui -notmatch 'custom_minimum_size\s*=\s*Vector2\(0, 64\)') { throw "Cible tactile standard 64 absente" }
if ($ui -notmatch 'static func reward_text' -or $missions -match 'reward\.get\("spins"') {
    throw "Récompenses live-ops encore supposées spins-only"
}
if ($spinLines -gt 1000) { throw "SpinScreen redevient monolithique: $spinLines lignes" }
if ($onboarding -match 'apply_state\(\{\s*"spins"' -or $events -notmatch 'func reset_session' -or
    $events -notmatch '_session_generation') {
    throw "Session mobile: état fabriqué ou isolation analytics absente"
}
foreach ($component in @("SpinVisuals.gd", "SpinNetworkView.gd", "SpinNetworkActions.gd", "SpinEncounterView.gd", "SpinTelemetry.gd")) {
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

# --- Budget d'assets mobile (R31) ---
# La derive de poids ne se voit qu'au build Android : la gate la rend visible
# a chaque validation. Chiffres de reference apres conversion WebP : 3,64 Mo
# au total, plus gros fichier 913 Ko (atlas du slot, sans perte).
$assetsRoot = Join-Path $client "assets"
$generatedRoot = Join-Path $assetsRoot "generated"
$assetBudgetTotalMB = 5.0
$assetBudgetFileKB = 1024

if (Test-Path -LiteralPath (Join-Path $generatedRoot "local_ai")) {
    throw "Staging local_ai present dans client/assets : il vit sous art/local_ai/staging"
}

$assetFiles = Get-ChildItem -LiteralPath $assetsRoot -Recurse -File
$totalMB = [math]::Round((($assetFiles | Measure-Object Length -Sum).Sum) / 1MB, 2)
if ($totalMB -gt $assetBudgetTotalMB) {
    throw "Budget d'assets depasse: $totalMB Mo > $assetBudgetTotalMB Mo"
}
$oversized = $assetFiles | Where-Object { $_.Length -gt $assetBudgetFileKB * 1KB }
if ($oversized) {
    throw "Asset au-dessus de $assetBudgetFileKB Ko: $(($oversized | ForEach-Object Name) -join ', ')"
}

# WebP obligatoire pour les textures runtime : un PNG lossless de plusieurs Mo
# passe inapercu a l'ecran mais pese dans l'APK. La conversion est fournie
# (tools/asset_budget + promotions du manifest), donc aucun PNG n'est tolere.
$textures = $assetFiles | Where-Object { $_.FullName.StartsWith($generatedRoot) -and $_.Extension -in @(".png", ".webp") }
$pngLeft = $textures | Where-Object { $_.Extension -eq ".png" }
if ($pngLeft) {
    throw "PNG non converti en WebP: $(($pngLeft | ForEach-Object Name) -join ', ')"
}

# Zero asset orphelin : chaque texture doit etre referencee par un chemin
# res:// dans les sources GDScript ou par la config (les districts stockent
# des noms relatifs sans extension sous assets/generated/).
$configTexts = (Get-ChildItem -LiteralPath (Join-Path $workspace "config") -Filter "*.json" -Recurse |
    ForEach-Object { Get-Content -Encoding UTF8 -LiteralPath $_.FullName -Raw }) -join "`n"
$references = $joined + "`n" + $configTexts
$orphans = @()
foreach ($texture in $textures) {
    $relative = $texture.FullName.Substring($generatedRoot.Length + 1).Replace("\", "/")
    $resPath = "res://assets/generated/" + $relative
    $bareName = $relative.Substring(0, $relative.Length - $texture.Extension.Length)
    if (-not ($references.Contains($resPath) -or $references.Contains('"' + $bareName + '"'))) {
        $orphans += $relative
    }
}
if ($orphans) {
    throw "Assets orphelins (aucune reference code/config): $($orphans -join ', ')"
}

# Un .import sans source est un residu de suppression : Godot le regenere de
# toute facon, et il fausse l'inventaire du projet.
$staleImports = $assetFiles | Where-Object { $_.Extension -eq ".import" } |
    Where-Object { -not (Test-Path -LiteralPath ($_.FullName.Substring(0, $_.FullName.Length - 7))) }
if ($staleImports) {
    throw "Fichiers .import orphelins: $(($staleImports | ForEach-Object Name) -join ', ')"
}

# --- UI 100 % anglaise (R32 / D12) ---
# Le copy joueur est anglais pour le dApp Store global. Tripwire : aucun
# caractere accentue dans une chaine des scripts client (commentaires et tests
# exclus, ils restent francais) ni dans les champs joueur des configs.
# La classe exclut U+00D7 (signe multiplication, "BET x1") et U+00F7.
$accentClass = '[\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF\u0152\u0153]'
$frenchHits = @()
Get-ChildItem -LiteralPath $client -Filter "*.gd" -Recurse |
    Where-Object { $_.FullName -notmatch '\\tests\\' } |
    ForEach-Object {
        $file = $_
        $lineNum = 0
        foreach ($line in (Get-Content -Encoding UTF8 -LiteralPath $file.FullName)) {
            $lineNum++
            $code = $line -replace '(^|\s)#.*$', ''
            if ($code -match ('"[^"]*' + $accentClass + '[^"]*"')) {
                $frenchHits += "$($file.Name):$lineNum"
            }
        }
    }
if ($frenchHits) {
    throw "Chaines UI non anglaises (accents) : $($frenchHits -join ', ')"
}
$configFrench = @()
Get-ChildItem -LiteralPath (Join-Path $workspace "config") -Filter "*.json" -Recurse |
    ForEach-Object {
        $file = $_
        $lineNum = 0
        foreach ($line in (Get-Content -Encoding UTF8 -LiteralPath $file.FullName)) {
            $lineNum++
            if ($line -match '"(name|label|description|title|subtitle)"\s*:' -and $line -match $accentClass) {
                $configFrench += "$($file.Name):$lineNum"
            }
        }
    }
if ($configFrench) {
    throw "Champs config joueur non anglais (accents) : $($configFrench -join ', ')"
}

# --- Identite de boot + packaging Android (R33) ---
# Sans ces reglages, l'APK sort avec le splash et l'icone robot Godot par
# defaut : invisible en desktop, humiliant en store review.
if ($project -notmatch 'boot_splash/bg_color=Color\(') { throw "Boot splash: bg_color absent (splash Godot par defaut)" }
if ($project -notmatch 'boot_splash/image="res://assets/boot_splash\.png"') { throw "Boot splash: image absente" }
if (-not (Test-Path -LiteralPath (Join-Path $client "assets\boot_splash.png"))) { throw "assets/boot_splash.png manquant" }
if ($project -match ('config/description="[^"]*' + $accentClass)) { throw "Description projet non anglaise" }

$preset = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $client "export_presets.cfg") -Raw
foreach ($iconKey in @("main_192x192", "adaptive_foreground_432x432", "adaptive_background_432x432")) {
    if ($preset -notmatch ('launcher_icons/' + $iconKey + '="res://export/icons/' + $iconKey + '\.png"')) {
        throw "Preset Android: launcher_icons/$iconKey non cable"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $client "export\icons\$iconKey.png"))) {
        throw "Icone launcher manquante: export/icons/$iconKey.png"
    }
}
if ($preset -notmatch 'exclude_filter="[^"]*export/\*') { throw "Preset Android: export/* doit rester hors du pck" }

[pscustomobject]@{
    TouchInputs = $touchInputs
    DismissibleModals = $dismissibleModals
    SafeAreas = $true
    AndroidBack = $true
    SpinScreenLines = $spinLines
    PetsRuntimeHits = 0
    AssetsTotalMB = $totalMB
    AssetTextures = @($textures).Count
    EnglishUiStrings = $true
    BootSplash = $true
    LauncherIcons = 3
} | Format-List
Write-Host "MOBILE_UX_CHECK_OK" -ForegroundColor Green
