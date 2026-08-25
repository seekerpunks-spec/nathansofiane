//! Coffres, cartes, doublons et récompenses de collection.

use crate::auth::Addr;
use crate::config::{CardConfig, LootWeight};
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::progression;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, State};
use axum::http::HeaderMap;
use axum::Json;
use rand::Rng;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{Postgres, Transaction};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChestReq {
    chest_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetReq {
    set_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

fn pick_weighted<T, F>(items: &[T], weight: F) -> Option<&T>
where
    F: Fn(&T) -> u32,
{
    let total: u32 = items.iter().map(&weight).sum();
    if total == 0 {
        return None;
    }
    let pick = rand::rngs::OsRng.gen_range(0..total);
    let mut acc = 0u32;
    items.iter().find(|item| {
        acc += weight(item);
        pick < acc
    })
}

fn draw_card<'a>(loot_table: &[LootWeight], cards: &'a [CardConfig]) -> Option<&'a CardConfig> {
    let rarity = pick_weighted(loot_table, |l| l.weight).map(|l| l.rarity)?;
    let eligible: Vec<&CardConfig> = cards.iter().filter(|c| c.rarity == rarity).collect();
    if eligible.is_empty() {
        return pick_weighted(cards, |c| c.drop_weight);
    }
    let total: u32 = eligible.iter().map(|c| c.drop_weight).sum();
    if total == 0 {
        return None;
    }
    let pick = rand::rngs::OsRng.gen_range(0..total);
    let mut acc = 0u32;
    eligible.into_iter().find(|card| {
        acc += card.drop_weight;
        pick < acc
    })
}

pub async fn grant_spin_chest_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    chest_id: &str,
    amount: u32,
) -> Result<Value, ApiError> {
    let amount = i64::from(amount);
    let qty: Option<i64> = sqlx::query_scalar(
        "INSERT INTO player_chests(address,chest_id,qty) VALUES($1,$2,$3) \
         ON CONFLICT(address,chest_id) DO UPDATE SET qty=player_chests.qty+EXCLUDED.qty \
         WHERE player_chests.qty <= 9223372036854775807-EXCLUDED.qty RETURNING qty",
    )
    .bind(address)
    .bind(chest_id)
    .bind(amount)
    .fetch_optional(&mut **tx)
    .await?;
    let qty =
        qty.ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: spin.chestInventory")))?;
    Ok(json!({"chestId":chest_id,"quantity":qty,"quantityAdded":amount}))
}

pub async fn grant_spin_card_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    cards: &[CardConfig],
    amount: u32,
) -> Result<Value, ApiError> {
    let card = pick_weighted(cards, |candidate| candidate.drop_weight)
        .ok_or_else(|| ApiError::Internal(anyhow!("aucune carte tirable")))?;
    let amount = i64::from(amount);
    let qty: Option<i64> = sqlx::query_scalar(
        "INSERT INTO player_cards(address,card_id,qty) VALUES($1,$2,$3) \
         ON CONFLICT(address,card_id) DO UPDATE SET qty=player_cards.qty+EXCLUDED.qty \
         WHERE player_cards.qty <= 9223372036854775807-EXCLUDED.qty RETURNING qty",
    )
    .bind(address)
    .bind(&card.card_id)
    .bind(amount)
    .fetch_optional(&mut **tx)
    .await?;
    let qty =
        qty.ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: spin.cardInventory")))?;
    Ok(
        json!({"cardId":card.card_id,"setId":card.set_id,"name":card.name,"rarity":card.rarity,"quantity":qty,"quantityAdded":amount,"duplicate":qty>amount}),
    )
}

