//! Score global autoritaire et classement de progression.

use crate::auth::Addr;
use crate::config::{RemoteConfig, Tier};
use crate::error::ApiError;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, State};
use axum::Json;
use serde_json::{json, Value};
use sqlx::{Postgres, Transaction};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ScoreBreakdown {
    pub total: i64,
    pub upgrades: i64,
    pub districts: i64,
    pub cards: i64,
    pub sets: i64,
    pub achievements: i64,
}

fn checked_component(value: i64, points: u32, label: &str) -> Result<i64, ApiError> {
    value
        .checked_mul(i64::from(points))
        .ok_or_else(|| ApiError::Internal(anyhow!("{label} score overflow")))
}

fn rarity_points(config: &RemoteConfig, tier: Tier) -> i64 {
    i64::from(config.progression.rarity_points.points(tier))
}

pub async fn calculate_score_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    config: &RemoteConfig,
) -> Result<ScoreBreakdown, ApiError> {
    let upgrade_levels: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(level),0)::bigint FROM district_progress WHERE address=$1",
    )
    .bind(address)
    .fetch_one(&mut **tx)
    .await?;
    let completed_districts: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM district_completion WHERE address=$1")
            .bind(address)
            .fetch_one(&mut **tx)
            .await?;
    let completed_sets: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::bigint FROM set_completion WHERE address=$1 AND claimed=true",
    )
    .bind(address)
    .fetch_one(&mut **tx)
    .await?;
    let completed_achievements: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM achievement_claims WHERE address=$1")
            .bind(address)
            .fetch_one(&mut **tx)
            .await?;
    let owned_cards: Vec<String> =
        sqlx::query_scalar("SELECT card_id FROM player_cards WHERE address=$1 AND qty>0")
            .bind(address)
            .fetch_all(&mut **tx)
            .await?;

    let upgrades = checked_component(upgrade_levels, config.progression.upgrade_points, "upgrade")?;
    let districts = checked_component(
        completed_districts,
        config.progression.district_completion_points,
        "district",
    )?;
    let sets = checked_component(
        completed_sets,
        config.progression.set_completion_points,
        "set",
    )?;
    let achievements = checked_component(
        completed_achievements,
        config.progression.achievement_points,
        "achievement",
    )?;
    let mut cards = 0i64;
    for card_id in owned_cards {
        if let Some(card) = config.cards.iter().find(|card| card.card_id == card_id) {
            cards = cards
                .checked_add(rarity_points(config, card.rarity))
                .ok_or_else(|| ApiError::Internal(anyhow!("card score overflow")))?;
        }
    }
    let total = upgrades
        .checked_add(districts)
        .and_then(|score| score.checked_add(cards))
        .and_then(|score| score.checked_add(sets))
        .and_then(|score| score.checked_add(achievements))
        .ok_or_else(|| ApiError::Internal(anyhow!("global score overflow")))?;
    Ok(ScoreBreakdown {
        total,
        upgrades,
        districts,
        cards,
        sets,
        achievements,
    })
}

pub async fn refresh_score_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    config: &RemoteConfig,
) -> Result<ScoreBreakdown, ApiError> {
    let score = calculate_score_tx(tx, address, config).await?;
    sqlx::query(
        "INSERT INTO progression_scores(address,score,upgrade_score,district_score,card_score,set_score,achievement_score) \
         VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(address) DO UPDATE SET \
         score=EXCLUDED.score,upgrade_score=EXCLUDED.upgrade_score,district_score=EXCLUDED.district_score, \
         card_score=EXCLUDED.card_score,set_score=EXCLUDED.set_score,achievement_score=EXCLUDED.achievement_score,updated_at=now()",
    )
    .bind(address)
    .bind(score.total)
    .bind(score.upgrades)
    .bind(score.districts)
    .bind(score.cards)
    .bind(score.sets)
    .bind(score.achievements)
    .execute(&mut **tx)
    .await?;
    Ok(score)
}

pub async fn stored_score_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
) -> Result<ScoreBreakdown, ApiError> {
    let row: (i64, i64, i64, i64, i64, i64) = sqlx::query_as(
        "SELECT score,upgrade_score,district_score,card_score,set_score,achievement_score FROM progression_scores WHERE address=$1",
    )
    .bind(address)
    .fetch_one(&mut **tx)
    .await?;
    Ok(ScoreBreakdown {
        total: row.0,
        upgrades: row.1,
        districts: row.2,
        cards: row.3,
        sets: row.4,
        achievements: row.5,
    })
}

pub async fn refresh_score(state: &AppState, address: &str) -> Result<ScoreBreakdown, ApiError> {
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT address FROM player_state WHERE address=$1 FOR UPDATE")
        .bind(address)
        .fetch_one(&mut *tx)
        .await?;
    let score = refresh_score_tx(&mut tx, address, &state.config).await?;
    tx.commit().await?;
    Ok(score)
}

pub fn score_json(score: ScoreBreakdown, config: &RemoteConfig) -> Value {
    json!({
        "name":config.progression.score_name,
        "score":score.total,
        "breakdown":{"upgrades":score.upgrades,"districts":score.districts,"cards":score.cards,"sets":score.sets,"achievements":score.achievements}
    })
}

pub async fn leaderboard(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
) -> Result<Json<Value>, ApiError> {
    refresh_score(&state, &addr.0).await?;
    let limit = i64::from(state.config.progression.global_leaderboard_limit);
    let rows: Vec<(i64, String, String, String, i64, i32)> = sqlx::query_as(
        "SELECT DENSE_RANK() OVER(ORDER BY ps.score DESC) AS rank,p.friend_code,p.display_name,p.avatar_id,ps.score,s.district_index \
         FROM progression_scores ps JOIN player_profiles p ON p.address=ps.address \
         JOIN player_state s ON s.address=ps.address ORDER BY ps.score DESC,p.friend_code LIMIT $1",
    )
    .bind(limit)
    .fetch_all(state.db.pool())
    .await?;
    let entries: Vec<Value> = rows
        .into_iter()
        .map(|(rank, player_id, display_name, avatar_id, score, district_index)| {
            json!({"rank":rank,"playerId":player_id,"displayName":display_name,"avatarId":avatar_id,"score":score,"districtIndex":district_index})
        })
        .collect();
    let player_rank: i64 = sqlx::query_scalar(
        "SELECT COUNT(DISTINCT score)+1 FROM progression_scores WHERE score>(SELECT score FROM progression_scores WHERE address=$1)",
    )
    .bind(&addr.0)
    .fetch_one(state.db.pool())
    .await?;
    Ok(Json(
        json!({"name":state.config.progression.score_name,"playerRank":player_rank,"entries":entries}),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checked_score_component_rejects_overflow() {
        assert!(checked_component(i64::MAX, 2, "test").is_err());
        assert_eq!(checked_component(25, 4, "test").unwrap(), 100);
    }
}
