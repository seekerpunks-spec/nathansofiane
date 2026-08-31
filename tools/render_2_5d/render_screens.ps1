param(
    [string]$BlenderPath = "C:\Users\danbi\Documents\Codex\tools\blender-5.2\runtime\blender-5.2.0-windows-x64\blender.exe",
    [string]$OutputDir = "",
    [string]$BlendDir = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $root "art\render_2_5d\staging"
}
if (-not $BlendDir) {
    $BlendDir = Join-Path $root "art\blender"
}
if (-not (Test-Path -LiteralPath $BlenderPath)) {
    throw "Blender introuvable : $BlenderPath"
}

& $BlenderPath --background --factory-startup --python (Join-Path $PSScriptRoot "render_screen_art.py") -- --output-dir $OutputDir --blend-dir $BlendDir
if ($LASTEXITCODE -ne 0) {
    throw "Le rendu Blender des écrans a échoué avec le code $LASTEXITCODE"
}

$expected = @("district_hero.png", "collection_hero.png", "missions_hero.png", "store_hero.png", "mascot_hero.png")
foreach ($name in $expected) {
    $path = Join-Path $OutputDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Le rendu attendu n'a pas été créé : $path"
    }
}
Write-Output "CYBERSEEKER_SCREEN_RENDER_PIPELINE_OK"
