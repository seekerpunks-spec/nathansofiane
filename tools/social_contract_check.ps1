param(
    [string]$BaseUrl = "http://127.0.0.1:8084",
    [string]$SecondaryAuthBaseUrl = "",
    [string]$DevAddressPrefix = "dev-social",
    [string]$AlphaAddress = "",
    [string]$BetaAddress = ""
)

# Deux processus DEV_AUTH sont nécessaires car une instance n'accepte qu'une
# DEV_ADDRESS. Ils partagent PostgreSQL et JWT_SECRET ; toutes les mutations
# protégées sont ensuite exercées sur BaseUrl avec les deux access tokens.
$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd('/')
$SecondaryAuthBaseUrl = $SecondaryAuthBaseUrl.TrimEnd('/')
$runId = [guid]::NewGuid().ToString("N").Substring(0, 12)
if (-not $SecondaryAuthBaseUrl) { $SecondaryAuthBaseUrl = $BaseUrl }
if (-not $AlphaAddress) { $AlphaAddress = "$DevAddressPrefix-alpha-$runId" }
if (-not $BetaAddress) { $BetaAddress = "$DevAddressPrefix-beta-$runId" }
if ($AlphaAddress -eq $BetaAddress) { throw "AlphaAddress et BetaAddress doivent différer" }

function Invoke-JsonPost([string]$Path, [hashtable]$Body, [string]$RootUrl = $BaseUrl) {
    try {
        $response = Invoke-WebRequest -Uri ($RootUrl + $Path) -Method POST `
            -ContentType "application/json" -Body ($Body | ConvertTo-Json -Compress -Depth 20) `
            -UseBasicParsing
        return [pscustomobject]@{
            Code = [int]$response.StatusCode
            Raw = $response.Content
            Data = $response.Content | ConvertFrom-Json
        }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $raw = $_.ErrorDetails.Message
        $data = $null
        if ($raw) { try { $data = $raw | ConvertFrom-Json } catch { } }
        return [pscustomobject]@{ Code = $code; Raw = $raw; Data = $data }
    }
}

