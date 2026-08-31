//! Bonus quotidien, missions, événements, classement et saison.

use crate::auth::Addr;
use crate::config::{DailyBonusOutcome, EventConfig, EventWindow, RemoteConfig, Reward};
use crate::db::Db;
use crate::entitlements;
use crate::error::ApiError;
use crate::game;
use crate::progression;
use crate::reward_pool;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, Path, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::{DateTime, Duration, Utc};
use rand::Rng;
use serde::Deserialize;
use serde_json::{json, Value};

/// Fenêtre encore actionnable pour milestones/claims : occurrence active,
/// sinon la dernière terminée dont la fenêtre de claim est ouverte.
fn claimable_window(event: &EventConfig, now_ms: i64) -> Option<EventWindow> {
    if let Some(active) = event.active_window(now_ms) {
        return Some(active);
    }
    event
        .ended_windows(now_ms, 1)
        .into_iter()
        .next()
        .filter(|window| now_ms < window.ends_at_ms.saturating_add(event.claim_window_ms()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaimReq {
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MissionClaimReq {
    mission_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeasonClaimReq {
    season_id: String,
    tier: u32,
    #[serde(default)]
    premium: bool,
    #[serde(default)]
    request_id: Option<String>,
}

fn bonus_index_for_roll(outcomes: &[DailyBonusOutcome], mut roll: u32) -> Option<usize> {
    for (index, outcome) in outcomes.iter().enumerate() {
        if roll < outcome.weight {
            return Some(index);
        }
        roll = roll.checked_sub(outcome.weight)?;
    }
    None
}

pub async fn daily_bonus_for_state(
    state: &AppState,
    address: &str,
    today: chrono::NaiveDate,
) -> Result<Value, ApiError> {
    let bonus = &state.config.daily.bonus;
    let claimed_outcome: Option<String> = sqlx::query_scalar(
        "SELECT outcome_id FROM daily_bonus_claims WHERE address=$1 AND bonus_id=$2 AND claim_day=$3",
    )
    .bind(address)
    .bind(&bonus.bonus_id)
    .bind(today)
    .fetch_optional(state.db.pool())
    .await?;
    Ok(json!({
        "bonusId":bonus.bonus_id,
        "name":bonus.name,
        "available":claimed_outcome.is_none(),
        "claimedOutcomeId":claimed_outcome,
    }))
}

pub async fn team_events_for_state(
    state: &AppState,
    address: &str,
) -> Result<Vec<Value>, ApiError> {
    let team: Option<(String, String)> = sqlx::query_as(
        "SELECT tm.team_id,t.name FROM team_members tm JOIN teams t ON t.team_id=tm.team_id WHERE tm.address=$1",
    )
    .bind(address)
    .fetch_optional(state.db.pool())
    .await?;
    let Some((team_id, team_name)) = team else {
        return Ok(Vec::new());
    };
    let scores: Vec<(String, i64)> =
        sqlx::query_as("SELECT event_id,points FROM team_event_scores WHERE team_id=$1")
            .bind(&team_id)
            .fetch_all(state.db.pool())
            .await?;
    let contributions: Vec<(String, i64)> = sqlx::query_as(
        "SELECT event_id,points FROM team_event_contributions WHERE team_id=$1 AND address=$2",
    )
    .bind(&team_id)
    .bind(address)
    .fetch_all(state.db.pool())
    .await?;
    let claims: Vec<(String, i32)> =
        sqlx::query_as("SELECT event_id,milestone_index FROM team_event_claims WHERE address=$1")
            .bind(address)
            .fetch_all(state.db.pool())
            .await?;
    let now_ms = Utc::now().timestamp_millis();
    Ok(state
        .config
        .events
        .iter()
        .filter_map(|event| {
            let team_config = event.team.as_ref()?;
            let window = event.display_window(now_ms)?;
            let team_points = scores
                .iter()
                .find(|row| row.0 == window.key)
                .map(|row| row.1)
                .unwrap_or(0);
            let contribution_points = contributions
                .iter()
                .find(|row| row.0 == window.key)
                .map(|row| row.1)
                .unwrap_or(0);
            let milestones: Vec<Value> = team_config
                .milestones
                .iter()
                .enumerate()
                .map(|(index, milestone)| {
                    json!({
                        "index":index,
                        "points":milestone.points,
                        "reward":milestone.reward,
                        "claimed":claims.iter().any(|row| row.0 == window.key && row.1 == index as i32),
                    })
                })
                .collect();
            Some(json!({
                "eventId":event.event_id,
                "eventKey":window.key,
                "occurrence":window.occurrence,
                "name":team_config.name,
                "teamId":team_id,
                "teamName":team_name,
                "startsAtMs":window.starts_at_ms,
                "endsAtMs":window.ends_at_ms,
                "teamPoints":team_points,
                "contributionPoints":contribution_points,
                "minContributionPoints":team_config.min_contribution_points,
                "milestones":milestones,
            }))
        })
        .collect())
}

pub async fn achievements_for_state(
    state: &AppState,
    address: &str,
) -> Result<Vec<Value>, ApiError> {
    let totals: Vec<(String, i64)> =
        sqlx::query_as("SELECT action,amount FROM player_action_totals WHERE address=$1")
            .bind(address)
            .fetch_all(state.db.pool())
            .await?;
    let claims: Vec<String> =
        sqlx::query_scalar("SELECT achievement_id FROM achievement_claims WHERE address=$1")
            .bind(address)
            .fetch_all(state.db.pool())
            .await?;
    Ok(state
        .config
        .achievements
        .iter()
        .map(|achievement| {
            let progress = totals
                .iter()
                .find(|row| row.0 == achievement.action)
                .map(|row| row.1)
                .unwrap_or(0);
            json!({
                "achievementId":achievement.achievement_id,
                "name":achievement.name,
                "description":achievement.description,
                "action":achievement.action,
                "target":achievement.target,
                "progress":progress,
                "reward":achievement.reward,
                "claimed":claims.contains(&achievement.achievement_id),
            })
        })
        .collect())
}

pub async fn claim_daily_bonus(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<ClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("daily_bonus_claim", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let bonus = &state.config.daily.bonus;
    let total_weight = bonus
        .outcomes
        .iter()
        .try_fold(0u32, |total, outcome| total.checked_add(outcome.weight))
        .ok_or_else(|| ApiError::Internal(anyhow!("daily bonus weight overflow")))?;
    let roll = rand::rngs::OsRng.gen_range(0..total_weight);
    let outcome = bonus
        .outcomes
        .get(
            bonus_index_for_roll(&bonus.outcomes, roll)
                .ok_or_else(|| ApiError::Internal(anyhow!("daily bonus outcome absent")))?,
        )
        .ok_or_else(|| ApiError::Internal(anyhow!("daily bonus outcome invalide")))?;
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let today = Utc::now().date_naive();
    let already_claimed: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM daily_bonus_claims WHERE address=$1 AND bonus_id=$2 AND claim_day=$3)",
    )
    .bind(&addr.0)
    .bind(&bonus.bonus_id)
    .bind(today)
    .fetch_one(&mut *tx)
    .await?;
    if already_claimed {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    sqlx::query(
        "INSERT INTO daily_bonus_claims(address,bonus_id,claim_day,outcome_id) VALUES($1,$2,$3,$4)",
    )
    .bind(&addr.0)
    .bind(&bonus.bonus_id)
    .bind(today)
    .bind(&outcome.outcome_id)
    .execute(&mut *tx)
    .await?;
    game::grant_reward_tx(&mut tx, &addr.0, &outcome.reward, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({
        "bonusId":bonus.bonus_id,"name":bonus.name,
        "outcomeId":outcome.outcome_id,"outcomeName":outcome.name,"reward":outcome.reward,
        "spins":balances.0,"credits":balances.1,"serverTimeMs":Utc::now().timestamp_millis(),
    });
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "daily_bonus_claim",
        &json!({"spins":player.spins,"credits":player.credits}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn claim_daily(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<ClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("daily_claim", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(v) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(v));
    }
    let today = Utc::now().date_naive();
    if player.last_daily_claim == Some(today) {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    let streak = if player.last_daily_claim == Some(today - Duration::days(1)) {
        player
            .daily_streak
            .checked_add(1)
            .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: daily.streak")))?
    } else {
        1
    };
    let index = ((streak - 1) as usize) % state.config.daily.cycle.len();
    let entry = &state.config.daily.cycle[index];
    let entitlement_perks =
        entitlements::effective_perks_tx(&mut tx, &addr.0, &state.config).await?;
    let reward = Reward {
        spins: entry
            .spins
            .checked_add(entitlement_perks.daily_spin_bonus)
            .ok_or_else(|| ApiError::Internal(anyhow!("daily entitlement bonus overflow")))?,
        credits: entry.credits,
        chest: entry.chest.clone(),
    };
    sqlx::query("UPDATE player_state SET daily_streak=$1,last_daily_claim=$2 WHERE address=$3")
        .bind(streak)
        .bind(today)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    game::grant_reward_tx(&mut tx, &addr.0, &reward, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({"day": entry.day, "streak": streak, "reward": reward,
        "entitlementBonusSpins":entitlement_perks.daily_spin_bonus,
        "spins": balances.0, "credits": balances.1, "serverTimeMs": Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "daily_claim",
        &json!({"streak": player.daily_streak}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn claim_mission(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<MissionClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("mission_claim", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let today = Utc::now().date_naive();
    // Seul le tirage du jour est réclamable : une mission du pool non tirée
    // aujourd'hui n'existe pas côté joueur (fail-closed).
    let mission = state
        .config
        .daily_missions_for(today)
        .into_iter()
        .find(|m| m.mission_id == body.mission_id)
        .ok_or(ApiError::NotFound)?;
    let mut tx = state.db.begin().await?;
    let _player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(v) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(v));
    }
    let row: Option<(i64, bool)> = sqlx::query_as("SELECT progress,claimed FROM mission_progress WHERE address=$1 AND mission_id=$2 AND mission_day=$3 FOR UPDATE")
        .bind(&addr.0).bind(&mission.mission_id).bind(today).fetch_optional(&mut *tx).await?;
    let Some((progress, claimed)) = row else {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("mission non terminée".to_string()));
    };
    if claimed {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    if progress < mission.target as i64 {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("mission non terminée".to_string()));
    }
    sqlx::query("UPDATE mission_progress SET claimed=true WHERE address=$1 AND mission_id=$2 AND mission_day=$3")
        .bind(&addr.0).bind(&mission.mission_id).bind(today).execute(&mut *tx).await?;
    game::grant_reward_tx(&mut tx, &addr.0, &mission.reward, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({"missionId": mission.mission_id, "reward": mission.reward, "spins": balances.0, "credits": balances.1, "serverTimeMs": Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "mission_claim",
        &json!({"progress": progress}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn leaderboard(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Path(event_id): Path<String>,
) -> Result<Json<Value>, ApiError> {
    let event = state
        .config
        .events
        .iter()
        .find(|e| e.event_id == event_id)
        .ok_or(ApiError::NotFound)?;
    let window = event
        .display_window(Utc::now().timestamp_millis())
        .ok_or(ApiError::NotFound)?;
    let player_row: Option<(i64, i32)> = sqlx::query_as(
        "SELECT points,cohort_id FROM event_scores WHERE event_id=$1 AND address=$2",
    )
    .bind(&window.key)
    .bind(&addr.0)
    .fetch_optional(state.db.pool())
    .await?;
    let (player_points, cohort_id) = player_row.unwrap_or((0, 1));
    let rows: Vec<(String, String, String, i64, i64)> = sqlx::query_as(
        "SELECT pp.friend_code,pp.display_name,pp.avatar_id,ranked.points,ranked.rank FROM (\
            SELECT address,points,DENSE_RANK() OVER(ORDER BY points DESC) AS rank \
            FROM event_scores WHERE event_id=$1 AND cohort_id=$2\
         ) ranked JOIN player_profiles pp ON pp.address=ranked.address \
         ORDER BY ranked.rank,pp.friend_code LIMIT $3",
    )
    .bind(&window.key)
    .bind(cohort_id)
    .bind(event.leaderboard.display_limit as i64)
    .fetch_all(state.db.pool())
    .await?;
    let rank: i64 = if player_row.is_some() {
        sqlx::query_scalar(
            "SELECT COUNT(DISTINCT points)+1 FROM event_scores \
             WHERE event_id=$1 AND cohort_id=$2 AND points>$3",
        )
        .bind(&window.key)
        .bind(cohort_id)
        .bind(player_points)
        .fetch_one(state.db.pool())
        .await?
    } else {
        0
    };
    Ok(Json(
        json!({"eventId": event.event_id, "eventKey": window.key, "name": event.name,
        "startsAtMs": window.starts_at_ms, "endsAtMs": window.ends_at_ms,
        "cohortId": cohort_id,
        "leaders": rows.into_iter().map(|(player_id,display_name,avatar_id,points,rank)| json!({"rank": rank, "playerId": player_id, "displayName": display_name, "avatarId": avatar_id, "points": points})).collect::<Vec<_>>(),
        "player": {"rank": rank, "points": player_points, "cohortId": cohort_id}, "serverTimeMs": Utc::now().timestamp_millis()}),
    ))
}

pub async fn claim_event_milestone(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Path((event_id, milestone_index)): Path<(String, u32)>,
    headers: HeaderMap,
    Json(body): Json<ClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let event = state
        .config
        .events
        .iter()
        .find(|candidate| candidate.event_id == event_id)
        .ok_or(ApiError::NotFound)?;
    let window = claimable_window(event, Utc::now().timestamp_millis())
        .ok_or_else(|| ApiError::Unavailable("occurrence terminée".to_string()))?;
    let action = format!("event_milestone_claim:{}:{milestone_index}", window.key);
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let milestone = event
        .milestones
        .get(milestone_index as usize)
        .ok_or(ApiError::NotFound)?;
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let points: i64 = sqlx::query_scalar(
        "SELECT points FROM event_scores WHERE event_id=$1 AND address=$2 FOR UPDATE",
    )
    .bind(&window.key)
    .bind(&addr.0)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    if points < game::checked_u64_to_i64(milestone.points, "milestone.points")? {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("milestone non atteint".to_string()));
    }
    let inserted = sqlx::query(
        "INSERT INTO event_milestone_claims(event_id,address,milestone_index,auto_claimed) \
         VALUES($1,$2,$3,false) ON CONFLICT DO NOTHING",
    )
    .bind(&window.key)
    .bind(&addr.0)
    .bind(milestone_index as i32)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if inserted == 0 {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    game::grant_reward_tx(&mut tx, &addr.0, &milestone.reward, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({
        "eventId": event.event_id,
        "eventKey": window.key,
        "milestoneIndex": milestone_index,
        "points": milestone.points,
        "reward": milestone.reward,
        "spins": balances.0,
        "credits": balances.1,
        "serverTimeMs": Utc::now().timestamp_millis(),
    });
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "event_milestone_claim",
        &json!({"points": points, "spins": player.spins, "credits": player.credits}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn claim_team_event_milestone(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Path((event_id, milestone_index)): Path<(String, u32)>,
    headers: HeaderMap,
    Json(body): Json<ClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let event = state
        .config
        .events
        .iter()
        .find(|candidate| candidate.event_id == event_id)
        .ok_or(ApiError::NotFound)?;
    let window = claimable_window(event, Utc::now().timestamp_millis())
        .ok_or_else(|| ApiError::Unavailable("occurrence terminée".to_string()))?;
    let action = format!(
        "team_event_milestone_claim:{}:{milestone_index}",
        window.key
    );
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let team_config = event.team.as_ref().ok_or(ApiError::NotFound)?;
    let milestone = team_config
        .milestones
        .get(milestone_index as usize)
        .ok_or(ApiError::NotFound)?;
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let team_id: Option<String> =
        sqlx::query_scalar("SELECT team_id FROM team_members WHERE address=$1")
            .bind(&addr.0)
            .fetch_optional(&mut *tx)
            .await?;
    let Some(team_id) = team_id else {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("aucune équipe".to_string()));
    };
    let team_points: i64 = sqlx::query_scalar(
        "SELECT points FROM team_event_scores WHERE event_id=$1 AND team_id=$2 FOR UPDATE",
    )
    .bind(&window.key)
    .bind(&team_id)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    let contribution_points: i64 = sqlx::query_scalar(
        "SELECT points FROM team_event_contributions WHERE event_id=$1 AND team_id=$2 AND address=$3 FOR UPDATE",
    )
    .bind(&window.key)
    .bind(&team_id)
    .bind(&addr.0)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    if team_points < game::checked_u64_to_i64(milestone.points, "teamMilestone.points")? {
        tx.rollback().await?;
        return Err(ApiError::Unavailable(
            "palier d'équipe non atteint".to_string(),
        ));
    }
    if contribution_points
        < game::checked_u64_to_i64(
            team_config.min_contribution_points,
            "teamEvent.minContributionPoints",
        )?
    {
        tx.rollback().await?;
        return Err(ApiError::Unavailable(
            "contribution personnelle insuffisante".to_string(),
        ));
    }
    let inserted = sqlx::query(
        "INSERT INTO team_event_claims(event_id,milestone_index,address,team_id) \
         VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING",
    )
    .bind(&window.key)
    .bind(milestone_index as i32)
    .bind(&addr.0)
    .bind(&team_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if inserted == 0 {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    game::grant_reward_tx(&mut tx, &addr.0, &milestone.reward, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({
        "eventId":event.event_id,
        "eventKey":window.key,
        "milestoneIndex":milestone_index,
        "teamId":team_id,
        "teamPoints":team_points,
        "contributionPoints":contribution_points,
        "reward":milestone.reward,
        "spins":balances.0,
        "credits":balances.1,
        "serverTimeMs":Utc::now().timestamp_millis(),
    });
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "team_event_milestone_claim",
        &json!({
            "teamId":team_id,
            "teamPoints":team_points,
            "contributionPoints":contribution_points,
            "spins":player.spins,
            "credits":player.credits,
        }),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn claim_achievement(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Path(achievement_id): Path<String>,
    headers: HeaderMap,
    Json(body): Json<ClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let action = format!("achievement_claim:{achievement_id}");
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let achievement = state
        .config
        .achievements
        .iter()
        .find(|candidate| candidate.achievement_id == achievement_id)
        .ok_or(ApiError::NotFound)?;
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let progress: i64 = sqlx::query_scalar(
        "SELECT amount FROM player_action_totals WHERE address=$1 AND action=$2 FOR UPDATE",
    )
    .bind(&addr.0)
    .bind(&achievement.action)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    if progress < game::checked_u64_to_i64(achievement.target, "achievement.target")? {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("achievement non terminé".to_string()));
    }
    let inserted = sqlx::query(
        "INSERT INTO achievement_claims(achievement_id,address) VALUES($1,$2) ON CONFLICT DO NOTHING",
    )
    .bind(&achievement.achievement_id)
    .bind(&addr.0)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if inserted == 0 {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    game::grant_reward_tx(&mut tx, &addr.0, &achievement.reward, &state.config).await?;
    let reward_pool_allocations = reward_pool::allocate_tx(
        &mut tx,
        &addr.0,
        "achievement_claim",
        &achievement.achievement_id,
        &state.config.reward_pool,
    )
    .await?;
    let global_progression = progression::refresh_score_tx(&mut tx, &addr.0, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({
        "achievementId":achievement.achievement_id,
        "progress":progress,
        "target":achievement.target,
        "reward":achievement.reward,
        "rewardPoolAllocations":reward_pool_allocations,
        "spins":balances.0,
        "credits":balances.1,
        "globalProgression":progression::score_json(global_progression, &state.config),
        "serverTimeMs":Utc::now().timestamp_millis(),
    });
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "achievement_claim",
        &json!({
            "progress":progress,
            "spins":player.spins,
            "credits":player.credits,
        }),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

/// Réclame les récompenses de rang MATÉRIALISÉES par le worker de
/// distribution. Le rang est figé à la fin de l'occurrence et la fenêtre de
/// claim est bornée : passé `claim_until`, la ligne expire.
pub async fn claim_event(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Path(event_id): Path<String>,
    headers: HeaderMap,
    Json(body): Json<ClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let action = format!("event_claim:{event_id}");
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let event = state
        .config
        .events
        .iter()
        .find(|e| e.event_id == event_id)
        .ok_or(ApiError::NotFound)?;
    let now_ms = Utc::now().timestamp_millis();
    let candidate_keys = event.claimable_keys(now_ms);
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let rows: Vec<(String, i32, i64, Value)> = if candidate_keys.is_empty() {
        Vec::new()
    } else {
        sqlx::query_as(
            "SELECT event_key,cohort_id,rank,reward FROM event_rank_rewards \
             WHERE address=$1 AND event_key=ANY($2) AND claimed_at IS NULL AND claim_until>now() \
             ORDER BY event_key FOR UPDATE",
        )
        .bind(&addr.0)
        .bind(&candidate_keys)
        .fetch_all(&mut *tx)
        .await?
    };
    if rows.is_empty() {
        tx.rollback().await?;
        if event.active_window(now_ms).is_some() {
            return Err(ApiError::Unavailable("événement encore actif".to_string()));
        }
        let already: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM event_rank_rewards \
             WHERE address=$1 AND (event_key=$2 OR left(event_key,char_length($2)+1)=$2 || '#') \
             AND claimed_at IS NOT NULL)",
        )
        .bind(&addr.0)
        .bind(&event.event_id)
        .fetch_one(state.db.pool())
        .await?;
        if already {
            return Err(ApiError::AlreadyClaimed);
        }
        if candidate_keys.is_empty() {
            return Err(ApiError::Unavailable(
                "fenêtre de réclamation expirée".to_string(),
            ));
        }
        let distributed: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM event_reward_distributions WHERE event_key=ANY($1))",
        )
        .bind(&candidate_keys)
        .fetch_one(state.db.pool())
        .await?;
        if !distributed {
            return Err(ApiError::Unavailable(
                "distribution des rangs en cours".to_string(),
            ));
        }
        return Err(ApiError::Unavailable(
            "aucune récompense de rang pour ce joueur".to_string(),
        ));
    }
    let mut claimed = Vec::new();
    for (event_key, cohort_id, rank, reward_value) in &rows {
        let reward: Reward = serde_json::from_value(reward_value.clone())
            .map_err(|_| ApiError::Internal(anyhow!("reward de rang illisible: {event_key}")))?;
        game::grant_reward_tx(&mut tx, &addr.0, &reward, &state.config).await?;
        sqlx::query(
            "UPDATE event_rank_rewards SET claimed_at=now() WHERE event_key=$1 AND address=$2",
        )
        .bind(event_key)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
        claimed.push(json!({
            "eventKey": event_key,
            "cohortId": cohort_id,
            "rank": rank,
            "reward": reward,
        }));
    }
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let first = &rows[0];
    let response = json!({"eventId": event.event_id, "rank": first.2, "cohortId": first.1,
        "reward": claimed[0]["reward"], "claimed": claimed,
        "spins": balances.0, "credits": balances.1, "serverTimeMs":Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "event_claim",
        &json!({"spins":player.spins,"credits":player.credits}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

/// Worker : matérialise les récompenses de rang des occurrences terminées.
/// Idempotent multi-instance (verrou advisory + ligne de distribution unique).
/// Retourne le nombre d'occurrences distribuées.
pub async fn distribute_rank_rewards(
    db: &Db,
    config: &RemoteConfig,
    now_ms: i64,
) -> anyhow::Result<u64> {
    let mut distributed = 0u64;
    for event in &config.events {
        for window in event.claimable_windows(now_ms) {
            let claim_until_ms = window.ends_at_ms.saturating_add(event.claim_window_ms());
            let already: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM event_reward_distributions WHERE event_key=$1)",
            )
            .bind(&window.key)
            .fetch_one(db.pool())
            .await?;
            if already {
                continue;
            }
            let claim_until = DateTime::from_timestamp_millis(claim_until_ms)
                .ok_or_else(|| anyhow!("claim_until hors plage: {claim_until_ms}"))?;
            let mut tx = db.begin().await?;
            sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,1))")
                .bind(&window.key)
                .execute(&mut *tx)
                .await?;
            let recheck: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM event_reward_distributions WHERE event_key=$1)",
            )
            .bind(&window.key)
            .fetch_one(&mut *tx)
            .await?;
            if recheck {
                tx.rollback().await?;
                continue;
            }
            // Rangs FINAUX par cohorte : plus aucun point n'arrive après la
            // fin de l'occurrence (l'accrual exige une fenêtre active).
            let ranked: Vec<(String, i32, i64)> = sqlx::query_as(
                "SELECT address,cohort_id,DENSE_RANK() OVER (PARTITION BY cohort_id ORDER BY points DESC) \
                 FROM event_scores WHERE event_id=$1",
            )
            .bind(&window.key)
            .fetch_all(&mut *tx)
            .await?;
            let mut rewarded = 0i64;
            for (address, cohort_id, rank) in &ranked {
                let Some(tier) = event
                    .reward_tiers
                    .iter()
                    .find(|tier| *rank >= tier.min_rank as i64 && *rank <= tier.max_rank as i64)
                else {
                    continue;
                };
                let inserted = sqlx::query(
                    "INSERT INTO event_rank_rewards(event_key,address,cohort_id,rank,reward,claim_until) \
                     VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING",
                )
                .bind(&window.key)
                .bind(address)
                .bind(cohort_id)
                .bind(rank)
                .bind(serde_json::to_value(&tier.reward)?)
                .bind(claim_until)
                .execute(&mut *tx)
                .await?
                .rows_affected();
                rewarded += inserted as i64;
            }
            sqlx::query(
                "INSERT INTO event_reward_distributions(event_key,event_id,claim_until,participants,rewarded) \
                 VALUES($1,$2,$3,$4,$5)",
            )
            .bind(&window.key)
            .bind(&event.event_id)
            .bind(claim_until)
            .bind(ranked.len() as i64)
            .bind(rewarded)
            .execute(&mut *tx)
            .await?;
            tx.commit().await?;
            distributed += 1;
            tracing::info!(
                event_key = %window.key,
                participants = ranked.len(),
                rewarded,
                "récompenses de rang distribuées"
            );
        }
    }
    Ok(distributed)
}

/// Worker : archive les occurrences dont la fenêtre de claim est close. Les
/// tables vivantes restent bornées, l'historique part dans `*_archive`.
pub async fn archive_expired_events(db: &Db) -> anyhow::Result<u64> {
    let keys: Vec<String> = sqlx::query_scalar(
        "SELECT event_key FROM event_reward_distributions \
         WHERE claim_until < now() AND archived_at IS NULL",
    )
    .fetch_all(db.pool())
    .await?;
    let mut archived = 0u64;
    for key in keys {
        let mut tx = db.begin().await?;
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,2))")
            .bind(&key)
            .execute(&mut *tx)
            .await?;
        let still_pending: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM event_reward_distributions \
             WHERE event_key=$1 AND archived_at IS NULL)",
        )
        .bind(&key)
        .fetch_one(&mut *tx)
        .await?;
        if !still_pending {
            tx.rollback().await?;
            continue;
        }
        sqlx::query(
            "INSERT INTO event_scores_archive(event_key,address,points,cohort_id,reward_claimed) \
             SELECT event_id,address,points,cohort_id,reward_claimed FROM event_scores WHERE event_id=$1",
        )
        .bind(&key)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM event_scores WHERE event_id=$1")
            .bind(&key)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO team_event_scores_archive(event_key,team_id,points) \
             SELECT event_id,team_id,points FROM team_event_scores WHERE event_id=$1",
        )
        .bind(&key)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM team_event_scores WHERE event_id=$1")
            .bind(&key)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO team_event_contributions_archive(event_key,team_id,address,points) \
             SELECT event_id,team_id,address,points FROM team_event_contributions WHERE event_id=$1",
        )
        .bind(&key)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM team_event_contributions WHERE event_id=$1")
            .bind(&key)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO event_milestone_claims_archive(event_key,address,milestone_index,auto_claimed,claimed_at) \
             SELECT event_id,address,milestone_index,auto_claimed,claimed_at FROM event_milestone_claims WHERE event_id=$1",
        )
        .bind(&key)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM event_milestone_claims WHERE event_id=$1")
            .bind(&key)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO team_event_claims_archive(event_key,milestone_index,address,team_id,claimed_at) \
             SELECT event_id,milestone_index,address,team_id,claimed_at FROM team_event_claims WHERE event_id=$1",
        )
        .bind(&key)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM team_event_claims WHERE event_id=$1")
            .bind(&key)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE event_reward_distributions SET archived_at=now() WHERE event_key=$1")
            .bind(&key)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        archived += 1;
        tracing::info!(event_key = %key, "occurrence archivée");
    }
    Ok(archived)
}

pub async fn claim_season(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<SeasonClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let action = format!(
        "season_claim:{}:{}:{}",
        body.season_id, body.tier, body.premium
    );
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let season = state
        .config
        .seasons
        .iter()
        .find(|s| s.season_id == body.season_id)
        .ok_or(ApiError::NotFound)?;
    let tier = season
        .tiers
        .get(body.tier as usize)
        .ok_or(ApiError::NotFound)?;
    let reward = if body.premium {
        tier.premium_reward.as_ref().ok_or(ApiError::NotFound)?
    } else {
        &tier.free_reward
    };
    let mut tx = state.db.begin().await?;
    let _player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let row: Option<(i64, bool, Value, Value)> = sqlx::query_as("SELECT points,premium,free_claimed,paid_claimed FROM season_progress WHERE address=$1 AND season_id=$2 FOR UPDATE")
        .bind(&addr.0).bind(&season.season_id).fetch_optional(&mut *tx).await?;
    let Some((points, premium_owned, free_claimed, paid_claimed)) = row else {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("palier non atteint".to_string()));
    };
    if points < tier.points as i64 {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("palier non atteint".to_string()));
    }
    if body.premium && !premium_owned {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("pass premium requis".to_string()));
    }
    let claims = if body.premium {
        &paid_claimed
    } else {
        &free_claimed
    };
    if claims
        .as_array()
        .is_some_and(|a| a.iter().any(|v| v.as_u64() == Some(body.tier as u64)))
    {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    let column = if body.premium {
        "paid_claimed"
    } else {
        "free_claimed"
    };
    sqlx::query(&format!("UPDATE season_progress SET {column}={column} || jsonb_build_array($1::int) WHERE address=$2 AND season_id=$3"))
        .bind(body.tier as i32).bind(&addr.0).bind(&season.season_id).execute(&mut *tx).await?;
    game::grant_reward_tx(&mut tx, &addr.0, reward, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({"seasonId": season.season_id, "tier": body.tier, "premium": body.premium,
        "reward": reward, "spins": balances.0, "credits": balances.1,
        "serverTimeMs":Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "season_claim",
        &json!({"points":points}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outcome(id: &str, weight: u32) -> DailyBonusOutcome {
        DailyBonusOutcome {
            outcome_id: id.to_string(),
            name: id.to_string(),
            weight,
            reward: Reward {
                spins: 0,
                credits: 0,
                chest: None,
            },
        }
    }

    #[test]
    fn daily_bonus_weight_boundaries_are_exact() {
        let outcomes = vec![outcome("a", 2), outcome("b", 3), outcome("c", 1)];
        assert_eq!(bonus_index_for_roll(&outcomes, 0), Some(0));
        assert_eq!(bonus_index_for_roll(&outcomes, 1), Some(0));
        assert_eq!(bonus_index_for_roll(&outcomes, 2), Some(1));
        assert_eq!(bonus_index_for_roll(&outcomes, 4), Some(1));
        assert_eq!(bonus_index_for_roll(&outcomes, 5), Some(2));
        assert_eq!(bonus_index_for_roll(&outcomes, 6), None);
    }

    /// Cycle live-ops complet, tel qu'exécuté par le worker de main() :
    /// 1. claim avant distribution → refus explicite (pas de rang improvisé) ;
    /// 2. distribution idempotente qui fige les rangs par cohorte ;
    /// 3. claim du joueur via le handler de production, rejouable une fois ;
    /// 4. archivage après fenêtre : tables vivantes vidées, grand livre rempli.
    #[tokio::test]
    async fn postgres_rank_rewards_distribute_claim_then_archive() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_rank_rewards_distribute_claim_then_archive").await
        else {
            return Ok(());
        };
        let mut config = crate::config::RemoteConfig::load(
            &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../config"),
        )?;
        let now_ms = Utc::now().timestamp_millis();
        let event_id = format!("qa-ev-{}", uuid::Uuid::new_v4());
        let hour = crate::config::MS_PER_HOUR;
        // Occurrence à dates fixes terminée il y a 1h, fenêtre de claim 72h :
        // exactement l'état dans lequel le worker doit intervenir.
        config.events = vec![crate::config::EventConfig {
            event_id: event_id.clone(),
            name: "QA Rush".to_string(),
            starts_at_ms: now_ms - 10 * hour,
            ends_at_ms: now_ms - hour,
            schedule: None,
            claim_window_hours: Some(72),
            point_sources: Vec::new(),
            milestones: Vec::new(),
            team: None,
            leaderboard: crate::config::EventLeaderboardConfig {
                cohort_size: 25,
                display_limit: 25,
            },
            reward_tiers: vec![
                crate::config::EventRewardTier {
                    min_rank: 1,
                    max_rank: 1,
                    reward: Reward {
                        spins: 7,
                        credits: 1000,
                        chest: None,
                    },
                },
                crate::config::EventRewardTier {
                    min_rank: 2,
                    max_rank: 25,
                    reward: Reward {
                        spins: 2,
                        credits: 100,
                        chest: None,
                    },
                },
            ],
        }];
        let config = std::sync::Arc::new(config);
        let state = AppState {
            rate: std::sync::Arc::new(crate::rate_limit::RateLimiter::new(
                db.pool().clone(),
                std::time::Duration::from_secs(60),
                10_000,
            )),
            db: db.clone(),
            config: std::sync::Arc::clone(&config),
            jwt_secret: "qa-secret-0123456789-0123456789-012".to_string(),
            dev_auth: false,
            dev_address: None,
            started_at: std::time::Instant::now(),
        };

        let winner = format!("qa-lead-{}", uuid::Uuid::new_v4());
        let runner = format!("qa-runner-{}", uuid::Uuid::new_v4());
        for (address, points) in [(&winner, 500i64), (&runner, 200i64)] {
            db.ensure_player(address, 0).await?;
            sqlx::query(
                "INSERT INTO event_scores(event_id,address,points,cohort_id) VALUES($1,$2,$3,1)",
            )
            .bind(&event_id)
            .bind(address)
            .bind(points)
            .execute(db.pool())
            .await?;
        }
        sqlx::query(
            "INSERT INTO event_milestone_claims(event_id,address,milestone_index,auto_claimed) \
             VALUES($1,$2,0,true)",
        )
        .bind(&event_id)
        .bind(&winner)
        .execute(db.pool())
        .await?;

        // 1. Avant distribution : le handler refuse au lieu de calculer un
        // rang à la volée (l'ancien comportement, non figé, était triché-able
        // en réclamant avant que les retardataires ne postent leurs points).
        let premature = claim_event(
            State(state.clone()),
            Extension(Addr(winner.clone())),
            Path(event_id.clone()),
            HeaderMap::new(),
            Json(ClaimReq {
                request_id: Some(uuid::Uuid::new_v4().to_string()),
            }),
        )
        .await;
        assert!(
            matches!(premature, Err(ApiError::Unavailable(_))),
            "claim avant distribution doit être indisponible"
        );

        // 2. Distribution : une passe fige les rangs, la seconde ne fait rien.
        assert_eq!(distribute_rank_rewards(&db, &config, now_ms).await?, 1);
        assert_eq!(distribute_rank_rewards(&db, &config, now_ms).await?, 0);
        let ranks: Vec<(String, i64, Option<DateTime<Utc>>)> = sqlx::query_as(
            "SELECT address,rank,claimed_at FROM event_rank_rewards WHERE event_key=$1 ORDER BY rank",
        )
        .bind(&event_id)
        .fetch_all(db.pool())
        .await?;
        assert_eq!(ranks.len(), 2);
        assert_eq!((ranks[0].0.as_str(), ranks[0].1), (winner.as_str(), 1));
        assert_eq!((ranks[1].0.as_str(), ranks[1].1), (runner.as_str(), 2));

        // 3. Claim de production : payé une fois, rejet explicite ensuite.
        let claimed = claim_event(
            State(state.clone()),
            Extension(Addr(winner.clone())),
            Path(event_id.clone()),
            HeaderMap::new(),
            Json(ClaimReq {
                request_id: Some(uuid::Uuid::new_v4().to_string()),
            }),
        )
        .await
        .map_err(|error| anyhow!("claim post-distribution refusé: {error:?}"))?;
        assert_eq!(claimed.0["rank"], json!(1));
        assert_eq!(claimed.0["spins"], json!(7));
        let re_claim = claim_event(
            State(state.clone()),
            Extension(Addr(winner.clone())),
            Path(event_id.clone()),
            HeaderMap::new(),
            Json(ClaimReq {
                request_id: Some(uuid::Uuid::new_v4().to_string()),
            }),
        )
        .await;
        assert!(
            matches!(re_claim, Err(ApiError::AlreadyClaimed)),
            "second claim doit être AlreadyClaimed"
        );

        // 4. Fenêtre encore ouverte : rien à archiver. Puis on force la
        // clôture et l'archivage doit vider les tables vivantes une seule fois.
        assert_eq!(archive_expired_events(&db).await?, 0);
        sqlx::query(
            "UPDATE event_reward_distributions SET claim_until=now()-interval '1 hour' \
             WHERE event_key=$1",
        )
        .bind(&event_id)
        .execute(db.pool())
        .await?;
        assert_eq!(archive_expired_events(&db).await?, 1);
        assert_eq!(archive_expired_events(&db).await?, 0);
        let live_scores: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM event_scores WHERE event_id=$1")
                .bind(&event_id)
                .fetch_one(db.pool())
                .await?;
        let archived_scores: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM event_scores_archive WHERE event_key=$1")
                .bind(&event_id)
                .fetch_one(db.pool())
                .await?;
        let archived_milestones: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM event_milestone_claims_archive WHERE event_key=$1",
        )
        .bind(&event_id)
        .fetch_one(db.pool())
        .await?;
        assert_eq!(live_scores, 0, "les scores vivants doivent être purgés");
        assert_eq!(archived_scores, 2);
        assert_eq!(archived_milestones, 1);
        Ok(())
    }
}
