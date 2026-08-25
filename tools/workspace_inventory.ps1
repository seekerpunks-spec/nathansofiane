$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot

$rows = Get-ChildItem -Force -Directory -LiteralPath $workspace | ForEach-Object {
    $files = @(Get-ChildItem -Force -File -Recurse -LiteralPath $_.FullName -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Name = $_.Name
        Files = $files.Count
        MiB = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
        SuspiciousName = $_.Name -eq "@" -or $_.Name -notmatch '^[A-Za-z0-9._ -]+$'
    }
}

$rows | Sort-Object MiB -Descending | Format-Table -AutoSize
$suspicious = @($rows | Where-Object SuspiciousName)
if (@($suspicious | Where-Object Files).Count -gt 0) {
    throw "Un dossier racine au nom anormal contient désormais des fichiers : inspection manuelle requise"
}
Write-Host "WORKSPACE_INVENTORY_OK: $($suspicious.Count) dossiers anormaux vides" -ForegroundColor Green