function Invoke-ProtectedGet([string]$Path, [string]$Token) {
    try {
        $response = Invoke-WebRequest -Uri ($BaseUrl + $Path) `
            -Headers @{ Authorization = "Bearer $Token" } -UseBasicParsing
        return [pscustomobject]@{
            Code = [int]$response.StatusCode
            Raw = $response.Content
            Data = $response.Content | ConvertFrom-Json
        }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $raw = $_.ErrorDetails.Message
        $data = $null
        if ($raw) { try { $data = $raw | ConvertFrom-Json } catch { } }
        return [pscustomobject]@{ Code = $code; Raw = $raw; Data = $data }
    }
}

function Invoke-ProtectedPost(
    [string]$Path,
    [string]$Token,
    [hashtable]$Body,
    [string]$RequestId
) {
    $headers = @{
        Authorization = "Bearer $Token"
        "x-request-id" = $RequestId
    }
    try {
        $response = Invoke-WebRequest -Uri ($BaseUrl + $Path) -Method POST `
            -Headers $headers -ContentType "application/json" `
            -Body ($Body | ConvertTo-Json -Compress -Depth 20) -UseBasicParsing
        return [pscustomobject]@{
            Code = [int]$response.StatusCode
            Raw = $response.Content
            Data = $response.Content | ConvertFrom-Json
        }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $raw = $_.ErrorDetails.Message
        $data = $null
        if ($raw) { try { $data = $raw | ConvertFrom-Json } catch { } }
        return [pscustomobject]@{ Code = $code; Raw = $raw; Data = $data }
    }
}

function Assert-Ok($Response, [string]$Context) {
    if ($Response.Code -ne 200) {
        throw "$Context : HTTP $($Response.Code) $($Response.Raw)"
    }
}

function Get-State($Player) {
    $response = Invoke-ProtectedGet "/state" $Player.Token
    Assert-Ok $response "GET /state pour $($Player.Address)"
    return $response.Data
}

function New-TestPlayer(
    [string]$Suffix,
    [string]$DisplayName,
    [string]$Address,
    [string]$AuthBaseUrl
) {
    $address = $Address
    $challenge = Invoke-JsonPost "/auth/challenge" @{ address = $address } $AuthBaseUrl
    Assert-Ok $challenge "challenge $Suffix"
    if (-not $challenge.Data.nonce) { throw "challenge $Suffix sans nonce" }
    $verify = Invoke-JsonPost "/auth/verify" @{ address = $address; signature = "dev" } $AuthBaseUrl
    Assert-Ok $verify "verify $Suffix"
    if (-not $verify.Data.token) { throw "verify $Suffix sans token" }

    $player = [pscustomobject]@{
        Address = $address
        Token = [string]$verify.Data.token
        RefreshToken = [string]$verify.Data.refreshToken
        PlayerId = ""
    }
    $profileRid = "social-profile-$Suffix-$runId"
    $profile = Invoke-ProtectedPost "/profile" $player.Token @{
        displayName = $DisplayName
        requestId = $profileRid
    } $profileRid
    Assert-Ok $profile "profil $Suffix"
    $player.PlayerId = [string]$profile.Data.playerId

    $offers = Invoke-ProtectedGet "/offers" $player.Token
    Assert-Ok $offers "offres $Suffix"
    $starter = $offers.Data.items | Where-Object { $_.offerId -eq "welcome_signal" } |
        Select-Object -First 1
    if ($starter) {
        $purchaseRid = "social-purchase-$Suffix-$runId"
        $purchaseBody = @{
            offerId = [string]$starter.offerId
            txSignature = "dev:social-$Suffix-$runId"
            tokenMint = [string]$starter.priceToken
            amountU64 = [uint64]$starter.priceU64
            requestId = $purchaseRid
        }
        $purchase = Invoke-ProtectedPost "/purchase/verify" $player.Token $purchaseBody $purchaseRid
        $purchaseReplay = Invoke-ProtectedPost "/purchase/verify" $player.Token $purchaseBody $purchaseRid
        Assert-Ok $purchase "starter $Suffix"
        Assert-Ok $purchaseReplay "rejeu starter $Suffix"
        if ($purchase.Raw -cne $purchaseReplay.Raw) { throw "starter $Suffix non idempotent" }
    } else {
        $existing = Get-State $player
        if ([int64]$existing.spins -lt 50 -or [int64]$existing.credits -lt 200000) {
            throw "compte $Suffix réutilisé sans ressources suffisantes"
        }
    }
    return $player
}

function Invoke-DebugSpin(
    $Player,
    [string]$OutcomeId,
    [int]$Multiplier = 1,
    [string]$TargetAddress = ""
) {
    $rid = "social-spin-$OutcomeId-" + [guid]::NewGuid().ToString("N")
    $body = @{
        requestId = $rid
        multiplier = $Multiplier
        debugOutcomeId = $OutcomeId
    }
    if ($TargetAddress) { $body.debugTargetAddress = $TargetAddress }
    $response = Invoke-ProtectedPost "/spin" $Player.Token $body $rid
    Assert-Ok $response "spin debug $OutcomeId"
    if ([string]$response.Data.outcome.id -ne $OutcomeId) {
        throw "spin debug divergent : $($response.Data.outcome.id) au lieu de $OutcomeId"
    }
    return $response
}

function Get-CardQuantity($State, [string]$CardId) {
    $row = $State.cards | Where-Object { $_.cardId -eq $CardId } | Select-Object -First 1
    if (-not $row) { return [int64]0 }
    return [int64]$row.qty
}

$health = Invoke-WebRequest -Uri ($BaseUrl + "/health") -UseBasicParsing
$ready = Invoke-WebRequest -Uri ($BaseUrl + "/ready") -UseBasicParsing
if (($health.Content | ConvertFrom-Json).status -ne "ok" -or
    ($ready.Content | ConvertFrom-Json).status -ne "ready") {
    throw "serveur social non prêt"
}
$remoteConfig = (Invoke-WebRequest -Uri ($BaseUrl + "/config") -UseBasicParsing).Content |
    ConvertFrom-Json
$district = $remoteConfig.payload.districts | Select-Object -First 1
$element = $district.elements | Select-Object -First 1
if (-not $district -or -not $element) { throw "configuration district vide" }
$tradeableRarities = @($remoteConfig.payload.social.trading.tradeableRarities)
$tradeableCardIds = @($remoteConfig.payload.cards |
    Where-Object { $tradeableRarities -contains $_.rarity } |
    ForEach-Object { [string]$_.cardId })

$alpha = New-TestPlayer "alpha" "Neon Alpha" $AlphaAddress $BaseUrl
$beta = New-TestPlayer "beta" "Neon Beta" $BetaAddress $SecondaryAuthBaseUrl

# Les deux joueurs construisent un nœud : cibles Attack/Revenge réelles, jamais
# la cible corporate de secours.
foreach ($player in @($alpha, $beta)) {
    $rid = "social-upgrade-" + [guid]::NewGuid().ToString("N")
    $upgrade = Invoke-ProtectedPost "/district/upgrade" $player.Token @{
        districtId = [int]$district.id
        elementId = [int]$element.id
        requestId = $rid
    } $rid
    Assert-Ok $upgrade "upgrade $($player.Address)"
    if ([int]$upgrade.Data.level -ne 1) { throw "upgrade initial différent de 1" }
}

# Invitation, acceptation et lecture bilatérale.
$friendRid = "social-friend-$runId"
$friendBody = @{ friendCode = $beta.PlayerId; requestId = $friendRid }
$friend = Invoke-ProtectedPost "/friends/request" $alpha.Token $friendBody $friendRid
$friendReplay = Invoke-ProtectedPost "/friends/request" $alpha.Token $friendBody $friendRid
Assert-Ok $friend "demande d'ami"
Assert-Ok $friendReplay "rejeu demande d'ami"
if ($friend.Raw -cne $friendReplay.Raw) { throw "demande d'ami non idempotente" }
$acceptRid = "social-accept-$runId"
$accept = Invoke-ProtectedPost "/friends/accept" $beta.Token @{
    friendCode = $alpha.PlayerId
    requestId = $acceptRid
} $acceptRid
Assert-Ok $accept "acceptation ami"
$alphaNetwork = Invoke-ProtectedGet "/friends" $alpha.Token
$betaNetwork = Invoke-ProtectedGet "/friends" $beta.Token
Assert-Ok $alphaNetwork "réseau alpha"
Assert-Ok $betaNetwork "réseau beta"
if (-not ($alphaNetwork.Data.friends | Where-Object playerId -eq $beta.PlayerId) -or
    -not ($betaNetwork.Data.friends | Where-Object playerId -eq $alpha.PlayerId)) {
    throw "amitié absente d'un snapshot réseau"
}

# Une préférence ami doit être autorisée et consommable par le prochain Attack.
$targetRid = "social-target-friend-$runId"
$target = Invoke-ProtectedPost "/social/target" $alpha.Token @{
    friendCode = $beta.PlayerId
    source = "friend"
    requestId = $targetRid
} $targetRid
Assert-Ok $target "sélection cible amie"

# Firewall 0→3 via une seule animation ×3, puis trois attaques bloquées et une
# quatrième qui endommage réellement le district.
$shield = Invoke-DebugSpin $beta "firewall" 3
$betaState = Get-State $beta
if ([int]$betaState.firewallCharges -ne 3) { throw "Firewall ×3 n'a pas produit 3 charges" }

$lastAttack = $null
for ($attackIndex = 0; $attackIndex -lt 4; $attackIndex++) {
    $spin = Invoke-DebugSpin $alpha "signal_jam" 1 $beta.Address
    $encounter = $spin.Data.pendingEncounter
    if (-not $encounter -or $encounter.kind -ne "attack") { throw "encounter Attack absent" }
    $choice = @($encounter.choices) | Select-Object -First 1
    if ($null -eq $choice) { throw "Attack sans choix de nœud" }
    $resolveRid = "social-attack-$attackIndex-$runId"
    $resolveBody = @{
        encounterId = [string]$encounter.encounterId
        elementId = [int]$choice
        requestId = $resolveRid
    }
    $resolve = Invoke-ProtectedPost "/attack/resolve" $alpha.Token $resolveBody $resolveRid
    $resolveReplay = Invoke-ProtectedPost "/attack/resolve" $alpha.Token $resolveBody $resolveRid
    Assert-Ok $resolve "résolution Attack $attackIndex"
    Assert-Ok $resolveReplay "rejeu Attack $attackIndex"
    if ($resolve.Raw -cne $resolveReplay.Raw) { throw "Attack $attackIndex non idempotent" }
    $expectedBlocked = $attackIndex -lt 3
    if ([bool]$resolve.Data.blocked -ne $expectedBlocked) {
        throw "Attack $attackIndex : blocked=$($resolve.Data.blocked), attendu=$expectedBlocked"
    }
    $lastAttack = $resolve.Data
}
$betaState = Get-State $beta
if ([int]$betaState.firewallCharges -ne 0) { throw "les Firewalls n'ont pas été consommés exactement" }
$damage = @($betaState.districtDamage | Where-Object {
    [int]$_.districtId -eq [int]$district.id -and [int]$_.elementId -eq [int]$lastAttack.elementId
})
if ($damage.Count -ne 1) { throw "dégât Attack absent ou dupliqué" }

# Journal de revanche et sélection revenge. Alpha possède aussi un nœud valide.
$betaNetwork = Invoke-ProtectedGet "/friends" $beta.Token
Assert-Ok $betaNetwork "journal de revanche"
$revengeRow = $betaNetwork.Data.recentAttacks | Where-Object {
    $_.playerId -eq $alpha.PlayerId -and $_.canRevenge -eq $true
} | Select-Object -First 1
if (-not $revengeRow) { throw "revanche absente du journal Beta" }
$revengeRid = "social-target-revenge-$runId"
$revenge = Invoke-ProtectedPost "/social/target" $beta.Token @{
    friendCode = $alpha.PlayerId
    source = "revenge"
    requestId = $revengeRid
} $revengeRid
Assert-Ok $revenge "sélection revanche"

# Réparation serveur-authoritative du seul dégât créé.
$repairRid = "social-repair-$runId"
$repair = Invoke-ProtectedPost "/district/repair" $beta.Token @{
    districtId = [int]$district.id
    elementId = [int]$lastAttack.elementId
    requestId = $repairRid
} $repairRid
Assert-Ok $repair "réparation district"
if ($repair.Data.repaired -ne $true -or @((Get-State $beta).districtDamage).Count -ne 0) {
    throw "réparation non appliquée"
}

# Ghost Vault réel contre Beta. Le plateau est secret ; on réessaie uniquement
# si le premier nœud est l'unique trace (probabilité d'échec total < 1/6^12).
$raidCashout = $null
for ($attempt = 0; $attempt -lt 12 -and -not $raidCashout; $attempt++) {
    $raidSpin = Invoke-DebugSpin $alpha "ghost_vault" 1 $beta.Address
    $raid = $raidSpin.Data.pendingEncounter
    if (-not $raid -or $raid.kind -ne "raid") { throw "encounter Raid absent" }
    $pickRid = "social-raid-pick-$attempt-$runId"
    $pick = Invoke-ProtectedPost "/raid/pick" $alpha.Token @{
        encounterId = [string]$raid.encounterId
        nodeIndex = 0
        requestId = $pickRid
    } $pickRid
    Assert-Ok $pick "pick Raid $attempt"
    if ($pick.Data.failed -eq $true) { continue }
    if ($pick.Data.canCashout -ne $true -or [int64]$pick.Data.unbankedCredits -le 0) {
        throw "pick Raid sûr sans cashout ni gain non banké"
    }
    $alphaBeforeCashout = Get-State $alpha
    $betaBeforeCashout = Get-State $beta
    $cashoutRid = "social-raid-cashout-$attempt-$runId"
    $cashoutBody = @{ encounterId = [string]$raid.encounterId; requestId = $cashoutRid }
    $cashout = Invoke-ProtectedPost "/raid/cashout" $alpha.Token $cashoutBody $cashoutRid
    $cashoutReplay = Invoke-ProtectedPost "/raid/cashout" $alpha.Token $cashoutBody $cashoutRid
    Assert-Ok $cashout "cashout Raid"
    Assert-Ok $cashoutReplay "rejeu cashout Raid"
    if ($cashout.Raw -cne $cashoutReplay.Raw) { throw "cashout Raid non idempotent" }
    $reward = [int64]$cashout.Data.rewardCredits
    $alphaAfterCashout = Get-State $alpha
    $betaAfterCashout = Get-State $beta
    if ($reward -le 0 -or
        [int64]$alphaAfterCashout.credits -ne [int64]$alphaBeforeCashout.credits + $reward -or
        [int64]$betaAfterCashout.credits -ne [int64]$betaBeforeCashout.credits - $reward) {
        throw "transfert Raid non conservatif"
    }
    $raidCashout = $cashout.Data
}
if (-not $raidCashout) { throw "aucun premier nœud Raid sûr en 12 tentatives" }

# Le debug DEV Card donne multiplier exemplaires d'une même carte : ×2 produit
# un doublon sans toucher directement la base. On cherche deux cartes distinctes
# échangeables puis on prouve le transfert atomique et son rejeu.
$alphaCard = ""
$betaCard = ""
for ($cardAttempt = 0; $cardAttempt -lt 12 -and (-not $alphaCard -or -not $betaCard); $cardAttempt++) {
    $null = Invoke-DebugSpin $alpha "signal_card" 2
    $null = Invoke-DebugSpin $beta "signal_card" 2
    $alphaCards = @((Get-State $alpha).cards | Where-Object {
        [int64]$_.qty -ge 2 -and $tradeableCardIds -contains [string]$_.cardId
    })
    $betaCards = @((Get-State $beta).cards | Where-Object {
        [int64]$_.qty -ge 2 -and $tradeableCardIds -contains [string]$_.cardId
    })
    foreach ($aCard in $alphaCards) {
        $different = $betaCards | Where-Object cardId -ne $aCard.cardId | Select-Object -First 1
        if ($different) {
            $alphaCard = [string]$aCard.cardId
            $betaCard = [string]$different.cardId
            break
        }
    }
}
if (-not $alphaCard -or -not $betaCard) { throw "doublons échangeables distincts introuvables" }
$alphaBeforeTrade = Get-State $alpha
$betaBeforeTrade = Get-State $beta
$tradeRid = "social-trade-create-$runId"
$tradeBody = @{
    recipientFriendCode = $beta.PlayerId
    offeredCardId = $alphaCard
    requestedCardId = $betaCard
    requestId = $tradeRid
}
$trade = Invoke-ProtectedPost "/trades/create" $alpha.Token $tradeBody $tradeRid
$tradeReplay = Invoke-ProtectedPost "/trades/create" $alpha.Token $tradeBody $tradeRid
Assert-Ok $trade "création échange"
Assert-Ok $tradeReplay "rejeu création échange"
if ($trade.Raw -cne $tradeReplay.Raw) { throw "création échange non idempotente" }
$acceptTradeRid = "social-trade-accept-$runId"
$acceptTradeBody = @{ tradeId = [string]$trade.Data.tradeId; requestId = $acceptTradeRid }
$acceptedTrade = Invoke-ProtectedPost "/trades/accept" $beta.Token $acceptTradeBody $acceptTradeRid
$acceptedTradeReplay = Invoke-ProtectedPost "/trades/accept" $beta.Token $acceptTradeBody $acceptTradeRid
Assert-Ok $acceptedTrade "acceptation échange"
Assert-Ok $acceptedTradeReplay "rejeu acceptation échange"
if ($acceptedTrade.Raw -cne $acceptedTradeReplay.Raw) { throw "acceptation échange non idempotente" }
$alphaAfterTrade = Get-State $alpha
$betaAfterTrade = Get-State $beta
if ((Get-CardQuantity $alphaAfterTrade $alphaCard) -ne (Get-CardQuantity $alphaBeforeTrade $alphaCard) - 1 -or
    (Get-CardQuantity $alphaAfterTrade $betaCard) -ne (Get-CardQuantity $alphaBeforeTrade $betaCard) + 1 -or
    (Get-CardQuantity $betaAfterTrade $betaCard) -ne (Get-CardQuantity $betaBeforeTrade $betaCard) - 1 -or
    (Get-CardQuantity $betaAfterTrade $alphaCard) -ne (Get-CardQuantity $betaBeforeTrade $alphaCard) + 1) {
    throw "quantités de cartes incohérentes après échange"
}

[pscustomobject]@{
    Players = 2
    Friendship = "bilateral"
    FriendTarget = "accepted"
    Firewall = "3 blocked + 1 damage"
    Revenge = "available"
    Repair = "applied"
    RaidReward = [int64]$raidCashout.rewardCredits
    RaidConservative = $true
    Trade = "$alphaCard <-> $betaCard"
    TradeIdempotent = $true
} | Format-List
Write-Host "SOCIAL_CONTRACT_CHECK_OK" -ForegroundColor Green
