//! Entitlements NFT fail-closed.
//!
//! Ce module ne vérifie pas le wallet lui-même : le provider Solana est une
//! dépendance externe explicitement différée. Les perks ne sont actifs que si
//! une ligne écrite par un futur vérificateur serveur est active, non expirée,
//! et correspond à une définition remote-config elle-même activée. Il n'existe
//! volontairement aucune route client permettant de déclarer une ownership.

use crate::config::{EntitlementConfig, RemoteConfig};
use crate::error::ApiError;
use crate::state::AppState;
use anyhow::anyhow;
use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::{json, Value};
use sqlx::{Postgres, Transaction};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EffectiveEntitlement {
    pub entitlement_id: String,
    pub name: String,
    pub badge_id: Option<String>,
    pub expires_at_ms: i64,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EffectivePerks {
    pub daily_spin_bonus: u32,
    pub items: Vec<EffectiveEntitlement>,
}

fn summarize(
    definitions: &[EntitlementConfig],
    rows: &[(String, DateTime<Utc>)],
) -> Result<EffectivePerks, ApiError> {
    let mut result = EffectivePerks::default();
    for (entitlement_id, expires_at) in rows {
        let Some(definition) = definitions
            .iter()
            .find(|definition| definition.enabled && definition.entitlement_id == *entitlement_id)
        else {
            continue;
        };
        result.daily_spin_bonus = result
            .daily_spin_bonus
            .checked_add(definition.perks.daily_spin_bonus)
            .ok_or_else(|| ApiError::Internal(anyhow!("entitlement daily bonus overflow")))?;
        result.items.push(EffectiveEntitlement {
            entitlement_id: definition.entitlement_id.clone(),
            name: definition.name.clone(),
            badge_id: definition.perks.badge_id.clone(),
            expires_at_ms: expires_at.timestamp_millis(),
        });
    }
    Ok(result)
}

pub async fn effective_perks_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    config: &RemoteConfig,
) -> Result<EffectivePerks, ApiError> {
    let rows: Vec<(String, DateTime<Utc>)> = sqlx::query_as(
        "SELECT entitlement_id,expires_at FROM player_entitlements \
         WHERE address=$1 AND active=true AND expires_at>now() ORDER BY entitlement_id",
    )
    .bind(address)
    .fetch_all(&mut **tx)
    .await?;
    summarize(&config.entitlements, &rows)
}

/// Point d'entrée interne du futur provider/indexeur. Il n'est relié à aucune
/// route HTTP client et dérive toujours le TTL depuis la remote config.
pub async fn record_verification_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    entitlement_id: &str,
    ownership_ref: &str,
    verifier: &str,
    owned: bool,
    config: &RemoteConfig,
) -> Result<(), ApiError> {
    let definition = config
        .entitlements
        .iter()
        .find(|definition| definition.enabled && definition.entitlement_id == entitlement_id)
        .ok_or_else(|| ApiError::Unavailable("entitlement désactivé ou inconnu".to_string()))?;
    if ownership_ref.trim().is_empty()
        || ownership_ref.len() > 160
        || verifier.trim().is_empty()
        || verifier.len() > 48
    {
        return Err(ApiError::BadRequest(
            "preuve d'ownership invalide".to_string(),
        ));
    }
    let ttl = i64::try_from(definition.verification_ttl_ms)
        .map_err(|_| ApiError::Internal(anyhow!("entitlement ttl overflow")))?;
    let now = Utc::now();
    let expires_at = now
        .checked_add_signed(chrono::Duration::milliseconds(ttl))
        .ok_or_else(|| ApiError::Internal(anyhow!("entitlement expiry overflow")))?;
    sqlx::query(
        "INSERT INTO player_entitlements(address,entitlement_id,active,verifier,ownership_ref,verified_at,expires_at) \
         VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(address,entitlement_id) DO UPDATE SET \
         active=EXCLUDED.active,verifier=EXCLUDED.verifier,ownership_ref=EXCLUDED.ownership_ref, \
         verified_at=EXCLUDED.verified_at,expires_at=EXCLUDED.expires_at",
    )
    .bind(address)
    .bind(entitlement_id)
    .bind(owned)
    .bind(verifier)
    .bind(ownership_ref)
    .bind(now)
    .bind(expires_at)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub async fn for_state(state: &AppState, address: &str) -> Result<Value, ApiError> {
    let rows: Vec<(String, DateTime<Utc>)> = sqlx::query_as(
        "SELECT entitlement_id,expires_at FROM player_entitlements \
         WHERE address=$1 AND active=true AND expires_at>now() ORDER BY entitlement_id",
    )
    .bind(address)
    .fetch_all(state.db.pool())
    .await?;
    let perks = summarize(&state.config.entitlements, &rows)?;
    Ok(json!({
        "dailySpinBonus":perks.daily_spin_bonus,
        "items":perks.items,
        "verificationMode":"server_provider_required",
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::EntitlementPerks;

    fn definition(enabled: bool) -> EntitlementConfig {
        EntitlementConfig {
            entitlement_id: "og".to_string(),
            name: "OG".to_string(),
            enabled,
            collection_address: "collection".to_string(),
            verification_ttl_ms: 86_400_000,
            perks: EntitlementPerks {
                daily_spin_bonus: 50,
                badge_id: Some("OG".to_string()),
            },
        }
    }

    #[test]
    fn disabled_or_unknown_ownership_never_grants_perks() {
        let expiry = Utc::now();
        assert_eq!(
            summarize(&[definition(false)], &[("og".to_string(), expiry)])
                .unwrap()
                .daily_spin_bonus,
            0
        );
        assert_eq!(
            summarize(&[definition(true)], &[("unknown".to_string(), expiry)])
                .unwrap()
                .daily_spin_bonus,
            0
        );
    }

    #[test]
    fn verified_enabled_ownership_grants_configured_perks() {
        let expiry = Utc::now();
        let perks = summarize(&[definition(true)], &[("og".to_string(), expiry)]).unwrap();
        assert_eq!(perks.daily_spin_bonus, 50);
        assert_eq!(perks.items.len(), 1);
    }

    #[tokio::test]
    async fn postgres_expired_ownership_fails_closed() -> anyhow::Result<()> {
        let Ok(database_url) = std::env::var("CYBERSEEKER_TEST_DATABASE_URL") else {
            return Ok(());
        };
        let mut config = crate::config::RemoteConfig::load(
            &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../config"),
        )?;
        config.entitlements[0].enabled = true;
        let pool = sqlx::PgPool::connect(&database_url).await?;
        let mut tx = pool.begin().await?;
        let address = format!("qa-entitlement-{}", uuid::Uuid::new_v4());
        sqlx::query("INSERT INTO players(address) VALUES($1)")
            .bind(&address)
            .execute(&mut *tx)
            .await?;
        record_verification_tx(
            &mut tx,
            &address,
            &config.entitlements[0].entitlement_id,
            "asset",
            "qa",
            true,
            &config,
        )
        .await?;
        assert_eq!(
            effective_perks_tx(&mut tx, &address, &config)
                .await?
                .daily_spin_bonus,
            50
        );
        sqlx::query(
            "UPDATE player_entitlements SET verified_at=now()-interval '2 days',expires_at=now()-interval '1 day' WHERE address=$1",
        )
        .bind(&address)
        .execute(&mut *tx)
        .await?;
        assert_eq!(
            effective_perks_tx(&mut tx, &address, &config)
                .await?
                .daily_spin_bonus,
            0
        );
        tx.rollback().await?;
        Ok(())
    }
}
