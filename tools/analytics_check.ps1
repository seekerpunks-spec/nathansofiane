$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$expected = @(
    "session_start",
    "spin_started",
    "spin_completed",
    "spins_empty",
    "multiplier_changed",
    "currency_earned",
    "currency_spent",
    "upgrade_started",
    "upgrade_completed",
    "village_completed",
    "chest_opened",
    "card_received",
    "new_card",
    "duplicate_card",
    "set_completed",
    "daily_claim",
    "daily_bonus_claim",
    "event_progress",
    "milestone_claim",
    "leaderboard_join",
    "leaderboard_finish",
    "rewarded_ad_offer",
    "rewarded_ad_complete",
    "purchase_offer_view",
    "purchase_started",
    "purchase_complete",
    "attack_started",
    "attack_completed",
    "raid_started",
    "raid_node_revealed",
    "raid_cashout",
    "raid_failed",
    "repair_started",
    "repair_completed",
    "profile_updated",
    "friend_request_sent",
    "friend_request_accepted",
    "friend_request_declined",
    "social_target_selected",
    "team_created",
    "team_joined",
    "team_left",
    "team_owner_transferred",
    "team_member_kicked",
    "trade_created",
    "trade_accepted",
    "trade_declined",
    "trade_cancelled"
)

$sources = Get-ChildItem -LiteralPath (Join-Path $workspace "client") -Filter "*.gd" -Recurse |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
$joined = $sources -join "`n"
$missing = @($expected | Where-Object { $joined -notmatch [regex]::Escape('"' + $_ + '"') })
if ($missing.Count -gt 0) {
    throw "Événements analytics absents du client: $($missing -join ', ')"
}

[pscustomobject]@{
    RequiredEvents = $expected.Count
    MissingEvents = $missing.Count
} | Format-List
Write-Host "ANALYTICS_CHECK_OK" -ForegroundColor Green
