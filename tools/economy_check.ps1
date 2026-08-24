$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$spin = Get-Content -LiteralPath (Join-Path $workspace "config\spin_table.json") -Raw | ConvertFrom-Json
$district = Get-Content -LiteralPath (Join-Path $workspace "config\districts\district_01.json") -Raw | ConvertFrom-Json

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
$districtCost = 0.0
foreach ($element in $district.elements) {
    foreach ($level in $element.levels) { $districtCost += [double]$level.cost }
}
$spinsToComplete = $districtCost / $expected
$glitchRate = [double]$glitchWeight / [double]$weight

if ($glitchRate -gt 0.25) { throw "Taux de spin vide trop élevé: $glitchRate" }
if ($spinsToComplete -lt 80 -or $spinsToComplete -gt 400) {
    throw "District 1 hors fenêtre cible: $spinsToComplete spins attendus"
}

[pscustomobject]@{
    ExpectedCreditsPerSpin = [math]::Round($expected)
    EmptySpinRatePercent = [math]::Round($glitchRate * 100, 1)
    DistrictOneCost = [math]::Round($districtCost)
    ExpectedSpinsToComplete = [math]::Round($spinsToComplete, 1)
} | Format-List
Write-Host "ECONOMY_CHECK_OK" -ForegroundColor Green

