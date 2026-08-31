$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$spin = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "config\spin_table.json") -Raw | ConvertFrom-Json
$social = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "config\social.json") -Raw | ConvertFrom-Json
$chests = (Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "config\chests.json") -Raw | ConvertFrom-Json).items
$curve = (Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "config\progression.json") -Raw | ConvertFrom-Json).districtCurve
if ($null -eq $curve) { throw "progression.json : districtCurve absent" }
$districtFiles = Get-ChildItem -LiteralPath (Join-Path $workspace "config\districts") -Filter "district_*.json" |
    Sort-Object Name
if ($districtFiles.Count -lt 2) { throw "Au moins deux districts sont requis pour valider la progression" }

$weight = ($spin.outcomes | Measure-Object weight -Sum).Sum
if ($weight -le 0) { throw "Poids de spin nul" }
$expected = 0.0
$glitchWeight = 0
foreach ($outcome in $spin.outcomes) {
    $mean = 0.0
    switch ($outcome.type) {
        "credits" { $mean = ([double]$outcome.min + [double]$outcome.max) / 2.0 }
        "attack" { $mean = [double]$social.attack.baseRewardCredits }
        "raid" {
            $safe = [double]($social.raid.nodeCount - $social.raid.traceNodes)
            $probabilityTwoSafe = ($safe / [double]$social.raid.nodeCount) * (($safe - 1.0) / ([double]$social.raid.nodeCount - 1.0))
            $averageShare = (($social.raid.safeNodeSharesBps | Measure-Object -Average).Average / 10000.0)
            $mean = [double]$social.raid.basePotCredits * $probabilityTwoSafe * $averageShare * 2.0
        }
        "shield" { $mean = [double]$social.shieldOverflowCredits }
        "chest" {
            $chest = $chests | Where-Object { $_.chestId -eq $outcome.rewardId } | Select-Object -First 1
            if ($null -ne $chest) { $mean = [double]$chest.priceCredits }
        }
        "card" {
            $basic = $chests | Sort-Object priceCredits | Select-Object -First 1
            if ($null -ne $basic) { $mean = [double]$basic.priceCredits / [double]$basic.cardsPerOpen }
        }
        "none" { $glitchWeight += [int]$outcome.weight }
    }
    $expected += $mean * [double]$outcome.weight / [double]$weight
}
$glitchRate = [double]$glitchWeight / [double]$weight

if ($glitchRate -gt 0.25) { throw "Taux de spin vide trop élevé: $glitchRate" }

$districtResults = @()
foreach ($districtFile in $districtFiles) {
    $district = Get-Content -Encoding UTF8 -LiteralPath $districtFile.FullName -Raw | ConvertFrom-Json
    $districtCost = 0.0
    foreach ($element in $district.elements) {
        foreach ($level in $element.levels) { $districtCost += [double]$level.cost }
    }
    $spinsToComplete = $districtCost / $expected
    # Fenetre derivee de l'enveloppe config, pas de seuil code en dur : elle
    # croit avec l'index du district comme la courbe de couts.
    $growthFactor = [math]::Pow([double]$curve.expectedSpinsGrowth, [int]$district.id - 1)
    $minimumSpins = [double]$curve.expectedSpinsMin * $growthFactor
    $maximumSpins = [double]$curve.expectedSpinsMax * $growthFactor
    if ($spinsToComplete -lt $minimumSpins -or $spinsToComplete -gt $maximumSpins) {
        throw ("District $($district.id) hors fenetre cible: " +
            "$([math]::Round($spinsToComplete,1)) spins attendus, fenetre " +
            "[$([math]::Round($minimumSpins,1)), $([math]::Round($maximumSpins,1))]")
    }
    # L'enveloppe de cout (ecart a la courbe, croissance par niveau, monotonie)
    # est arbitree UNIQUEMENT par RemoteConfig::validate au boot, exerce par le
    # test cargo bundled_config_is_valid. On l'affiche ici sans la rejuger : deux
    # implementations du meme seuil finiraient par se contredire au bord.
    $expectedCost = [double]$curve.baseDistrictCostCredits *
        [math]::Pow([double]$curve.districtCostGrowth, [int]$district.id - 1)
    $deviation = if ($expectedCost -gt 0) {
        [math]::Abs($districtCost - $expectedCost) / $expectedCost
    } else { 0.0 }
    $districtResults += [pscustomobject]@{
        District = [int]$district.id
        Name = [string]$district.name
        TotalCost = [math]::Round($districtCost)
        ExpectedSpins = [math]::Round($spinsToComplete, 1)
        SpinWindow = "$([math]::Round($minimumSpins)) - $([math]::Round($maximumSpins))"
        CostDeviationPercent = [math]::Round($deviation * 100, 1)
    }
}

[pscustomobject]@{
    ExpectedCreditsPerSpin = [math]::Round($expected)
    EmptySpinRatePercent = [math]::Round($glitchRate * 100, 1)
} | Format-List
$districtResults | Format-Table -AutoSize
Write-Host "ECONOMY_CHECK_OK" -ForegroundColor Green
