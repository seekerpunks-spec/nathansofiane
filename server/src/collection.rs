//! Coffres, cartes, doublons et récompenses de collection.

use crate::auth::Addr;
use crate::config::{CardConfig, ChestConfig, Reward};
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, State};
use axum::http::HeaderMap;
use axum::Json;
use rand::Rng;
use serde::Deserialize;
use serde_json::{json, Value};

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

fn pick_weighted<'a, T, F>(items: &'a [T], weight: F) -> Option<&'a T>
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

fn draw_card<'a>(chest: &ChestConfig, cards: &'a [CardConfig]) -> Option<&'a CardConfig> {
    let rarity = pick_weighted(&chest.loot_table, |l| l.weight).map(|l| l.rarity)?;
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
    sqlx::query("INSERT INTO player_chests(address,chest_id,qty) VALUES($1,$2,1) ON CONFLICT(address,chest_id) DO UPDATE SET qty=player_chests.qty+1")
        .bind(&addr.0).bind(&chest.chest_id).execute(&mut *tx).await?;
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
    let _player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(v) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(v));
    }
    let qty: i32 = sqlx::query_scalar(
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
        let card = draw_card(chest, &state.config.cards)
            .ok_or_else(|| ApiError::Internal(anyhow!("loot table sans carte compatible")))?;
        let new_qty: i32 = sqlx::query_scalar(
            "INSERT INTO player_cards(address,card_id,qty) VALUES($1,$2,1) ON CONFLICT(address,card_id) DO UPDATE SET qty=player_cards.qty+1 RETURNING qty",
        ).bind(&addr.0).bind(&card.card_id).fetch_one(&mut *tx).await?;
        drops.push(json!({"cardId": card.card_id, "setId": card.set_id, "name": card.name, "rarity": card.rarity, "qty": new_qty, "duplicate": new_qty > 1}));
    }
    game::progress_action_tx(&mut tx, &addr.0, "chest_open", 1, &state.config).await?;
    let before = json!({"chestId": chest.chest_id, "qty": qty});
    let after = json!({"chestId": chest.chest_id, "qty": qty - 1, "drops": drops});
    Db::audit_tx(&mut tx, &addr.0, "chest_open", &before, &after, Some(&rid)).await?;
    let response = json!({"chestId": chest.chest_id, "remaining": qty - 1, "cards": drops, "serverTimeMs": chrono::Utc::now().timestamp_millis()});
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
    let reward = Reward {
        spins: set.completion_spins,
        credits: 0,
        chest: None,
    };
    game::grant_reward_tx(&mut tx, &addr.0, &reward).await?;
    let response = json!({"setId": set.set_id, "reward": reward, "spins": player.spins + set.completion_spins as i32, "serverTimeMs": chrono::Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "set_complete",
        &json!({"spins": player.spins}),
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

    #[test]
    fn empty_weight_list_returns_none() {
        let cards: Vec<CardConfig> = Vec::new();
        assert!(pick_weighted(&cards, |c| c.drop_weight).is_none());
    }
}
