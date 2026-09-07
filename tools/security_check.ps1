$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$server = Join-Path $workspace "server\src"

$auth = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "auth.rs") -Raw
$main = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "main.rs") -Raw
$spin = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "spin.rs") -Raw
$game = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "game.rs") -Raw
$commerce = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "commerce.rs") -Raw
$engagement = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "engagement.rs") -Raw
$collection = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "collection.rs") -Raw
$entitlements = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "entitlements.rs") -Raw
$db = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "db.rs") -Raw
$rate = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "rate_limit.rs") -Raw
$guardsMigration = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "server\migrations\0016_distributed_guards.sql") -Raw
$rewardPool = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "reward_pool.rs") -Raw
$rewardPoolConfig = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "config\reward_pool.json") -Raw
$rewardPoolMigration = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "server\migrations\0017_reward_pool_ledger.sql") -Raw
$refreshMigration = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "server\migrations\0018_refresh_rotation.sql") -Raw
$invariantsMigration = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "server\migrations\0019_relational_invariants.sql") -Raw
$privacyMigration = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "server\migrations\0021_privacy_controls.sql") -Raw
$account = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server "account.rs") -Raw
$net = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $workspace "client\scripts\core\Net.gd") -Raw
# -split (regex) est obligatoire ici : String.Split("#[cfg(test)]") resout vers la
# surcharge char[] et tronquerait le runtime au premier caractere de l'ensemble.
$authRuntime = ($auth -split '#\[cfg\(test\)\]')[0]
if ($authRuntime.Length -lt ($auth.Length / 2)) { throw "Auth: extraction du runtime hors tests invalide" }

