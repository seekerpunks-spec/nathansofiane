param(
    [string[]]$Only = @(),
    [switch]$Force,
    [switch]$KeepServer
)

$ErrorActionPreference = 'Stop'
$AiHome = if ($env:CYBERSEEKER_AI_HOME) {
    $env:CYBERSEEKER_AI_HOME
} else {
    'C:\Users\danbi\Documents\Codex\2026-08-22\ex\local-ai'
}
$Python = Join-Path $AiHome 'venv\Scripts\python.exe'
$Script = Join-Path $PSScriptRoot 'generate_assets.py'

if (-not (Test-Path -LiteralPath $Python)) {
    throw "Environnement local introuvable: $Python"
}

$Arguments = @($Script)
if ($Only.Count -gt 0) {
    $Arguments += '--only'
    $Arguments += $Only
}
if ($Force) {
    $Arguments += '--force'
}
if ($KeepServer) {
    $Arguments += '--keep-server'
}

& $Python @Arguments
exit $LASTEXITCODE
