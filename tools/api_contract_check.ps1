param(
    [string]$BaseUrl = "http://127.0.0.1:8084",
    [string]$DevAddress = "dev-player-0001"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd('/')

# Windows PowerShell 5.1 ne charge pas System.Net.Http tout seul : sans ce
# chargement explicite, le test de concurrence (HttpClient) ne marche que si
# un autre outil a deja charge l'assembly dans la session.
Add-Type -AssemblyName System.Net.Http

$health = Invoke-RestMethod -Uri ($BaseUrl + "/health") -UseBasicParsing
$ready = Invoke-RestMethod -Uri ($BaseUrl + "/ready") -UseBasicParsing
if ($health.status -ne "ok" -or $ready.status -ne "ready" -or $ready.database -ne $true) {
    throw "Health/readiness invalide"
}

function Invoke-JsonPost([string]$Path, [hashtable]$Body) {
    try {
        $response = Invoke-WebRequest -Uri ($BaseUrl + $Path) -Method POST `
            -ContentType "application/json" -Body ($Body | ConvertTo-Json -Compress) `
            -UseBasicParsing
        return [pscustomobject]@{
            Code = [int]$response.StatusCode
            Raw = $response.Content
            Data = $response.Content | ConvertFrom-Json
        }
    } catch {
        $code = [int]$_.Exception.Response.StatusCode
        $raw = $_.ErrorDetails.Message
        $data = $null
        if ($raw) {
            try { $data = $raw | ConvertFrom-Json } catch { }
        }
        return [pscustomobject]@{ Code = $code; Raw = $raw; Data = $data }
    }
}

function Invoke-State([string]$AccessToken) {
    $headers = @{ Authorization = "Bearer $AccessToken" }
    $response = Invoke-WebRequest -Uri ($BaseUrl + "/state") -Headers $headers -UseBasicParsing
    if ([int]$response.StatusCode -ne 200) { throw "GET /state: HTTP $($response.StatusCode)" }
    return $response.Content | ConvertFrom-Json
}

function Invoke-ProtectedJsonPost(
    [string]$Path,
    [string]$AccessToken,
    [hashtable]$Body,
    [string]$RequestId
) {
    $headers = @{
        Authorization = "Bearer $AccessToken"
        "x-request-id" = $RequestId
    }
    try {
        $response = Invoke-WebRequest -Uri ($BaseUrl + $Path) -Method POST `
            -Headers $headers -ContentType "application/json" `
            -Body ($Body | ConvertTo-Json -Compress) -UseBasicParsing
        return [pscustomobject]@{
            Code = [int]$response.StatusCode
            Raw = $response.Content
            Data = $response.Content | ConvertFrom-Json
        }
    } catch {
        $code = [int]$_.Exception.Response.StatusCode
        $raw = $_.ErrorDetails.Message
        $data = $null
        if ($raw) {
            try { $data = $raw | ConvertFrom-Json } catch { }
        }
        return [pscustomobject]@{ Code = $code; Raw = $raw; Data = $data }
    }
}

$challenge = Invoke-JsonPost "/auth/challenge" @{ address = $DevAddress }
if ($challenge.Code -ne 200 -or -not $challenge.Data.nonce) {
    throw "Auth challenge invalide: HTTP $($challenge.Code)"
}
$verify = Invoke-JsonPost "/auth/verify" @{ address = $DevAddress; signature = "dev" }
if ($verify.Code -ne 200 -or -not $verify.Data.token -or -not $verify.Data.refreshToken) {
    throw "Auth verify invalide: HTTP $($verify.Code)"
}

# Offres : le catalogue et l'éligibilité sont serveur-authoritative. Cette gate
# utilise volontairement un compte DEV neuf afin d'exercer l'offre starter.
$authHeaders = @{ Authorization = "Bearer $($verify.Data.token)" }
$offersResponse = Invoke-WebRequest -Uri ($BaseUrl + "/offers") -Headers $authHeaders -UseBasicParsing
$offers = $offersResponse.Content | ConvertFrom-Json
$starter = $offers.items | Where-Object { $_.offerId -eq "welcome_signal" } | Select-Object -First 1
if (-not $starter) { throw "Offre starter absente : utiliser un DevAddress neuf" }
$beforePurchase = Invoke-State $verify.Data.token
$wrongPurchase = Invoke-ProtectedJsonPost "/purchase/verify" $verify.Data.token @{
    offerId = $starter.offerId
    txSignature = "dev:wrong-" + [guid]::NewGuid().ToString("N")
    tokenMint = $starter.priceToken
    amountU64 = [uint64]$starter.priceU64 + 1
} ("purchase-wrong-" + [guid]::NewGuid().ToString("N"))
if ($wrongPurchase.Code -ne 400 -or $wrongPurchase.Data.error.code -ne "BAD_REQUEST") {
    throw "Un montant d'achat incorrect n'a pas été refusé"
}
$purchaseId = "purchase-" + [guid]::NewGuid().ToString("N")
$purchaseBody = @{
    offerId = $starter.offerId
    txSignature = "dev:" + [guid]::NewGuid().ToString("N")
    tokenMint = $starter.priceToken
    amountU64 = [uint64]$starter.priceU64
    requestId = $purchaseId
}
$purchase = Invoke-ProtectedJsonPost "/purchase/verify" $verify.Data.token $purchaseBody $purchaseId
$purchaseReplay = Invoke-ProtectedJsonPost "/purchase/verify" $verify.Data.token $purchaseBody $purchaseId
if ($purchase.Code -ne 200 -or $purchaseReplay.Code -ne 200 -or
    $purchase.Raw -cne $purchaseReplay.Raw) {
    throw "Achat DEV non idempotent"
}
$afterPurchase = Invoke-State $verify.Data.token
$expectedSpins = [int64]($starter.contents | Where-Object type -eq "spins" |
    Measure-Object -Property amount -Sum).Sum
$expectedCredits = [int64]($starter.contents | Where-Object type -eq "credits" |
    Measure-Object -Property amount -Sum).Sum
if ([int64]$afterPurchase.spins -ne [int64]$beforePurchase.spins + $expectedSpins -or
    [int64]$afterPurchase.credits -ne [int64]$beforePurchase.credits + $expectedCredits) {
    throw "Crédit de l'offre starter incohérent"
}

$stateBefore = $afterPurchase
if ([int64]$stateBefore.spins -lt 4) { throw "Compte de test sans 4 spins" }

$requestId = "api-contract-" + [guid]::NewGuid().ToString("N")
$spinBody = @{ requestId = $requestId; multiplier = 4 } | ConvertTo-Json -Compress
$client = [System.Net.Http.HttpClient]::new()
try {
    function New-SpinRequest {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post,
            $BaseUrl + "/spin"
        )
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new(
            "Bearer",
            [string]$verify.Data.token
        )
        [void]$request.Headers.TryAddWithoutValidation("x-request-id", $requestId)
        $request.Content = [System.Net.Http.StringContent]::new(
            $spinBody,
            [System.Text.Encoding]::UTF8,
            "application/json"
        )
        return $request
    }

    $firstTask = $client.SendAsync((New-SpinRequest))
    $secondTask = $client.SendAsync((New-SpinRequest))
    [System.Threading.Tasks.Task]::WaitAll(
        [System.Threading.Tasks.Task[]]@($firstTask, $secondTask)
    )
    $first = $firstTask.Result
    $second = $secondTask.Result
    $firstRaw = $first.Content.ReadAsStringAsync().Result
    $secondRaw = $second.Content.ReadAsStringAsync().Result
    if ([int]$first.StatusCode -ne 200 -or [int]$second.StatusCode -ne 200) {
        throw "Spins concurrents: HTTP $([int]$first.StatusCode)/$([int]$second.StatusCode)"
    }
    if ($firstRaw -cne $secondRaw) { throw "Rejeu idempotent: réponses différentes" }
    $spin = $firstRaw | ConvertFrom-Json
} finally {
    $client.Dispose()
}

