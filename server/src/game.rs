//! Primitives communes aux mutations économiques R17.

use crate::config::{RemoteConfig, Reward};
use crate::error::ApiError;
use axum::http::HeaderMap;
use chrono::{NaiveDate, Utc};
use sqlx::{Postgres, Transaction};

pub fn request_id(headers: &HeaderMap, fallback: Option<&str>) -> Result<String, ApiError> {
    let value = headers
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .or(fallback)
        .map(str::trim)
        .filter(|v| !v.is_empty() && v.len() <= 128)
        .ok_or_else(|| ApiError::BadRequest("X-Request-Id est requis".to_string()))?;
    if !value
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
    {
        return Err(ApiError::BadRequest("X-Request-Id invalide".to_string()));
    }
    Ok(value.to_string())
}

pub fn idem_key(action: &str, address: &str, request_id: &str) -> String {
    format!("{action}|{address}|{request_id}")
}

pub async fn grant_reward_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    reward: &Reward,
) -> Result<(), ApiError> {
    sqlx::query(
        "UPDATE player_state SET spins = spins + $1, credits = credits + $2 WHERE address = $3",
    )
    .bind(reward.spins as i32)
    .bind(reward.credits as i64)
    .bind(address)
    .execute(&mut **tx)
    .await?;
    if let Some(chest) = &reward.chest {
        sqlx::query(
            "INSERT INTO player_chests(address, chest_id, qty) VALUES ($1,$2,1) \
             ON CONFLICT(address,chest_id) DO UPDATE SET qty = player_chests.qty + 1",
        )
        .bind(address)
        .bind(chest)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

/// Progresse missions, événement actif et saison dans la transaction métier.
pub async fn progress_action_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    action: &str,
    amount: i64,
    config: &RemoteConfig,
) -> Result<(), ApiError> {
    let now = Utc::now();
    let today: NaiveDate = now.date_naive();
    for mission in config.daily.missions.iter().filter(|m| m.action == action) {
        sqlx::query(
            "INSERT INTO mission_progress(address,mission_id,mission_day,progress) VALUES($1,$2,$3,$4) \
             ON CONFLICT(address,mission_id,mission_day) DO UPDATE SET progress = mission_progress.progress + EXCLUDED.progress",
        )
        .bind(address)
        .bind(&mission.mission_id)
        .bind(today)
        .bind(amount.max(0))
        .execute(&mut **tx)
        .await?;
    }

    let now_ms = now.timestamp_millis();
    let mut season_points = 0i64;
    for event in config
        .events
        .iter()
        .filter(|e| e.starts_at_ms <= now_ms && now_ms < e.ends_at_ms)
    {
        let points: i64 = event
            .point_sources
            .iter()
            .filter(|s| s.action == action)
            .map(|s| s.points as i64 * amount.max(0))
            .sum();
        if points > 0 {
            season_points += points;
            sqlx::query(
                "INSERT INTO event_scores(event_id,address,points) VALUES($1,$2,$3) \
                 ON CONFLICT(event_id,address) DO UPDATE SET points = event_scores.points + EXCLUDED.points",
            )
            .bind(&event.event_id)
            .bind(address)
            .bind(points)
            .execute(&mut **tx)
            .await?;
        }
    }
    for season in config
        .seasons
        .iter()
        .filter(|s| s.starts_at_ms <= now_ms && now_ms < s.ends_at_ms)
    {
        if season_points > 0 {
            sqlx::query(
                "INSERT INTO season_progress(address,season_id,points) VALUES($1,$2,$3) \
                 ON CONFLICT(address,season_id) DO UPDATE SET points = season_progress.points + EXCLUDED.points",
            )
            .bind(address)
            .bind(&season.season_id)
            .bind(season_points)
            .execute(&mut **tx)
            .await?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_ids_are_scoped_by_action() {
        assert_ne!(
            idem_key("spin", "alice", "1"),
            idem_key("upgrade", "alice", "1")
        );
    }
}
