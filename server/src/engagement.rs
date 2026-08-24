//! Bonus quotidien, missions, événements, classement et saison.

use crate::auth::Addr;
use crate::config::{DailyBonusOutcome, Reward};
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, Path, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::{Duration, Utc};
use rand::Rng;
use serde::Deserialize;
use serde_json::{json, Value};

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
    Ok(state
        .config
        .events
        .iter()
        .filter_map(|event| {
            let team_config = event.team.as_ref()?;
            let team_points = scores
                .iter()
                .find(|row| row.0 == event.event_id)
                .map(|row| row.1)
                .unwrap_or(0);
            let contribution_points = contributions
                .iter()
                .find(|row| row.0 == event.event_id)
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
                        "claimed":claims.iter().any(|row| row.0 == event.event_id && row.1 == index as i32),
                    })
                })
                .collect();
            Some(json!({
                "eventId":event.event_id,
                "name":team_config.name,
                "teamId":team_id,
                "teamName":team_name,
                "startsAtMs":event.starts_at_ms,
                "endsAtMs":event.ends_at_ms,
                "teamPoints":team_points,
                "contributionPoints":contribution_points,
                "minContributionPoints":team_config.min_contribution_points,
                "milestones":milestones,
            }))
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
        player.daily_streak + 1
    } else {
        1
    };
    let index = ((streak - 1) as usize) % state.config.daily.cycle.len();
    let entry = &state.config.daily.cycle[index];
    let reward = Reward {
        spins: entry.spins,
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
    let response = json!({"day": entry.day, "streak": streak, "reward": reward, "spins": balances.0, "credits": balances.1, "serverTimeMs": Utc::now().timestamp_millis()});
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
    let mission = state
        .config
        .daily
        .missions
        .iter()
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
    let today = Utc::now().date_naive();
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
    let player_row: Option<(i64, i32)> = sqlx::query_as(
        "SELECT points,cohort_id FROM event_scores WHERE event_id=$1 AND address=$2",
    )
    .bind(&event.event_id)
    .bind(&addr.0)
    .fetch_optional(state.db.pool())
    .await?;
    let (player_points, cohort_id) = player_row.unwrap_or((0, 1));
    let rows: Vec<(String, i64, i64)> = sqlx::query_as(
        "SELECT address,points,rank FROM (\
            SELECT address,points,DENSE_RANK() OVER(ORDER BY points DESC) AS rank \
            FROM event_scores WHERE event_id=$1 AND cohort_id=$2\
         ) ranked ORDER BY rank,address LIMIT $3",
    )
    .bind(&event.event_id)
    .bind(cohort_id)
    .bind(event.leaderboard.display_limit as i64)
    .fetch_all(state.db.pool())
    .await?;
    let rank: i64 = if player_row.is_some() {
        sqlx::query_scalar(
            "SELECT COUNT(DISTINCT points)+1 FROM event_scores \
             WHERE event_id=$1 AND cohort_id=$2 AND points>$3",
        )
        .bind(&event.event_id)
        .bind(cohort_id)
        .bind(player_points)
        .fetch_one(state.db.pool())
        .await?
    } else {
        0
    };
    Ok(Json(
        json!({"eventId": event.event_id, "name": event.name, "startsAtMs": event.starts_at_ms, "endsAtMs": event.ends_at_ms,
        "cohortId": cohort_id,
        "leaders": rows.into_iter().map(|(address,points,rank)| json!({"rank": rank, "address": address, "points": points})).collect::<Vec<_>>(),
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
    let action = format!("event_milestone_claim:{event_id}:{milestone_index}");
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let event = state
        .config
        .events
        .iter()
        .find(|candidate| candidate.event_id == event_id)
        .ok_or(ApiError::NotFound)?;
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
    .bind(&event.event_id)
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
    .bind(&event.event_id)
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
    let action = format!("team_event_milestone_claim:{event_id}:{milestone_index}");
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let event = state
        .config
        .events
        .iter()
        .find(|candidate| candidate.event_id == event_id)
        .ok_or(ApiError::NotFound)?;
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
    .bind(&event.event_id)
    .bind(&team_id)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    let contribution_points: i64 = sqlx::query_scalar(
        "SELECT points FROM team_event_contributions WHERE event_id=$1 AND team_id=$2 AND address=$3 FOR UPDATE",
    )
    .bind(&event.event_id)
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
    .bind(&event.event_id)
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

pub async fn claim_event(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Path(event_id): Path<String>,
    headers: HeaderMap,
    Json(body): Json<ClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("event_claim", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let event = state
        .config
        .events
        .iter()
        .find(|e| e.event_id == event_id)
        .ok_or(ApiError::NotFound)?;
    if Utc::now().timestamp_millis() < event.ends_at_ms {
        return Err(ApiError::Unavailable("événement encore actif".to_string()));
    }
    let mut tx = state.db.begin().await?;
    let _player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    let row: Option<(i64, bool, i32)> = sqlx::query_as("SELECT points,reward_claimed,cohort_id FROM event_scores WHERE event_id=$1 AND address=$2 FOR UPDATE")
        .bind(&event.event_id).bind(&addr.0).fetch_optional(&mut *tx).await?;
    let Some((points, claimed, cohort_id)) = row else {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("aucun score".to_string()));
    };
    if claimed {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    let rank: i64 = sqlx::query_scalar(
        "SELECT COUNT(DISTINCT points)+1 FROM event_scores \
         WHERE event_id=$1 AND cohort_id=$2 AND points>$3",
    )
    .bind(&event.event_id)
    .bind(cohort_id)
    .bind(points)
    .fetch_one(&mut *tx)
    .await?;
    let tier = event
        .reward_tiers
        .iter()
        .find(|t| rank >= t.min_rank as i64 && rank <= t.max_rank as i64)
        .ok_or_else(|| ApiError::Unavailable("aucune récompense pour ce rang".to_string()))?;
    sqlx::query("UPDATE event_scores SET reward_claimed=true WHERE event_id=$1 AND address=$2")
        .bind(&event.event_id)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    game::grant_reward_tx(&mut tx, &addr.0, &tier.reward, &state.config).await?;
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({"eventId": event.event_id, "rank": rank, "cohortId": cohort_id, "reward": tier.reward, "spins": balances.0, "credits": balances.1});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "event_claim",
        &json!({"points":points}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn claim_season(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<SeasonClaimReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("season_claim", &addr.0, &rid);
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
    let response = json!({"seasonId": season.season_id, "tier": body.tier, "premium": body.premium, "reward": reward, "spins": balances.0, "credits": balances.1});
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
}