if ([int64]$spin.multiplier -ne 4 -or [int64]$spin.spinsSpent -ne 4) {
    throw "Contrat multiplicateur ×4 invalide"
}
if ([int64]$spin.creditsGained -ne ([int64]$spin.baseCreditsGained * 4)) {
    throw "Récompense ×4 incohérente"
}
if ([int64]$spin.spins -ne ([int64]$stateBefore.spins - 4)) {
    throw "Le rejeu concurrent a consommé plus d'une mise"
}
$stateAfter = Invoke-State $verify.Data.token
if ([int64]$stateAfter.spins -ne [int64]$spin.spins -or
    [int64]$stateAfter.credits -ne [int64]$spin.credits) {
    throw "GET /state diverge de la réponse autoritaire du spin"
}
$activeEvent = $stateAfter.events | Select-Object -First 1
if ($activeEvent) {
    $leaderboardResponse = Invoke-WebRequest `
        -Uri ($BaseUrl + "/events/" + $activeEvent.eventId + "/leaderboard") `
        -Headers $authHeaders -UseBasicParsing
    $leaderboard = $leaderboardResponse.Content | ConvertFrom-Json
    $leader = $leaderboard.leaders | Select-Object -First 1
    if (-not $leader -or -not $leader.displayName -or -not $leader.playerId -or
        $leader.PSObject.Properties.Name -contains "address") {
        throw "Leaderboard événement: profil public invalide ou adresse exposée"
    }
}

