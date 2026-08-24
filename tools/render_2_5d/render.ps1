param(
    [string]$BlenderPath = "C:\Users\danbi\Documents\Codex\tools\blender-5.2\runtime\blender-5.2.0-windows-x64\blender.exe",
    [string]$Output = "",
    [string]$Blend = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $Output) {
    $Output = Join-Path $root "client\assets\generated\rendered\slot_cabinet.png"
}
if (-not $Blend) {
    $Blend = Join-Path $root "art\blender\cyberseeker_slot_master.blend"
}
if (-not (Test-Path -LiteralPath $BlenderPath)) {
    throw "Blender introuvable : $BlenderPath"
}

& $BlenderPath --background --factory-startup --python (Join-Path $PSScriptRoot "render_slot_cabinet.py") -- --output $Output --blend $Blend
if ($LASTEXITCODE -ne 0) {
    throw "Le rendu Blender a échoué avec le code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $Output)) {
    throw "Le rendu attendu n'a pas été créé : $Output"
}

$item = Get-Item -LiteralPath $Output
Write-Output "CYBERSEEKER_RENDER_PIPELINE_OK"
Write-Output "PNG: $($item.FullName) ($([Math]::Round($item.Length / 1MB, 2)) Mio)"
Write-Output "BLEND: $Blend"
