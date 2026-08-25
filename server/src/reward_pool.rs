//! Ledger futur d'un pool saisonnier SKR.
//!
//! Le fichier livré désactive entièrement le système. Quand une saison est
//! explicitement activée, seules des sources serveur configurées peuvent créer
//! un solde interne, sous budget global atomique. Aucun endpoint client ne peut
//! confirmer un payout blockchain ; `record_settlement_tx` est réservé au futur
//! provider serveur.

use crate::config::{RewardPoolConfig, SeasonRewardPool};
use crate::error::ApiError;
use anyhow::anyhow;
use chrono::Utc;
use serde_json::{json, Value};
use sqlx::{Postgres, Transaction};

fn active(pool: &SeasonRewardPool, now_ms: i64) -> bool {
    pool.starts_at_ms <= now_ms && now_ms < pool.ends_at_ms
}

pub async fn allocate_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    source: &str,
    source_id: &str,
    config: &RewardPoolConfig,
) -> Result<Vec<Value>, ApiError> {
    allocate_tx_at(
        tx,
        address,
        source,
        source_id,
        config,
        Utc::now().timestamp_millis(),
    )
    .await
}

async fn allocate_tx_at(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    source: &str,
    source_id: &str,
    config: &RewardPoolConfig,
    now_ms: i64,
) -> Result<Vec<Value>, ApiError> {
    if !config.enabled {
        return Ok(Vec::new());
    }
    let source_key = format!("{source}:{source_id}");
    let mut allocations = Vec::new();
    for pool in config.pools.iter().filter(|pool| active(pool, now_ms)) {
        let Some(rule) = pool
            .rules
            .iter()
            .find(|rule| rule.source == source && rule.source_id == source_id)
        else {
            continue;
        };
        let amount = i64::try_from(rule.amount_u64)
            .map_err(|_| ApiError::Internal(anyhow!("reward pool amount hors BIGINT")))?;
        let budget = i64::try_from(pool.budget_u64)
            .map_err(|_| ApiError::Internal(anyhow!("reward pool budget hors BIGINT")))?;

        // Verrou transactionnel global au pool : le budget est respecté même si
        // plusieurs joueurs terminent un milestone sur plusieurs instances.
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
            .bind(&pool.pool_id)
            .execute(&mut **tx)
            .await?;
        let existing: Option<i64> = sqlx::query_scalar(
            "SELECT amount_u64 FROM reward_pool_allocations \
             WHERE pool_id=$1 AND address=$2 AND source_key=$3",
        )
        .bind(&pool.pool_id)
        .bind(address)
        .bind(&source_key)
        .fetch_optional(&mut **tx)
        .await?;
        if let Some(existing) = existing {
            let pending: i64 = sqlx::query_scalar(
                "SELECT pending_u64 FROM reward_pool_balances WHERE pool_id=$1 AND address=$2",
            )
            .bind(&pool.pool_id)
            .bind(address)
            .fetch_one(&mut **tx)
            .await?;
            allocations.push(json!({
                "poolId":pool.pool_id,"tokenMint":pool.token_mint,"amountU64":existing,
                "pendingU64":pending,"source":source,"sourceId":source_id,"replayed":true
            }));
            continue;
        }
        let allocated: i64 = sqlx::query_scalar(
            "SELECT COALESCE(SUM(amount_u64),0)::bigint FROM reward_pool_allocations WHERE pool_id=$1",
        )
        .bind(&pool.pool_id)
        .fetch_one(&mut **tx)
        .await?;
        let Some(next_allocated) = allocated.checked_add(amount) else {
            return Err(ApiError::Internal(anyhow!(
                "reward pool allocation overflow"
            )));
        };
        if next_allocated > budget {
            allocations.push(json!({
                "poolId":pool.pool_id,"amountU64":0,"source":source,"sourceId":source_id,
                "poolAllocatedU64":allocated,"poolBudgetU64":budget,"exhausted":true
            }));
            continue;
        }
        sqlx::query(
            "INSERT INTO reward_pool_allocations(pool_id,address,source_key,amount_u64) \
             VALUES($1,$2,$3,$4)",
        )
        .bind(&pool.pool_id)
        .bind(address)
        .bind(&source_key)
        .bind(amount)
        .execute(&mut **tx)
        .await?;
        let pending: Option<i64> = sqlx::query_scalar(
            "INSERT INTO reward_pool_balances(pool_id,address,pending_u64) VALUES($1,$2,$3) \
             ON CONFLICT(pool_id,address) DO UPDATE SET \
               pending_u64=reward_pool_balances.pending_u64+EXCLUDED.pending_u64,updated_at=now() \
             WHERE reward_pool_balances.pending_u64 <= 9223372036854775807-EXCLUDED.pending_u64 \
             RETURNING pending_u64",
        )
        .bind(&pool.pool_id)
        .bind(address)
        .bind(amount)
        .fetch_optional(&mut **tx)
        .await?;
        let pending =
            pending.ok_or_else(|| ApiError::Internal(anyhow!("reward pool pending overflow")))?;
        allocations.push(json!({
            "poolId":pool.pool_id,"tokenMint":pool.token_mint,"amountU64":amount,
            "pendingU64":pending,"minClaimU64":pool.min_claim_u64,
            "poolAllocatedU64":next_allocated,"poolBudgetU64":budget,
            "source":source,"sourceId":source_id,"replayed":false
        }));
    }
    Ok(allocations)
}

