//! Bonus quotidien, missions, événements, classement et saison.

use crate::auth::Addr;
use crate::config::Reward;
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, Path, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::{Duration, Utc};
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
    game::grant_reward_tx(&mut tx, &addr.0, &reward).await?;
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
    game::grant_reward_tx(&mut tx, &addr.0, &mission.reward).await?;
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
    game::grant_reward_tx(&mut tx, &addr.0, &milestone.reward).await?;
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
    game::grant_reward_tx(&mut tx, &addr.0, &tier.reward).await?;
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
    if claims.as_array().map_or(false, |a| {
        a.iter().any(|v| v.as_u64() == Some(body.tier as u64))
    }) {
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
    game::grant_reward_tx(&mut tx, &addr.0, reward).await?;
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