pub async fn buy_chest(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<ChestReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("chest_buy", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let chest = state
        .config
        .chests
        .iter()
        .find(|c| c.chest_id == body.chest_id)
        .ok_or(ApiError::NotFound)?;
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
    if player.credits < chest.price_credits as i64 {
        tx.rollback().await?;
        return Err(ApiError::InsufficientCredits);
    }
    let credits = player.credits - chest.price_credits as i64;
    sqlx::query("UPDATE player_state SET credits=$1 WHERE address=$2")
        .bind(credits)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    let quantity: Option<i64> = sqlx::query_scalar(
        "INSERT INTO player_chests(address,chest_id,qty) VALUES($1,$2,1) \
         ON CONFLICT(address,chest_id) DO UPDATE SET qty=player_chests.qty+1 \
         WHERE player_chests.qty < 9223372036854775807 RETURNING qty",
    )
    .bind(&addr.0)
    .bind(&chest.chest_id)
    .fetch_optional(&mut *tx)
    .await?;
    if quantity.is_none() {
        return Err(ApiError::Internal(anyhow!(
            "overflow économique: chest.inventory"
        )));
    }
    let before = json!({"credits": player.credits});
    let after = json!({"credits": credits, "chestId": chest.chest_id, "qtyDelta": 1});
    Db::audit_tx(&mut tx, &addr.0, "chest_buy", &before, &after, Some(&rid)).await?;
    let response = json!({"chestId": chest.chest_id, "credits": credits, "serverTimeMs": chrono::Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn open_chest(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<ChestReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("chest_open", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let chest = state
        .config
        .chests
        .iter()
        .find(|c| c.chest_id == body.chest_id)
        .ok_or(ApiError::NotFound)?;
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
    // Table résolue une fois par ouverture : la progression et les événements
    // en cours sont figés pour toutes les cartes du même coffre.
    let active_events = state
        .config
        .active_event_ids(chrono::Utc::now().timestamp_millis());
    let loot_table = state.config.resolved_loot_table(
        chest,
        player.district_index.max(0) as u32,
        &active_events,
    );
    let qty: i64 = sqlx::query_scalar(
        "SELECT qty FROM player_chests WHERE address=$1 AND chest_id=$2 FOR UPDATE",
    )
    .bind(&addr.0)
    .bind(&chest.chest_id)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    if qty < 1 {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("aucun coffre de ce type".to_string()));
    }
    sqlx::query("UPDATE player_chests SET qty=qty-1 WHERE address=$1 AND chest_id=$2")
        .bind(&addr.0)
        .bind(&chest.chest_id)
        .execute(&mut *tx)
        .await?;
    let mut drops = Vec::new();
    for _ in 0..chest.cards_per_open {
        let card = draw_card(&loot_table, &state.config.cards)
            .ok_or_else(|| ApiError::Internal(anyhow!("loot table sans carte compatible")))?;
        let new_qty: Option<i64> = sqlx::query_scalar(
            "INSERT INTO player_cards(address,card_id,qty) VALUES($1,$2,1) \
             ON CONFLICT(address,card_id) DO UPDATE SET qty=player_cards.qty+1 \
             WHERE player_cards.qty < 9223372036854775807 RETURNING qty",
        )
        .bind(&addr.0)
        .bind(&card.card_id)
        .fetch_optional(&mut *tx)
        .await?;
        let new_qty = new_qty.ok_or_else(|| {
            ApiError::Internal(anyhow!("overflow économique: chest.cardInventory"))
        })?;
        drops.push(json!({"cardId": card.card_id, "setId": card.set_id, "name": card.name, "rarity": card.rarity, "qty": new_qty, "duplicate": new_qty > 1}));
    }
    let _progress =
        game::progress_action_tx(&mut tx, &addr.0, "chest_open", 1, &state.config).await?;
    let global_progression = progression::refresh_score_tx(&mut tx, &addr.0, &state.config).await?;
    let before = json!({"chestId": chest.chest_id, "qty": qty});
    let after = json!({"chestId": chest.chest_id, "qty": qty - 1, "drops": drops});
    Db::audit_tx(&mut tx, &addr.0, "chest_open", &before, &after, Some(&rid)).await?;
    let response = json!({"chestId": chest.chest_id, "remaining": qty - 1, "cards": drops, "globalProgression":progression::score_json(global_progression,&state.config), "serverTimeMs": chrono::Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn claim_set(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<SetReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("set_claim", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let set = state
        .config
        .sets
        .iter()
        .find(|s| s.set_id == body.set_id)
        .ok_or(ApiError::NotFound)?;
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
    let already: Option<bool> = sqlx::query_scalar(
        "SELECT claimed FROM set_completion WHERE address=$1 AND set_id=$2 FOR UPDATE",
    )
    .bind(&addr.0)
    .bind(&set.set_id)
    .fetch_optional(&mut *tx)
    .await?;
    if already.unwrap_or(false) {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    // Le prérequis de déblocage est arbitré ici : côté client il n'est
    // qu'un affichage, donc le laisser hors du serveur le rendrait décoratif.
    if let Some(requirement) = &set.unlock_requirement {
        if requirement
            .completed_district_id
            .is_some_and(|id| player.district_index < id as i32)
        {
            tx.rollback().await?;
            return Err(ApiError::Unavailable("set verrouillé".to_string()));
        }
        if let Some(required_set) = requirement.completed_set_id.as_deref() {
            let claimed: Option<bool> = sqlx::query_scalar(
                "SELECT claimed FROM set_completion WHERE address=$1 AND set_id=$2",
            )
            .bind(&addr.0)
            .bind(required_set)
            .fetch_optional(&mut *tx)
            .await?;
            if !claimed.unwrap_or(false) {
                tx.rollback().await?;
                return Err(ApiError::Unavailable("set verrouillé".to_string()));
            }
        }
    }
    let owned: Vec<String> =
        sqlx::query_scalar("SELECT card_id FROM player_cards WHERE address=$1 AND qty>0")
            .bind(&addr.0)
            .fetch_all(&mut *tx)
            .await?;
    if !set.cards.iter().all(|id| owned.contains(id)) {
        tx.rollback().await?;
        return Err(ApiError::Unavailable("collection incomplète".to_string()));
    }
    sqlx::query("INSERT INTO set_completion(address,set_id,claimed) VALUES($1,$2,true) ON CONFLICT(address,set_id) DO UPDATE SET claimed=true")
        .bind(&addr.0).bind(&set.set_id).execute(&mut *tx).await?;
    let reward = set.effective_reward();
    game::grant_reward_tx(&mut tx, &addr.0, &reward, &state.config).await?;
    let global_progression = progression::refresh_score_tx(&mut tx, &addr.0, &state.config).await?;
    // Relire le solde autoritaire : `grant_reward_tx` applique aussi la regen
    // non persistée et vérifie l'overflow. Recalculer ici divergeait.
    let balances: (i32, i64) =
        sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    let response = json!({"setId": set.set_id, "reward": reward, "spins": balances.0, "credits": balances.1, "globalProgression":progression::score_json(global_progression,&state.config), "serverTimeMs": chrono::Utc::now().timestamp_millis()});
    // Les sets accordent désormais spins, crédits et coffre : journaliser le
    // seul solde de spins laisserait la trace économique incomplète.
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "set_complete",
        &json!({"spins": player.spins, "credits": player.credits, "districtIndex": player.district_index}),
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
    use crate::config::RemoteConfig;
    use crate::rate_limit::RateLimiter;
    use std::sync::Arc;

    #[test]
    fn empty_weight_list_returns_none() {
        let cards: Vec<CardConfig> = Vec::new();
        assert!(pick_weighted(&cards, |c| c.drop_weight).is_none());
    }

    /// AppState complet pour appeler les handlers axum comme en production
    /// (mêmes transactions, même config de lancement, même idempotence).
    fn state_for_tests(db: Db) -> anyhow::Result<AppState> {
        let config = RemoteConfig::load(
            &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../config"),
        )?;
        Ok(AppState {
            rate: Arc::new(RateLimiter::new(
                db.pool().clone(),
                std::time::Duration::from_secs(60),
                10_000,
            )),
            db,
            config: Arc::new(config),
            jwt_secret: "qa-secret-0123456789-0123456789-012".to_string(),
            dev_auth: false,
            dev_address: None,
            started_at: std::time::Instant::now(),
        })
    }

    async fn grant_cards(db: &Db, address: &str, cards: &[String]) -> anyhow::Result<()> {
        for card_id in cards {
            sqlx::query(
                "INSERT INTO player_cards(address,card_id,qty) VALUES($1,$2,1) \
                 ON CONFLICT(address,card_id) DO UPDATE SET qty=player_cards.qty+1",
            )
            .bind(address)
            .bind(card_id)
            .execute(db.pool())
            .await?;
        }
        Ok(())
    }

    async fn balances(db: &Db, address: &str) -> anyhow::Result<(i32, i64)> {
        Ok(
            sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
                .bind(address)
                .fetch_one(db.pool())
                .await?,
        )
    }

    #[tokio::test]
    async fn postgres_claim_set_enforces_unlock_then_pays_once() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_claim_set_enforces_unlock_then_pays_once").await
        else {
            return Ok(());
        };
        let state = state_for_tests(db.clone())?;
        let address = format!("qa-set-{}", uuid::Uuid::new_v4());
        db.ensure_player(&address, 5).await?;

        let locked_set = state
            .config
            .sets
            .iter()
            .find(|set| {
                set.unlock_requirement
                    .as_ref()
                    .is_some_and(|requirement| requirement.completed_district_id.is_some())
            })
            .expect("la config de lancement doit contenir un set verrouillé par district")
            .clone();
        grant_cards(&db, &address, &locked_set.cards).await?;

        // Cartes complètes mais district insuffisant : le serveur arbitre.
        let locked = claim_set(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(SetReq {
                set_id: locked_set.set_id.clone(),
                request_id: Some(uuid::Uuid::new_v4().to_string()),
            }),
        )
        .await;
        assert!(matches!(locked, Err(ApiError::Unavailable(_))));
        let untouched = balances(&db, &address).await?;
        assert_eq!(untouched, (5, 0));

        let required_district = locked_set
            .unlock_requirement
            .as_ref()
            .and_then(|requirement| requirement.completed_district_id)
            .expect("prérequis district du set verrouillé");
        sqlx::query("UPDATE player_state SET district_index=$1 WHERE address=$2")
            .bind(required_district as i32)
            .bind(&address)
            .execute(db.pool())
            .await?;

        let before = balances(&db, &address).await?;
        let reward = locked_set.effective_reward();
        let rid = uuid::Uuid::new_v4().to_string();
        let paid = claim_set(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(SetReq {
                set_id: locked_set.set_id.clone(),
                request_id: Some(rid.clone()),
            }),
        )
        .await
        .map_err(|error| anyhow!("claim débloqué refusé : {error:?}"))?
        .0;
        let after = balances(&db, &address).await?;
        assert_eq!(after.0, before.0 + reward.spins as i32);
        assert_eq!(after.1, before.1 + i64::try_from(reward.credits)?);
        if let Some(chest_id) = &reward.chest {
            let qty: i64 = sqlx::query_scalar(
                "SELECT qty FROM player_chests WHERE address=$1 AND chest_id=$2",
            )
            .bind(&address)
            .bind(chest_id)
            .fetch_one(db.pool())
            .await?;
            assert_eq!(qty, 1);
        }

        // Rejeu du même requestId : réponse identique octet pour octet,
        // aucun second versement.
        let replayed = claim_set(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(SetReq {
                set_id: locked_set.set_id.clone(),
                request_id: Some(rid),
            }),
        )
        .await
        .map_err(|error| anyhow!("rejeu idempotent refusé : {error:?}"))?
        .0;
        assert_eq!(paid, replayed);
        assert_eq!(balances(&db, &address).await?, after);
        Ok(())
    }

    #[tokio::test]
    async fn postgres_claim_set_has_single_concurrent_winner() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_claim_set_has_single_concurrent_winner").await
        else {
            return Ok(());
        };
        let state = state_for_tests(db.clone())?;
        let address = format!("qa-race-{}", uuid::Uuid::new_v4());
        db.ensure_player(&address, 0).await?;

        let open_set = state
            .config
            .sets
            .iter()
            .find(|set| set.unlock_requirement.is_none())
            .expect("la config de lancement doit contenir un set sans prérequis")
            .clone();
        grant_cards(&db, &address, &open_set.cards).await?;

        let first_call = claim_set(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(SetReq {
                set_id: open_set.set_id.clone(),
                request_id: Some(uuid::Uuid::new_v4().to_string()),
            }),
        );
        let second_call = claim_set(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(SetReq {
                set_id: open_set.set_id.clone(),
                request_id: Some(uuid::Uuid::new_v4().to_string()),
            }),
        );
        let (first, second) = tokio::join!(first_call, second_call);
        let outcomes = [first, second];
        assert_eq!(
            outcomes.iter().filter(|outcome| outcome.is_ok()).count(),
            1,
            "exactement un claim concurrent doit gagner"
        );
        assert!(outcomes
            .iter()
            .any(|outcome| matches!(outcome, Err(ApiError::AlreadyClaimed))));

        let reward = open_set.effective_reward();
        let after = balances(&db, &address).await?;
        assert_eq!(after.0, reward.spins as i32, "un seul versement de spins");
        assert_eq!(after.1, i64::try_from(reward.credits)?);
        Ok(())
    }

    #[tokio::test]
    async fn postgres_open_chest_consumes_stock_once_and_replays() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_open_chest_consumes_stock_once_and_replays").await
        else {
            return Ok(());
        };
        let state = state_for_tests(db.clone())?;
        let address = format!("qa-chest-{}", uuid::Uuid::new_v4());
        db.ensure_player(&address, 0).await?;
        let chest = state.config.chests[0].clone();
        sqlx::query("INSERT INTO player_chests(address,chest_id,qty) VALUES($1,$2,1)")
            .bind(&address)
            .bind(&chest.chest_id)
            .execute(db.pool())
            .await?;

        // Stock de 1 : deux ouvertures concurrentes ne peuvent pas consommer
        // deux coffres.
        let first_rid = uuid::Uuid::new_v4().to_string();
        let second_rid = uuid::Uuid::new_v4().to_string();
        let first_call = open_chest(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(ChestReq {
                chest_id: chest.chest_id.clone(),
                request_id: Some(first_rid.clone()),
            }),
        );
        let second_call = open_chest(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(ChestReq {
                chest_id: chest.chest_id.clone(),
                request_id: Some(second_rid.clone()),
            }),
        );
        let (first, second) = tokio::join!(first_call, second_call);
        let (winner, winner_rid) = match (first, second) {
            (Ok(response), Err(ApiError::Unavailable(_))) => (response.0, first_rid),
            (Err(ApiError::Unavailable(_)), Ok(response)) => (response.0, second_rid),
            other => anyhow::bail!("attendu un gagnant et un refus, obtenu {other:?}"),
        };
        assert_eq!(winner["remaining"], 0);
        let drops = winner["cards"]
            .as_array()
            .ok_or_else(|| anyhow!("réponse sans cartes"))?;
        assert_eq!(drops.len(), chest.cards_per_open as usize);

        // Chaque rareté tirée doit être tirable dans la table résolue pour ce
        // joueur (district 0, événements actifs du moment) : c'est bien la
        // table centralisée qui gouverne le tirage.
        let active = state
            .config
            .active_event_ids(chrono::Utc::now().timestamp_millis());
        let allowed: Vec<Value> = state
            .config
            .resolved_loot_table(&chest, 0, &active)
            .iter()
            .filter(|weight| weight.weight > 0)
            .map(|weight| serde_json::to_value(weight.rarity).unwrap())
            .collect();
        for drop in drops {
            assert!(
                allowed.contains(&drop["rarity"]),
                "rareté {} hors table résolue",
                drop["rarity"]
            );
        }

        // Rejeu du requestId gagnant : même réponse, inventaire intact.
        let total_before_replay: i64 = sqlx::query_scalar(
            "SELECT COALESCE(SUM(qty),0)::bigint FROM player_cards WHERE address=$1",
        )
        .bind(&address)
        .fetch_one(db.pool())
        .await?;
        let replayed = open_chest(
            State(state.clone()),
            Extension(Addr(address.clone())),
            HeaderMap::new(),
            Json(ChestReq {
                chest_id: chest.chest_id.clone(),
                request_id: Some(winner_rid),
            }),
        )
        .await
        .map_err(|error| anyhow!("rejeu idempotent refusé : {error:?}"))?
        .0;
        assert_eq!(winner, replayed);
        let total_after_replay: i64 = sqlx::query_scalar(
            "SELECT COALESCE(SUM(qty),0)::bigint FROM player_cards WHERE address=$1",
        )
        .bind(&address)
        .fetch_one(db.pool())
        .await?;
        assert_eq!(total_before_replay, total_after_replay);
        assert_eq!(
            total_after_replay,
            i64::from(chest.cards_per_open),
            "le stock d'un seul coffre ne produit qu'une ouverture"
        );
        Ok(())
    }
}
