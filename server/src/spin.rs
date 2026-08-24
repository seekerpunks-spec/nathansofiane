//! `POST /spin` — l'action économique centrale (M1).
//!
//! Flow serveur-authoritative (ARCH §4.6) :
//! 1. auth JWT (middleware `guard`)
//! 2. idempotence (X-Request-Id) — la réponse est stockée DANS la même
//!    transaction que le spin (pas de double-spend même en race)
//! 3. regen temporelle (horloge serveur, jamais l'horloge client)
//! 4. validation + débit atomique du multiplicateur data-driven
//! 5. tirage sur `spin_table.json` (CSPRNG `OsRng`, poids entiers)
//! 6. transaction SQL atomique : état + audit économie
//!
//! Le client n'envoie AUCUN montant : le résultat vient 100 % de la
//! config versionnée (hashée). Règle d'or GDD §37-39.

use crate::auth::auth_address;
use crate::collection;
use crate::config::{OutcomeType, RemoteConfig};
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::social;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use chrono::{DateTime, Duration as ChronoDuration, Utc};
use rand::Rng;
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
pub struct SpinReq {
    /// Fallback idempotence (l'en-tête `X-Request-Id` a la priorité).
    #[serde(default, rename = "requestId")]
    pub request_id: Option<String>,
    #[serde(default = "default_multiplier")]
    pub multiplier: u32,
    /// Test d'intégration local uniquement ; refusé hors DEV_AUTH.
    #[serde(default, rename = "debugOutcomeId")]
    pub debug_outcome_id: Option<String>,
    #[serde(default, rename = "debugTargetAddress")]
    pub debug_target_address: Option<String>,
}

fn default_multiplier() -> u32 {
    1
}

pub async fn spin(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<SpinReq>,
) -> Result<Json<Value>, ApiError> {
    let address = auth_address(&state, &headers)?;

    // Clé d'idempotence : X-Request-Id (priorité) puis body.requestId.
    let request_id = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("spin", &address, &request_id);

    // Fast path : rejeu → réponse stockée.
    if let Some(stored) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(stored));
    }
    if (body.debug_outcome_id.is_some() || body.debug_target_address.is_some()) && !state.dev_auth {
        return Err(ApiError::BadRequest(
            "champs debug indisponibles hors DEV_AUTH".to_string(),
        ));
    }

    let response = perform_spin(
        &state.db,
        &state.config,
        &address,
        &request_id,
        body.multiplier,
        body.debug_outcome_id.as_deref(),
        body.debug_target_address.as_deref(),
    )
    .await?;
    Ok(Json(response))
}

