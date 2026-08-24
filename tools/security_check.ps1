$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$server = Join-Path $workspace "server\src"

$auth = Get-Content -LiteralPath (Join-Path $server "auth.rs") -Raw
$main = Get-Content -LiteralPath (Join-Path $server "main.rs") -Raw
$spin = Get-Content -LiteralPath (Join-Path $server "spin.rs") -Raw
$commerce = Get-Content -LiteralPath (Join-Path $server "commerce.rs") -Raw
$engagement = Get-Content -LiteralPath (Join-Path $server "engagement.rs") -Raw
$entitlements = Get-Content -LiteralPath (Join-Path $server "entitlements.rs") -Raw
$authRuntime = $auth.Split("#[cfg(test)]")[0]

if ($authRuntime -match 'to_lowercase\s*\(') { throw "Auth: normalisation lowercase interdite pour Base58" }
if ($main -notmatch 'dev_auth\s*&&\s*!cfg!\(debug_assertions\)') { throw "Garde release DEV_AUTH absente" }
if ($spin -notmatch 'OsRng') { throw "Spin: CSPRNG OsRng absent" }
if ($commerce -notmatch '!state\.dev_auth') { throw "Commerce: preuve dev non fermée hors DEV_AUTH" }
if ($main -match 'route\([^\r\n]*entitlements[^\r\n]*post\(') { throw "Entitlements: route client de mutation interdite" }
if ($entitlements -notmatch 'expires_at>now\(\)') { throw "Entitlements: expiration fail-closed absente" }

foreach ($scope in @('event_claim:', 'season_claim:')) {
    $start = $engagement.IndexOf($scope)
    if ($start -lt 0) { throw "Scope idempotence absent: $scope" }
    $slice = $engagement.Substring($start, [Math]::Min(5000, $engagement.Length - $start))
    if ($slice -notmatch 'fetch_idempotent_locked') { throw "Relecture idempotence sous verrou absente: $scope" }
}

$mutationFiles = @("collection.rs", "commerce.rs", "district.rs", "engagement.rs", "friends.rs", "social.rs", "spin.rs", "teams.rs", "trading.rs")
foreach ($file in $mutationFiles) {
    $content = Get-Content -LiteralPath (Join-Path $server $file) -Raw
    if ($content -notmatch 'request_id\(' -or $content -notmatch 'store_idempotent') {
        throw "Mutation sans contrat request-id/idempotence détectée dans $file"
    }
}

[pscustomobject]@{
    MutationModules = $mutationFiles.Count
    Base58CasePreserved = $true
    EntitlementsFailClosed = $true
    ReleaseDevAuthBlocked = $true
} | Format-List
Write-Host "SECURITY_CHECK_OK" -ForegroundColor Green