# Publicité récompensée : une preuve DEV crédite une fois, son requestId rejoue
# la même réponse et une nouvelle preuve immédiate est bloquée par le cooldown.
$adRequestId = "ad-" + [guid]::NewGuid().ToString("N")
$adBody = @{
    receipt = "dev:" + [guid]::NewGuid().ToString("N")
    requestId = $adRequestId
}
$ad = Invoke-ProtectedJsonPost "/ad/reward" $verify.Data.token $adBody $adRequestId
$adReplay = Invoke-ProtectedJsonPost "/ad/reward" $verify.Data.token $adBody $adRequestId
if ($ad.Code -ne 200 -or $adReplay.Code -ne 200 -or $ad.Raw -cne $adReplay.Raw) {
    throw "Récompense publicitaire non idempotente"
}
$afterAd = Invoke-State $verify.Data.token
if ([int64]$afterAd.spins -ne [int64]$stateAfter.spins + [int64]$ad.Data.rewardSpins) {
    throw "Crédit publicitaire incohérent"
}
$cooldown = Invoke-ProtectedJsonPost "/ad/reward" $verify.Data.token @{
    receipt = "dev:" + [guid]::NewGuid().ToString("N")
    requestId = "ad-cooldown-" + [guid]::NewGuid().ToString("N")
} ("ad-cooldown-header-" + [guid]::NewGuid().ToString("N"))
if ($cooldown.Code -ne 403 -or $cooldown.Data.error.code -ne "UNAVAILABLE") {
    throw "Cooldown publicitaire non appliqué"
}

$logout = Invoke-JsonPost "/auth/logout" @{ refreshToken = $verify.Data.refreshToken }
if ($logout.Code -ne 200 -or $logout.Data.revoked -ne $true) {
    throw "Logout non révoqué: HTTP $($logout.Code)"
}
$refreshAfterLogout = Invoke-JsonPost "/auth/refresh" @{ refreshToken = $verify.Data.refreshToken }
if ($refreshAfterLogout.Code -ne 401 -or $refreshAfterLogout.Data.error.code -ne "UNAUTHORIZED") {
    throw "Refresh révoqué encore accepté"
}

[pscustomobject]@{
    ConcurrentSpinStatus = "200/200"
    Health = "ok"
    Readiness = "ready"
    Multiplier = [int]$spin.multiplier
    SpinsSpent = [int]$spin.spinsSpent
    IdempotentReplay = $true
    StateMatches = $true
    LeaderboardProfileOnly = $true
    StarterOfferIdempotent = $true
    WrongPurchaseRejected = $true
    RewardedAdIdempotent = $true
    AdCooldown = 403
    LogoutRevoked = $true
    RefreshAfterLogout = 401
} | Format-List
Write-Host "API_CONTRACT_CHECK_OK" -ForegroundColor Green