pub async fn for_state(
    pool: &sqlx::PgPool,
    address: &str,
    config: &RewardPoolConfig,
) -> Result<Value, ApiError> {
    if !config.enabled {
        return Ok(json!({"enabled":false,"settlementEnabled":false,"pools":[]}));
    }
    let balances: Vec<(String, i64, i64)> = sqlx::query_as(
        "SELECT pool_id,pending_u64,settled_u64 FROM reward_pool_balances WHERE address=$1",
    )
    .bind(address)
    .fetch_all(pool)
    .await?;
    let now_ms = Utc::now().timestamp_millis();
    let pools: Vec<Value> = config
        .pools
        .iter()
        .map(|definition| {
            let balance = balances
                .iter()
                .find(|balance| balance.0 == definition.pool_id);
            let pending = balance.map(|balance| balance.1).unwrap_or(0);
            let settled = balance.map(|balance| balance.2).unwrap_or(0);
            json!({
                "poolId":definition.pool_id,"tokenMint":definition.token_mint,
                "startsAtMs":definition.starts_at_ms,"endsAtMs":definition.ends_at_ms,
                "budgetU64":definition.budget_u64,"minClaimU64":definition.min_claim_u64,
                "pendingU64":pending,"settledU64":settled,"active":active(definition,now_ms),
                "claimable":config.settlement_enabled && active(definition,now_ms)
                    && pending >= i64::try_from(definition.min_claim_u64).unwrap_or(i64::MAX)
            })
        })
        .collect();
    Ok(json!({
        "enabled":true,"settlementEnabled":config.settlement_enabled,"pools":pools
    }))
}

