//! `POST /spin` — l'action économique centrale (M1).
//!
//! Flow serveur-authoritative (ARCH §4.6) :
//! 1. auth JWT (middleware `guard`)
//! 2. idempotence (X-Request-Id) — la réponse est stockée DANS la même
//!    transaction que le spin (pas de double-spend même en race)
//! 3. regen temporelle (horloge serveur, jamais l'horloge client)
//! 4. spins < 1 → 403 `NO_SPINS` + `nextSpinAtMs`
//! 5. tirage sur `spin_table.json` (CSPRNG `OsRng`, poids entiers)
//! 6. transaction SQL atomique : état + audit économie
//!
//! Le client n'envoie AUCUN montant : le résultat vient 100 % de la
//! config versionnée (hashée). Règle d'or GDD §37-39.

use crate::auth::auth_address;
use crate::config::{OutcomeType, RemoteConfig};
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
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

    let response = perform_spin(&state.db, &state.config, &address, &request_id).await?;
    Ok(Json(response))
}

/// Tirage + écriture atomique (regen, état, audit, idempotence) en UNE transaction.
async fn perform_spin(
    db: &Db,
    config: &RemoteConfig,
    address: &str,
    request_id: &str,
) -> Result<Value, ApiError> {
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

    // 1) Regen temporelle (horloge serveur).
    let now = Utc::now();
    let gained = regen_gained(row.last_spin_at, now, row.spins, config);
    let spins_after_regen = row.spins + gained;

    // 2) Pas de spin → NO_SPINS + heure du prochain spin.
    if spins_after_regen < 1 {
        let next = row.last_spin_at.map(|last| {
            (last + ChronoDuration::milliseconds(config.economy.spin_regen_ms as i64))
                .timestamp_millis()
        });
        tx.rollback().await?;
        return Err(ApiError::NoSpins {
            next_spin_at_ms: next,
        });
    }

    // 3) Tirage sur la table de poids (CSPRNG).
    let outcomes = &config.spin_table.outcomes;
    let total: u32 = outcomes.iter().map(|o| o.weight).sum();
    let pick = rand::rngs::OsRng.gen_range(0..total);
    let mut acc = 0u32;
    let outcome = outcomes
        .iter()
        .find(|o| {
            acc += o.weight;
            pick < acc
        })
        .expect("table non vide (validée au boot)");

    // 4) Gain en crédits (bornes min/max validées au boot).
    let credits_gained: u64 = if outcome.outcome_type == OutcomeType::Credits {
        match (outcome.min, outcome.max) {
            (Some(min), Some(max)) => rand::rngs::OsRng.gen_range(min..=max),
            _ => 0,
        }
    } else {
        // M1 : pas d'issues chest/card dans la table (activées en M3).
        0
    };

    // 5) Écriture atomique : état + audit (+ idempotence).
    let before = json!({
        "spins": row.spins,
        "credits": row.credits,
        "lastSpinAt": row.last_spin_at.map(|t| t.to_rfc3339()),
    });

    let new_spins = spins_after_regen - 1;
    let new_credits = row.credits + credits_gained as i64;

    sqlx::query(
        "UPDATE player_state SET spins = $1, credits = $2, last_spin_at = $3 WHERE address = $4",
    )
    .bind(new_spins)
    .bind(new_credits)
    .bind(now)
    .bind(address)
    .execute(&mut *tx)
    .await?;

    let after = json!({
        "spins": new_spins,
        "credits": new_credits,
        "lastSpinAt": now.to_rfc3339(),
    });
    game::progress_action_tx(&mut tx, address, "spin", 1, config).await?;
    Db::audit_tx(&mut tx, address, "spin", &before, &after, Some(request_id)).await?;

    let next_spin_at_ms = if new_spins < config.economy.max_free_spins as i32 {
        Some(
            (now + ChronoDuration::milliseconds(config.economy.spin_regen_ms as i64))
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
        "creditsGained": credits_gained,
        "spins": new_spins,
        "credits": new_credits,
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
        assert_eq!(
            regen_gained(Some(old), now, 0, &cfg),
            cfg.economy.max_free_spins as i32
        );
        assert_eq!(
            regen_gained(Some(now + ChronoDuration::seconds(1)), now, 0, &cfg),
            0
        );
    }
}

/// Spins régénérés depuis `last_spin_at`, plafonnés à `maxFreeSpins`.
fn regen_gained(
    last_spin_at: Option<DateTime<Utc>>,
    now: DateTime<Utc>,
    spins: i32,
    config: &RemoteConfig,
) -> i32 {
    let Some(last) = last_spin_at else {
        return 0;
    };
    let elapsed = (now - last).num_milliseconds();
    if elapsed <= 0 {
        return 0;
    }
    let gained = (elapsed / config.economy.spin_regen_ms as i64) as i32;
    (gained)
        .min(config.economy.max_free_spins as i32 - spins)
        .max(0)
}
