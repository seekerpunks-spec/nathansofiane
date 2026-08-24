$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$spin = Get-Content -LiteralPath (Join-Path $workspace "config\spin_table.json") -Raw | ConvertFrom-Json
$districtFiles = Get-ChildItem -LiteralPath (Join-Path $workspace "config\districts") -Filter "district_*.json" |
    Sort-Object Name
if ($districtFiles.Count -lt 2) { throw "Au moins deux districts sont requis pour valider la progression" }

$weight = ($spin.outcomes | Measure-Object weight -Sum).Sum
if ($weight -le 0) { throw "Poids de spin nul" }
$expected = 0.0
$glitchWeight = 0
foreach ($outcome in $spin.outcomes) {
    if ($outcome.type -eq "credits") {
        $mean = ([double]$outcome.min + [double]$outcome.max) / 2.0
        $expected += $mean * [double]$outcome.weight / [double]$weight
    } else { $glitchWeight += [int]$outcome.weight }
}
$glitchRate = [double]$glitchWeight / [double]$weight

if ($glitchRate -gt 0.25) { throw "Taux de spin vide trop élevé: $glitchRate" }

$districtResults = @()
$previousCost = 0.0
foreach ($districtFile in $districtFiles) {
    $district = Get-Content -LiteralPath $districtFile.FullName -Raw | ConvertFrom-Json
    $districtCost = 0.0
    foreach ($element in $district.elements) {
        foreach ($level in $element.levels) { $districtCost += [double]$level.cost }
    }
    $spinsToComplete = $districtCost / $expected
    $minimumSpins = if ([int]$district.id -eq 1) { 80 } else { 150 }
    $maximumSpins = if ([int]$district.id -eq 1) { 400 } else { 800 }
    if ($spinsToComplete -lt $minimumSpins -or $spinsToComplete -gt $maximumSpins) {
        throw "District $($district.id) hors fenêtre cible: $spinsToComplete spins attendus"
    }
    if ($districtCost -le $previousCost) {
        throw "La courbe de coût doit croître: district $($district.id) coûte $districtCost après $previousCost"
    }
    $districtResults += [pscustomobject]@{
        District = [int]$district.id
        Name = [string]$district.name
        TotalCost = [math]::Round($districtCost)
        ExpectedSpins = [math]::Round($spinsToComplete, 1)
    }
    $previousCost = $districtCost
}

[pscustomobject]@{
    ExpectedCreditsPerSpin = [math]::Round($expected)
    EmptySpinRatePercent = [math]::Round($glitchRate * 100, 1)
} | Format-List
$districtResults | Format-Table -AutoSize
Write-Host "ECONOMY_CHECK_OK" -ForegroundColor Green
