$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop) { throw 'Dossier Bureau introuvable.' }
$shortcutPath = Join-Path $desktop 'Jouer a CyberSeeker.lnk'
$launcherPath = Join-Path $PSScriptRoot 'launch_game.ps1'
$powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$iconPath = Join-Path $PSScriptRoot 'cyberseeker.ico'
# Format conversion of the existing game icon; no new illustration.
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object Drawing.Bitmap((Join-Path $workspace 'client\export\icons\main_192x192.png'))
$handle = $bitmap.GetHicon()
$icon = [Drawing.Icon]::FromHandle($handle)
try {
    $stream = [IO.File]::Create($iconPath)
    try { $icon.Save($stream) } finally { $stream.Dispose() }
} finally {
    $icon.Dispose()
    $bitmap.Dispose()
}
$desktopShell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $shortcutPath) {
    $old = $desktopShell.CreateShortcut($shortcutPath)
    if (-not $old.Arguments.Contains($launcherPath)) {
        throw 'Un raccourci different utilise deja ce nom. Aucun remplacement.'
    }
}
$link = $desktopShell.CreateShortcut($shortcutPath)
$link.TargetPath = $powerShell
$link.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $launcherPath + '"'
$link.WorkingDirectory = $workspace
$link.Description = 'Lance CyberSeeker et son serveur local. Aucun editeur, aucun APK.'
$link.IconLocation = $iconPath + ',0'
$link.WindowStyle = 7
$link.Save()
Write-Output "SHORTCUT_CREATED: $shortcutPath"