/// Tirage + écriture atomique (regen, état, audit, idempotence) en UNE transaction.
async fn perform_spin(
    db: &Db,
    config: &RemoteConfig,
    address: &str,
    request_id: &str,
    multiplier: u32,
    forced_outcome_id: Option<&str>,
    forced_target: Option<&str>,
) -> Result<Value, ApiError> {
    if !config.economy.spin_multipliers.contains(&multiplier) {
        return Err(ApiError::BadRequest(
            "multiplier absent de la configuration".to_string(),
        ));
    }
    let mut tx = db.begin().await?;

    let row = db
        .fetch_state_locked(&mut tx, address)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("pas de player_state pour {address}")))?;

    // Re-lecture idempotence DANS la transaction (après le verrou ligne) :
    // ferme la fenêtre de race entre deux requêtes concurrentes même clé.
    let key = game::idem_key("spin", address, request_id);
    if let Some(stored) = db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(stored);
    }
    social::ensure_no_pending_tx(&mut tx, address).await?;

    // 1) Regen temporelle (horloge serveur).
    let now = Utc::now();
    let regen = regen_state(row.last_spin_at, now, row.spins, config);
    let spins_after_regen = regen.spins;

    // 2) Solde insuffisant : le serveur ne rétrograde jamais silencieusement.
    if spins_after_regen < multiplier as i32 {
        tx.rollback().await?;
        return Err(ApiError::InsufficientSpins {
            required_spins: multiplier,
            available_spins: spins_after_regen,
            next_spin_at_ms: regen.next_spin_at_ms,
        });
    }

    // 3) Tirage sur la table de poids (CSPRNG).
    let outcomes = &config.spin_table.outcomes;
    let total: u32 = outcomes.iter().map(|o| o.weight).sum();
    let outcome = if let Some(outcome_id) = forced_outcome_id {
        outcomes
            .iter()
            .find(|outcome| outcome.id == outcome_id)
            .ok_or_else(|| ApiError::BadRequest("debugOutcomeId inconnu".to_string()))?
    } else {
        let pick = rand::rngs::OsRng.gen_range(0..total);
        let mut acc = 0u32;
        outcomes
            .iter()
            .find(|outcome| {
                acc += outcome.weight;
                pick < acc
            })
            .expect("table non vide (validée au boot)")
    };

    // 4) Gain en crédits (bornes min/max validées au boot).
    let base_credits_gained: u64 = if outcome.outcome_type == OutcomeType::Credits {
        match (outcome.min, outcome.max) {
            (Some(min), Some(max)) => rand::rngs::OsRng.gen_range(min..=max),
            _ => 0,
        }
    } else {
        // M1 : pas d'issues chest/card dans la table (activées en M3).
        0
    };
    let mut credits_gained =
        game::checked_scale(base_credits_gained, multiplier, "spin.creditsGained")?;

    // 5) Écriture atomique : état + audit (+ idempotence).
    let before = json!({
        "spins": row.spins,
        "credits": row.credits,
        "lastSpinAt": row.last_spin_at.map(|t| t.to_rfc3339()),
        "multiplier": multiplier,
    });

    let new_spins = spins_after_regen - multiplier as i32;
    let new_credits = game::checked_add_credits(row.credits, credits_gained, "spin.credits")?;
    let max_free = config.economy.max_free_spins as i32;
    let persisted_anchor = if new_spins < max_free {
        if spins_after_regen >= max_free {
            now
        } else {
            regen.anchor.unwrap_or(now)
        }
    } else {
        now
    };

    sqlx::query(
        "UPDATE player_state SET spins = $1, credits = $2, last_spin_at = $3 WHERE address = $4",
    )
    .bind(new_spins)
    .bind(new_credits)
    .bind(persisted_anchor)
    .bind(address)
    .execute(&mut *tx)
    .await?;

    let mut pending_encounter: Option<Value> = None;
    let mut feature_reward: Option<Value> = None;
    match outcome.outcome_type {
        OutcomeType::Attack | OutcomeType::Raid => {
            pending_encounter = social::create_encounter_tx(
                &mut tx,
                address,
                row.district_index,
                outcome.outcome_type,
                multiplier,
                config,
                forced_target,
            )
            .await?;
        }
        OutcomeType::Shield => {
            let reward = social::apply_shield_tx(&mut tx, address, multiplier, config).await?;
            credits_gained = reward
                .get("overflowCredits")
                .and_then(Value::as_u64)
                .unwrap_or(0);
            feature_reward = Some(reward);
        }
        OutcomeType::Chest => {
            let chest_id = outcome
                .reward_id
                .as_deref()
                .ok_or_else(|| ApiError::Internal(anyhow!("spin chest sans rewardId")))?;
            feature_reward =
                Some(collection::grant_spin_chest_tx(&mut tx, address, chest_id).await?);
        }
        OutcomeType::Card => {
            feature_reward =
                Some(collection::grant_spin_card_tx(&mut tx, address, &config.cards).await?);
        }
        OutcomeType::Credits | OutcomeType::None => {}
    }

    let progress =
        game::progress_action_tx(&mut tx, address, "spin", multiplier as i64, config).await?;
    let final_balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(address)
            .fetch_one(&mut *tx)
            .await?;
    let after = json!({
        "spins": final_balances.0,
        "credits": final_balances.1,
        "lastSpinAt": persisted_anchor.to_rfc3339(),
        "multiplier": multiplier,
        "baseCreditsGained": base_credits_gained,
        "creditsGained": credits_gained,
        "featureReward": feature_reward.clone(),
        "pendingEncounter": pending_encounter.clone(),
    });
    Db::audit_tx(&mut tx, address, "spin", &before, &after, Some(request_id)).await?;

    let next_spin_at_ms = if final_balances.0 < config.economy.max_free_spins as i32 {
        Some(
            (persisted_anchor + ChronoDuration::milliseconds(config.economy.spin_regen_ms as i64))
                .timestamp_millis(),
        )
    } else {
        None
    };

    let response = json!({
        "outcome": {
            "id": outcome.id,
            "type": outcome.outcome_type,
            "tier": outcome.tier,
            "label": outcome.label,
        },
        "multiplier": multiplier,
        "spinsSpent": multiplier,
        "baseCreditsGained": base_credits_gained,
        "creditsGained": credits_gained,
        "spins": final_balances.0,
        "credits": final_balances.1,
        "featureReward": feature_reward,
        "pendingEncounter": pending_encounter,
        "progress": progress,
        "nextSpinAtMs": next_spin_at_ms,
        "serverTimeMs": now.timestamp_millis(),
    });

    db.store_idempotent(&mut tx, &key, &response).await?;

    tx.commit().await?;
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn regen_is_capped_and_never_negative() {
        let cfg =
            RemoteConfig::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../config")).unwrap();
        let now = Utc::now();
        let old = now - ChronoDuration::milliseconds(cfg.economy.spin_regen_ms as i64 * 100);
        let capped = regen_state(Some(old), now, 0, &cfg);
        assert_eq!(capped.spins, cfg.economy.max_free_spins as i32);
        assert_eq!(capped.next_spin_at_ms, None);
        let future = regen_state(Some(now + ChronoDuration::seconds(1)), now, 0, &cfg);
        assert_eq!(future.spins, 0);
    }

    #[test]
    fn regen_preserves_partial_interval() {
        let cfg =
            RemoteConfig::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../config")).unwrap();
        let now = Utc::now();
        let interval = cfg.economy.spin_regen_ms as i64;
        let last = now - ChronoDuration::milliseconds(interval + interval / 2);
        let snapshot = regen_state(Some(last), now, 0, &cfg);
        assert_eq!(snapshot.spins, 1);
        let anchor = snapshot.anchor.unwrap();
        assert_eq!(anchor, last + ChronoDuration::milliseconds(interval));
        assert_eq!(
            snapshot.next_spin_at_ms,
            Some((last + ChronoDuration::milliseconds(interval * 2)).timestamp_millis())
        );
    }
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct RegenState {
    pub spins: i32,
    pub anchor: Option<DateTime<Utc>>,
    pub next_spin_at_ms: Option<i64>,
}

