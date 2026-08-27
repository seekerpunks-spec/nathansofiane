//! Primitives communes aux mutations économiques R17.

use crate::config::{RemoteConfig, Reward};
use crate::error::ApiError;
use crate::spin;
use anyhow::anyhow;
use axum::http::HeaderMap;
use chrono::{NaiveDate, Utc};
use serde::Serialize;
use sqlx::{Postgres, Transaction};

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgressResult {
    pub events: Vec<EventProgressResult>,
    pub team_events: Vec<TeamEventProgressResult>,
    pub achievements: Vec<AchievementProgressResult>,
}

impl ProgressResult {
    /// Fusionne la progression d'une seconde action déclenchée dans la même
    /// transaction (ex. `spin` puis `credits_earned`).
    pub fn merge(&mut self, other: ProgressResult) {
        self.events.extend(other.events);
        self.team_events.extend(other.team_events);
        self.achievements.extend(other.achievements);
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EventProgressResult {
    pub event_id: String,
    /// Clé de l'occurrence créditée (identique à `event_id` pour un
    /// événement à dates fixes).
    pub event_key: String,
    pub points_added: i64,
    pub points: i64,
    pub cohort_id: i32,
    pub auto_milestones_claimed: Vec<u32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TeamEventProgressResult {
    pub event_id: String,
    pub team_id: String,
    pub points_added: i64,
    pub team_points: i64,
    pub contribution_points: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AchievementProgressResult {
    pub achievement_id: String,
    pub action: String,
    pub progress: i64,
    pub target: u64,
}

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

pub fn checked_u64_to_i64(value: u64, label: &str) -> Result<i64, ApiError> {
    i64::try_from(value).map_err(|_| ApiError::Internal(anyhow!("overflow économique: {label}")))
}

pub fn checked_add_credits(current: i64, delta: u64, label: &str) -> Result<i64, ApiError> {
    let delta = checked_u64_to_i64(delta, label)?;
    current
        .checked_add(delta)
        .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: {label}")))
}

pub fn checked_scale(value: u64, multiplier: u32, label: &str) -> Result<u64, ApiError> {
    value
        .checked_mul(multiplier as u64)
        .filter(|scaled| *scaled <= i64::MAX as u64)
        .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: {label}")))
}

pub async fn grant_reward_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    reward: &Reward,
    config: &RemoteConfig,
) -> Result<(), ApiError> {
    let current: (i32, i64, Option<chrono::DateTime<Utc>>) = sqlx::query_as(
        "SELECT spins,credits,last_spin_at FROM player_state WHERE address=$1 FOR UPDATE",
    )
    .bind(address)
    .fetch_one(&mut **tx)
    .await?;
    let now = Utc::now();
    let regen = spin::regen_state(current.2, now, current.0, config);
    let spins_delta = i32::try_from(reward.spins)
        .map_err(|_| ApiError::Internal(anyhow!("overflow économique: reward.spins")))?;
    let spins = regen
        .spins
        .checked_add(spins_delta)
        .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: player.spins")))?;
    let credits = checked_add_credits(current.1, reward.credits, "reward.credits")?;
    let regen_anchor = regen.anchor.or(current.2).unwrap_or(now);
    sqlx::query("UPDATE player_state SET spins=$1,credits=$2,last_spin_at=$3 WHERE address=$4")
        .bind(spins)
        .bind(credits)
        .bind(regen_anchor)
        .bind(address)
        .execute(&mut **tx)
        .await?;
    if let Some(chest) = &reward.chest {
        let quantity: Option<i64> = sqlx::query_scalar(
            "INSERT INTO player_chests(address, chest_id, qty) VALUES ($1,$2,1) \
             ON CONFLICT(address,chest_id) DO UPDATE SET qty = player_chests.qty + 1 \
             WHERE player_chests.qty < 9223372036854775807 RETURNING qty",
        )
        .bind(address)
        .bind(chest)
        .fetch_optional(&mut **tx)
        .await?;
        if quantity.is_none() {
            return Err(ApiError::Internal(anyhow!(
                "overflow économique: reward.chestInventory"
            )));
        }
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
) -> Result<ProgressResult, ApiError> {
    let now = Utc::now();
    let mut result = ProgressResult::default();
    let today: NaiveDate = now.date_naive();
    let achievement_matches: Vec<_> = config
        .achievements
        .iter()
        .filter(|achievement| achievement.action == action)
        .collect();
    if amount > 0 && !achievement_matches.is_empty() {
        let total: i64 = sqlx::query_scalar(
            "INSERT INTO player_action_totals(address,action,amount) VALUES($1,$2,$3) \
             ON CONFLICT(address,action) DO UPDATE SET amount = LEAST(9223372036854775807::numeric, player_action_totals.amount::numeric + EXCLUDED.amount::numeric)::bigint \
             RETURNING amount",
        )
        .bind(address)
        .bind(action)
        .bind(amount)
        .fetch_one(&mut **tx)
        .await?;
        result.achievements = achievement_matches
            .into_iter()
            .map(|achievement| AchievementProgressResult {
                achievement_id: achievement.achievement_id.clone(),
                action: action.to_string(),
                progress: total,
                target: achievement.target,
            })
            .collect();
    }
    for mission in config
        .daily_missions_for(today)
        .into_iter()
        .filter(|m| m.action == action)
    {
        sqlx::query(
            "INSERT INTO mission_progress(address,mission_id,mission_day,progress) VALUES($1,$2,$3,LEAST($4,$5)) \
             ON CONFLICT(address,mission_id,mission_day) DO UPDATE SET progress = \
             LEAST($5::numeric, mission_progress.progress::numeric + EXCLUDED.progress::numeric)::bigint",
        )
        .bind(address)
        .bind(&mission.mission_id)
        .bind(today)
        .bind(amount.max(0))
        .bind(checked_u64_to_i64(mission.target, "mission.target")?)
        .execute(&mut **tx)
        .await?;
    }

    let now_ms = now.timestamp_millis();
    let current_team: Option<String> =
        sqlx::query_scalar("SELECT team_id FROM team_members WHERE address=$1")
            .bind(address)
            .fetch_optional(&mut **tx)
            .await?;
    for event in &config.events {
        // Les points s'accumulent sur la CLÉ d'occurrence : chaque passage
        // d'un événement récurrent repart d'un classement vierge.
        let Some(window) = event.active_window(now_ms) else {
            continue;
        };
        let mut points = 0i64;
        for source in event.point_sources.iter().filter(|s| s.action == action) {
            let source_points = checked_u64_to_i64(source.points, "event.points")?;
            let delta = source_points
                .checked_mul(amount.max(0))
                .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: event.points")))?;
            points = points
                .checked_add(delta)
                .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: event.total")))?;
        }
        if points > 0 {
            // Sérialise uniquement l'affectation de cohorte de cette occurrence.
            sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
                .bind(&window.key)
                .execute(&mut **tx)
                .await?;
            let existing_cohort: Option<i32> = sqlx::query_scalar(
                "SELECT cohort_id FROM event_scores WHERE event_id=$1 AND address=$2",
            )
            .bind(&window.key)
            .bind(address)
            .fetch_optional(&mut **tx)
            .await?;
            let cohort_id = if let Some(cohort) = existing_cohort {
                cohort
            } else {
                let last_cohort: i32 = sqlx::query_scalar(
                    "SELECT COALESCE(MAX(cohort_id),1) FROM event_scores WHERE event_id=$1",
                )
                .bind(&window.key)
                .fetch_one(&mut **tx)
                .await?;
                let members: i64 = sqlx::query_scalar(
                    "SELECT COUNT(*) FROM event_scores WHERE event_id=$1 AND cohort_id=$2",
                )
                .bind(&window.key)
                .bind(last_cohort)
                .fetch_one(&mut **tx)
                .await?;
                if members >= event.leaderboard.cohort_size as i64 {
                    last_cohort.checked_add(1).ok_or_else(|| {
                        ApiError::Internal(anyhow!("overflow économique: event.cohort"))
                    })?
                } else {
                    last_cohort
                }
            };
            let total_points: i64 = sqlx::query_scalar(
                "INSERT INTO event_scores(event_id,address,points,cohort_id) VALUES($1,$2,$3,$4) \
                 ON CONFLICT(event_id,address) DO UPDATE SET points = LEAST(9223372036854775807::numeric, event_scores.points::numeric + EXCLUDED.points::numeric)::bigint \
                 RETURNING points",
            )
            .bind(&window.key)
            .bind(address)
            .bind(points)
            .bind(cohort_id)
            .fetch_one(&mut **tx)
            .await?;

            let mut auto_milestones_claimed = Vec::new();
            for (index, milestone) in event.milestones.iter().enumerate() {
                if !milestone.auto_claim
                    || total_points < checked_u64_to_i64(milestone.points, "milestone.points")?
                {
                    continue;
                }
                let inserted = sqlx::query(
                    "INSERT INTO event_milestone_claims(event_id,address,milestone_index,auto_claimed) \
                     VALUES($1,$2,$3,true) ON CONFLICT DO NOTHING",
                )
                .bind(&window.key)
                .bind(address)
                .bind(index as i32)
                .execute(&mut **tx)
                .await?
                .rows_affected();
                if inserted == 1 {
                    grant_reward_tx(tx, address, &milestone.reward, config).await?;
                    auto_milestones_claimed.push(index as u32);
                }
            }
            result.events.push(EventProgressResult {
                event_id: event.event_id.clone(),
                event_key: window.key.clone(),
                points_added: points,
                points: total_points,
                cohort_id,
                auto_milestones_claimed,
            });
            if event.team.is_some() {
                if let Some(team_id) = &current_team {
                    let team_points: i64 = sqlx::query_scalar(
                        "INSERT INTO team_event_scores(event_id,team_id,points) VALUES($1,$2,$3) \
                         ON CONFLICT(event_id,team_id) DO UPDATE SET points = LEAST(9223372036854775807::numeric, team_event_scores.points::numeric + EXCLUDED.points::numeric)::bigint \
                         RETURNING points",
                    )
                    .bind(&window.key)
                    .bind(team_id)
                    .bind(points)
                    .fetch_one(&mut **tx)
                    .await?;
                    let contribution_points: i64 = sqlx::query_scalar(
                        "INSERT INTO team_event_contributions(event_id,team_id,address,points) VALUES($1,$2,$3,$4) \
                         ON CONFLICT(event_id,team_id,address) DO UPDATE SET points = LEAST(9223372036854775807::numeric, team_event_contributions.points::numeric + EXCLUDED.points::numeric)::bigint \
                         RETURNING points",
                    )
                    .bind(&window.key)
                    .bind(team_id)
                    .bind(address)
                    .bind(points)
                    .fetch_one(&mut **tx)
                    .await?;
                    result.team_events.push(TeamEventProgressResult {
                        event_id: event.event_id.clone(),
                        team_id: team_id.clone(),
                        points_added: points,
                        team_points,
                        contribution_points,
                    });
                }
            }
        }
    }
    // Les saisons progressent depuis leurs PROPRES sources : la boucle de
    // rétention saisonnière ne dépend plus d'un événement actif.
    for season in config
        .seasons
        .iter()
        .filter(|s| s.starts_at_ms <= now_ms && now_ms < s.ends_at_ms)
    {
        let mut season_points = 0i64;
        for source in season.point_sources.iter().filter(|s| s.action == action) {
            let source_points = checked_u64_to_i64(source.points, "season.points")?;
            let delta = source_points
                .checked_mul(amount.max(0))
                .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: season.points")))?;
            season_points = season_points
                .checked_add(delta)
                .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: season.total")))?;
        }
        if season_points > 0 {
            sqlx::query(
                "INSERT INTO season_progress(address,season_id,points) VALUES($1,$2,$3) \
                 ON CONFLICT(address,season_id) DO UPDATE SET points = LEAST(9223372036854775807::numeric, season_progress.points::numeric + EXCLUDED.points::numeric)::bigint",
            )
            .bind(address)
            .bind(&season.season_id)
            .bind(season_points)
            .execute(&mut **tx)
            .await?;
        }
    }
    Ok(result)
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

    #[test]
    fn checked_scaling_rejects_bigint_overflow() {
        assert_eq!(
            checked_scale(6_000_000, 100_000, "test").unwrap(),
            600_000_000_000
        );
        assert!(checked_scale(i64::MAX as u64, 2, "test").is_err());
        assert!(checked_add_credits(i64::MAX, 1, "test").is_err());
    }

    #[tokio::test]
    async fn postgres_reward_preserves_unpersisted_regen() -> anyhow::Result<()> {
        let Some(db) = crate::testdb::connect("postgres_reward_preserves_unpersisted_regen").await
        else {
            return Ok(());
        };
        let config = crate::config::RemoteConfig::load(
            &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../config"),
        )?;
        let mut tx = db.begin().await?;
        let address = format!("qa-regen-{}", uuid::Uuid::new_v4());
        let interval = i64::try_from(config.economy.spin_regen_ms)?;
        let last = Utc::now() - chrono::Duration::milliseconds(interval * 2 + 1_000);
        sqlx::query("INSERT INTO players(address) VALUES($1)")
            .bind(&address)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO player_state(address,spins,credits,last_spin_at) VALUES($1,0,0,$2)",
        )
        .bind(&address)
        .bind(last)
        .execute(&mut *tx)
        .await?;
        grant_reward_tx(
            &mut tx,
            &address,
            &Reward {
                spins: 5,
                credits: 0,
                chest: None,
            },
            &config,
        )
        .await?;
        let persisted: (i32, chrono::DateTime<Utc>) =
            sqlx::query_as("SELECT spins,last_spin_at FROM player_state WHERE address=$1")
                .bind(&address)
                .fetch_one(&mut *tx)
                .await?;
        assert_eq!(persisted.0, 7);
        assert_eq!(
            persisted.1.timestamp_millis(),
            (last + chrono::Duration::milliseconds(interval * 2)).timestamp_millis()
        );

        sqlx::query("UPDATE player_state SET spins=$1,last_spin_at=now() WHERE address=$2")
            .bind(i32::MAX)
            .bind(&address)
            .execute(&mut *tx)
            .await?;
        let overflow = grant_reward_tx(
            &mut tx,
            &address,
            &Reward {
                spins: 1,
                credits: 0,
                chest: None,
            },
            &config,
        )
        .await;
        assert!(overflow.is_err());
        tx.rollback().await?;
        Ok(())
    }
}
