//! Construction des districts — coûts et récompenses exclusivement serveur.

use crate::auth::Addr;
use crate::config::Reward;
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, State};
use axum::http::HeaderMap;
use axum::Json;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpgradeReq {
    district_id: u32,
    element_id: u32,
    #[serde(default)]
    request_id: Option<String>,
}

pub async fn upgrade(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<UpgradeReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("district_upgrade", &addr.0, &rid);
    if let Some(stored) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(stored));
    }

    let district = state
        .config
        .districts
        .iter()
        .find(|d| d.id == body.district_id)
        .ok_or(ApiError::NotFound)?;
    let element = district
        .elements
        .iter()
        .find(|e| e.id == body.element_id)
        .ok_or(ApiError::NotFound)?;

    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(stored) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(stored));
    }

    let current: i32 = sqlx::query_scalar(
        "SELECT level FROM district_progress WHERE address=$1 AND district_id=$2 AND element_id=$3",
    )
    .bind(&addr.0)
    .bind(body.district_id as i32)
    .bind(body.element_id as i32)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    let next_level = current + 1;
    let level_cfg = element
        .levels
        .iter()
        .find(|l| l.level == next_level as u32)
        .ok_or_else(|| ApiError::BadRequest("niveau maximum atteint".to_string()))?;
    if player.credits < level_cfg.cost as i64 {
        tx.rollback().await?;
        return Err(ApiError::InsufficientCredits);
    }

    let before = json!({"credits": player.credits, "districtId": district.id, "elementId": element.id, "level": current});
    let credits = player.credits - level_cfg.cost as i64;
    sqlx::query("UPDATE player_state SET credits=$1 WHERE address=$2")
        .bind(credits)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "INSERT INTO district_progress(address,district_id,element_id,level) VALUES($1,$2,$3,$4) \
         ON CONFLICT(address,district_id,element_id) DO UPDATE SET level=EXCLUDED.level",
    )
    .bind(&addr.0)
    .bind(district.id as i32)
    .bind(element.id as i32)
    .bind(next_level)
    .execute(&mut *tx)
    .await?;

    let rows: Vec<(i32, i32)> = sqlx::query_as(
        "SELECT element_id,level FROM district_progress WHERE address=$1 AND district_id=$2 ORDER BY element_id",
    )
    .bind(&addr.0)
    .bind(district.id as i32)
    .fetch_all(&mut *tx)
    .await?;
    let levels: HashMap<u32, u32> = rows
        .iter()
        .map(|(id, level)| (*id as u32, *level as u32))
        .collect();
    let complete = district.elements.iter().all(|e| {
        let max = e.levels.iter().map(|l| l.level).max().unwrap_or(0);
        levels.get(&e.id).copied().unwrap_or(0) >= max
    });

    let mut completion_reward: Option<Reward> = None;
    if complete {
        let inserted = sqlx::query(
            "INSERT INTO district_completion(address,district_id) VALUES($1,$2) ON CONFLICT DO NOTHING",
        )
        .bind(&addr.0)
        .bind(district.id as i32)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if inserted == 1 {
            if let Some(reward) = &district.completion_reward {
                let r = Reward {
                    spins: reward.spins,
                    credits: reward.credits,
                    chest: reward.chest.clone(),
                };
                game::grant_reward_tx(&mut tx, &addr.0, &r).await?;
                completion_reward = Some(r);
            }
            sqlx::query("UPDATE player_state SET district_index=GREATEST(district_index,$1) WHERE address=$2")
                .bind(district.id as i32)
                .bind(&addr.0)
                .execute(&mut *tx)
                .await?;
        }
    }
    game::progress_action_tx(&mut tx, &addr.0, "upgrade", 1, &state.config).await?;

    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let after = json!({"spins": balances.0, "credits": balances.1, "districtId": district.id, "elementId": element.id, "level": next_level, "complete": complete});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "district_upgrade",
        &before,
        &after,
        Some(&rid),
    )
    .await?;
    let response = json!({
        "districtId": district.id, "elementId": element.id, "level": next_level,
        "cost": level_cfg.cost, "spins": balances.0, "credits": balances.1,
        "districtProgress": rows.into_iter().map(|(element_id, level)| json!({"districtId": district.id, "elementId": element_id, "level": level})).collect::<Vec<_>>(),
        "districtComplete": complete, "completionReward": completion_reward,
        "serverTimeMs": chrono::Utc::now().timestamp_millis()
    });
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}