/// Snapshot de régénération sans mutation. `anchor` avance uniquement des
/// intervalles complets afin de conserver le reliquat temporel du joueur.
pub(crate) fn regen_state(
    last_spin_at: Option<DateTime<Utc>>,
    now: DateTime<Utc>,
    spins: i32,
    config: &RemoteConfig,
) -> RegenState {
    let max_free = config.economy.max_free_spins as i32;
    if spins >= max_free {
        return RegenState {
            spins,
            anchor: None,
            next_spin_at_ms: None,
        };
    }
    let Some(last) = last_spin_at else {
        let next = now + ChronoDuration::milliseconds(config.economy.spin_regen_ms as i64);
        return RegenState {
            spins,
            anchor: Some(now),
            next_spin_at_ms: Some(next.timestamp_millis()),
        };
    };
    let elapsed = (now - last).num_milliseconds();
    if elapsed <= 0 {
        let next = last + ChronoDuration::milliseconds(config.economy.spin_regen_ms as i64);
        return RegenState {
            spins,
            anchor: Some(last),
            next_spin_at_ms: Some(next.timestamp_millis()),
        };
    }
    let gained = (elapsed / config.economy.spin_regen_ms as i64) as i32;
    let applied = gained.min(max_free - spins).max(0);
    let total = spins + applied;
    if total >= max_free {
        return RegenState {
            spins: total,
            anchor: None,
            next_spin_at_ms: None,
        };
    }
    let anchor =
        last + ChronoDuration::milliseconds(config.economy.spin_regen_ms as i64 * applied as i64);
    let next = anchor + ChronoDuration::milliseconds(config.economy.spin_regen_ms as i64);
    RegenState {
        spins: total,
        anchor: Some(anchor),
        next_spin_at_ms: Some(next.timestamp_millis()),
    }
}