/// Enregistre un payout déjà confirmé par le futur provider serveur. Cette
/// fonction n'est volontairement reliée à aucune route HTTP publique.
pub async fn record_settlement_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    pool_id: &str,
    amount_u64: u64,
    settlement_ref: &str,
    config: &RewardPoolConfig,
) -> Result<Value, ApiError> {
    if !config.enabled || !config.settlement_enabled {
        return Err(ApiError::Unavailable(
            "provider reward pool non configuré".to_string(),
        ));
    }
    let definition = config
        .pools
        .iter()
        .find(|pool| pool.pool_id == pool_id && active(pool, Utc::now().timestamp_millis()))
        .ok_or(ApiError::NotFound)?;
    if settlement_ref.trim().is_empty() || settlement_ref.len() > 160 {
        return Err(ApiError::BadRequest("settlementRef invalide".to_string()));
    }
    if amount_u64 < definition.min_claim_u64 {
        return Err(ApiError::Unavailable(
            "seuil minimum non atteint".to_string(),
        ));
    }
    let amount = i64::try_from(amount_u64)
        .map_err(|_| ApiError::BadRequest("amountU64 hors BIGINT".to_string()))?;
    let existing: Option<(String, String, i64)> = sqlx::query_as(
        "SELECT pool_id,address,amount_u64 FROM reward_pool_settlements WHERE settlement_ref=$1",
    )
    .bind(settlement_ref)
    .fetch_optional(&mut **tx)
    .await?;
    if let Some(existing) = existing {
        if existing == (pool_id.to_string(), address.to_string(), amount) {
            return Ok(json!({
                "poolId":pool_id,"amountU64":amount,"settlementRef":settlement_ref,"replayed":true
            }));
        }
        return Err(ApiError::AlreadyClaimed);
    }
    let balance: Option<(i64, i64)> = sqlx::query_as(
        "SELECT pending_u64,settled_u64 FROM reward_pool_balances \
         WHERE pool_id=$1 AND address=$2 FOR UPDATE",
    )
    .bind(pool_id)
    .bind(address)
    .fetch_optional(&mut **tx)
    .await?;
    let (pending, settled) = balance.ok_or(ApiError::NotFound)?;
    if pending < amount {
        return Err(ApiError::Unavailable(
            "solde reward pool insuffisant".to_string(),
        ));
    }
    let final_settled = settled
        .checked_add(amount)
        .ok_or_else(|| ApiError::Internal(anyhow!("reward pool settled overflow")))?;
    sqlx::query(
        "INSERT INTO reward_pool_settlements(settlement_ref,pool_id,address,amount_u64) \
         VALUES($1,$2,$3,$4)",
    )
    .bind(settlement_ref)
    .bind(pool_id)
    .bind(address)
    .bind(amount)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "UPDATE reward_pool_balances SET pending_u64=$1,settled_u64=$2,updated_at=now() \
         WHERE pool_id=$3 AND address=$4",
    )
    .bind(pending - amount)
    .bind(final_settled)
    .bind(pool_id)
    .bind(address)
    .execute(&mut **tx)
    .await?;
    Ok(json!({
        "poolId":pool_id,"amountU64":amount,"pendingU64":pending-amount,
        "settledU64":final_settled,"settlementRef":settlement_ref,"replayed":false
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{RewardPoolRule, SeasonRewardPool};

    fn config(enabled_settlement: bool, pool_id: &str) -> RewardPoolConfig {
        let now = Utc::now().timestamp_millis();
        RewardPoolConfig {
            enabled: true,
            settlement_enabled: enabled_settlement,
            pools: vec![SeasonRewardPool {
                pool_id: pool_id.to_string(),
                token_mint: "test-mint".to_string(),
                starts_at_ms: now - 60_000,
                ends_at_ms: now + 60_000,
                budget_u64: 150,
                min_claim_u64: 50,
                rules: vec![
                    RewardPoolRule {
                        source: "achievement_claim".to_string(),
                        source_id: "one".to_string(),
                        amount_u64: 100,
                    },
                    RewardPoolRule {
                        source: "achievement_claim".to_string(),
                        source_id: "two".to_string(),
                        amount_u64: 100,
                    },
                ],
            }],
        }
    }

    #[tokio::test]
    async fn postgres_pool_is_budgeted_idempotent_and_settled_internally() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_pool_is_budgeted_idempotent_and_settled_internally")
                .await
        else {
            return Ok(());
        };
        let address = format!("pool-test-{}", uuid::Uuid::new_v4());
        let pool_id = format!("pool-{}", uuid::Uuid::new_v4());
        db.ensure_player(&address, 1).await?;
        let cfg = config(true, &pool_id);

        let mut tx = db.begin().await?;
        let first = allocate_tx(&mut tx, &address, "achievement_claim", "one", &cfg).await?;
        let replay = allocate_tx(&mut tx, &address, "achievement_claim", "one", &cfg).await?;
        let exhausted = allocate_tx(&mut tx, &address, "achievement_claim", "two", &cfg).await?;
        assert_eq!(first[0]["amountU64"], 100);
        assert_eq!(replay[0]["replayed"], true);
        assert_eq!(exhausted[0]["exhausted"], true);
        let settlement_ref = format!("test:{}", uuid::Uuid::new_v4());
        let settlement =
            record_settlement_tx(&mut tx, &address, &pool_id, 100, &settlement_ref, &cfg).await?;
        assert_eq!(settlement["pendingU64"], 0);
        tx.commit().await?;

        let mut replay_tx = db.begin().await?;
        let replay = record_settlement_tx(
            &mut replay_tx,
            &address,
            &pool_id,
            100,
            &settlement_ref,
            &cfg,
        )
        .await?;
        assert_eq!(replay["replayed"], true);
        replay_tx.rollback().await?;

        sqlx::query("DELETE FROM player_state WHERE address=$1")
            .bind(&address)
            .execute(db.pool())
            .await?;
        sqlx::query("DELETE FROM players WHERE address=$1")
            .bind(&address)
            .execute(db.pool())
            .await?;
        Ok(())
    }

    #[tokio::test]
    async fn postgres_pool_budget_is_global_under_concurrency() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_pool_budget_is_global_under_concurrency").await
        else {
            return Ok(());
        };
        let first_address = format!("pool-a-{}", uuid::Uuid::new_v4());
        let second_address = format!("pool-b-{}", uuid::Uuid::new_v4());
        let pool_id = format!("pool-{}", uuid::Uuid::new_v4());
        db.ensure_player(&first_address, 1).await?;
        db.ensure_player(&second_address, 1).await?;
        let mut cfg = config(false, &pool_id);
        cfg.pools[0].budget_u64 = 100;

        let first_db = db.clone();
        let second_db = db.clone();
        let first_cfg = cfg.clone();
        let second_cfg = cfg.clone();
        let first_player = first_address.clone();
        let second_player = second_address.clone();
        let (first, second) = tokio::join!(
            async move {
                let mut tx = first_db.begin().await?;
                let result = allocate_tx(
                    &mut tx,
                    &first_player,
                    "achievement_claim",
                    "one",
                    &first_cfg,
                )
                .await?;
                tx.commit().await?;
                Ok::<Vec<Value>, anyhow::Error>(result)
            },
            async move {
                let mut tx = second_db.begin().await?;
                let result = allocate_tx(
                    &mut tx,
                    &second_player,
                    "achievement_claim",
                    "one",
                    &second_cfg,
                )
                .await?;
                tx.commit().await?;
                Ok::<Vec<Value>, anyhow::Error>(result)
            }
        );
        let results = [first?, second?];
        assert_eq!(
            results
                .iter()
                .map(|result| result[0]["amountU64"].as_i64().unwrap_or(0))
                .sum::<i64>(),
            100
        );
        assert_eq!(
            results
                .iter()
                .filter(|result| result[0]["exhausted"] == true)
                .count(),
            1
        );

        sqlx::query("DELETE FROM player_state WHERE address=$1 OR address=$2")
            .bind(&first_address)
            .bind(&second_address)
            .execute(db.pool())
            .await?;
        sqlx::query("DELETE FROM players WHERE address=$1 OR address=$2")
            .bind(&first_address)
            .bind(&second_address)
            .execute(db.pool())
            .await?;
        Ok(())
    }
}