if ($authRuntime -match 'to_lowercase\s*\(') { throw "Auth: normalisation lowercase interdite pour Base58" }
if ($main -notmatch 'dev_auth\s*&&\s*!cfg!\(debug_assertions\)') { throw "Garde release DEV_AUTH absente" }
if ($spin -notmatch 'OsRng') { throw "Spin: CSPRNG OsRng absent" }
if ($commerce -notmatch '!state\.dev_auth') { throw "Commerce: preuve dev non fermée hors DEV_AUTH" }
if ($main -match 'route\([^\r\n]*entitlements[^\r\n]*post\(') { throw "Entitlements: route client de mutation interdite" }
if ($entitlements -notmatch 'expires_at>now\(\)') { throw "Entitlements: expiration fail-closed absente" }
if ($authRuntime -match 'HashMap|Mutex') { throw "Auth: nonce encore stocké en mémoire" }
if ($db -notmatch 'DELETE FROM auth_nonces WHERE address=\$1' -or $db -notmatch 'RETURNING nonce') {
    throw "Auth: consommation atomique PostgreSQL du nonce absente"
}
if ($authRuntime -notmatch 'sign_in_message' -or $authRuntime -notmatch 'auth_domain' -or
    $db -notmatch 'CASE WHEN auth_nonces\.expires_at<now\(\)') {
    throw "Auth: challenge non lié au domaine/adresse ou nonce actif remplaçable"
}
if ($rate -match 'HashMap|Mutex' -or $rate -notmatch 'ON CONFLICT\(client_key\) DO UPDATE') {
    throw "Rate limit: compteur PostgreSQL atomique absent"
}
if ($guardsMigration -notmatch 'CREATE TABLE auth_nonces' -or $guardsMigration -notmatch 'CREATE TABLE api_rate_limits') {
    throw "Migration des garde-fous distribués absente"
}
if ($rewardPoolConfig -notmatch '"enabled"\s*:\s*false' -or $rewardPoolConfig -notmatch '"settlementEnabled"\s*:\s*false') {
    throw "Reward pool: configuration livrée doit rester fail-closed"
}
if ($main -match '\.route\([^\r\n]*reward.pool' -or $main -match '\.route\([^\r\n]*settlement') {
    throw "Reward pool: route client de payout interdite"
}
if ($rewardPool -notmatch 'pg_advisory_xact_lock' -or $rewardPool -notmatch 'record_settlement_tx') {
    throw "Reward pool: budget atomique ou point d'entrée provider absent"
}
if ($rewardPoolMigration -notmatch 'CREATE TABLE reward_pool_allocations' -or $rewardPoolMigration -notmatch 'CREATE TABLE reward_pool_settlements') {
    throw "Reward pool: ledger SQL absent"
}
if ($authRuntime -notmatch 'hash_jti' -or $authRuntime -notmatch 'rotate_refresh_session' -or $authRuntime -notmatch 'revoke_refresh_session') {
    throw "Auth: rotation du refresh token absente"
}
if ($db -notmatch 'consumed_at IS NULL' -or $refreshMigration -notmatch 'CREATE TABLE refresh_sessions') {
    throw "Auth: ledger PostgreSQL des refresh sessions absent"
}
foreach ($invariant in @(
    'social_encounter_not_self_targeted',
    'social_encounter_resolution_consistent',
    'card_trade_resolution_consistent',
    'team_members_one_owner'
)) {
    if ($invariantsMigration -notmatch $invariant) {
        throw "Invariant SQL absent: $invariant"
    }
}
if ($net -notmatch '_refresh_in_flight' -or $net -notmatch 'token != access_token_used') {
    throw "Client: refresh single-flight / détection de rotation absente"
}
if ($main -notmatch 'route\("/ready"' -or $main -notmatch 'with_graceful_shutdown' -or
    $main -notmatch 'JWT_SECRET de démonstration interdit') {
    throw "Runtime: readiness, arrêt propre ou garde secret release absent"
}
if ($collection -match 'player\.spins\s*\+' -or $spin -notmatch 'i32::try_from\(gained') {
    throw "Économie: calcul local non vérifié du solde spins détecté"
}
if ($engagement -match 'daily_streak\s*\+\s*1' -or $game -notmatch 'mission_progress\.progress::numeric') {
    throw "Économie: progression sans protection overflow détectée"
}
if ($engagement -match '"address"\s*:\s*address' -or
    $engagement -notmatch 'pp\.friend_code,pp\.display_name,pp\.avatar_id') {
    throw "Vie privée: leaderboard événement expose l'adresse wallet"
}
if ($main -notmatch 'ANALYTICS_RETENTION_DAYS' -or
    $main -notmatch 'DELETE FROM analytics_events' -or
    $main -notmatch 'DELETE FROM economy_audit' -or
    $main -notmatch 'account_deletion_tombstones') {
    throw "Vie privée: politique de rétention exécutable absente"
}
if ($account -notmatch 'GET /account/export' -or $account -notmatch 'POST /account/delete' -or
    $account -notmatch 'DELETE CYBERSEEKER ACCOUNT' -or
    $privacyMigration -notmatch 'CREATE TABLE account_deletion_tombstones') {
    throw "Vie privée: export ou effacement idempotent absent"
}

foreach ($scope in @('event_claim:', 'season_claim:')) {
    $start = $engagement.IndexOf($scope)
    if ($start -lt 0) { throw "Scope idempotence absent: $scope" }
    $slice = $engagement.Substring($start, [Math]::Min(5000, $engagement.Length - $start))
    if ($slice -notmatch 'fetch_idempotent_locked') { throw "Relecture idempotence sous verrou absente: $scope" }
}

$mutationFiles = @("collection.rs", "commerce.rs", "district.rs", "engagement.rs", "friends.rs", "social.rs", "spin.rs", "teams.rs", "trading.rs")
foreach ($file in $mutationFiles) {
    $content = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $server $file) -Raw
    if ($content -notmatch 'request_id\(' -or $content -notmatch 'store_idempotent') {
        throw "Mutation sans contrat request-id/idempotence détectée dans $file"
    }
}

[pscustomobject]@{
    MutationModules = $mutationFiles.Count
    Base58CasePreserved = $true
    EntitlementsFailClosed = $true
    DistributedGuards = $true
    RewardPoolFailClosed = $true
    RefreshRotation = $true
    ReleaseDevAuthBlocked = $true
    DomainBoundChallenge = $true
    PrivacyControls = $true
} | Format-List
Write-Host "SECURITY_CHECK_OK" -ForegroundColor Green
