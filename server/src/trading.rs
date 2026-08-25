//! Échanges directs de doublons : une carte contre une carte, jamais de SKR.

use crate::auth::Addr;
use crate::config::{CardConfig, RemoteConfig};
use crate::error::ApiError;
use crate::friends;
use crate::game;
use crate::progression;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{FromRow, Postgres, Transaction};
use uuid::Uuid;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateTradeReq {
    recipient_friend_code: String,
    offered_card_id: String,
    requested_card_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TradeActionReq {
    trade_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Debug, FromRow)]
struct TradeRow {
    trade_id: String,
    sender: String,
    recipient: String,
    offered_card_id: String,
    requested_card_id: String,
    status: String,
    expires_at: DateTime<Utc>,
}

#[derive(Debug, FromRow)]
struct TradeListRow {
    trade_id: String,
    offered_card_id: String,
    requested_card_id: String,
    status: String,
    created_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
    counterparty_player_id: String,
    counterparty_display_name: String,
}

fn canonical_trade_id(raw: &str) -> Result<String, ApiError> {
    Uuid::parse_str(raw.trim())
        .map(|id| id.to_string())
        .map_err(|_| ApiError::BadRequest("tradeId invalide".to_string()))
}

fn card<'a>(config: &'a RemoteConfig, card_id: &str) -> Result<&'a CardConfig, ApiError> {
    config
        .cards
        .iter()
        .find(|card| card.card_id == card_id)
        .ok_or(ApiError::NotFound)
}

fn ensure_tradeable(config: &RemoteConfig, card: &CardConfig) -> Result<(), ApiError> {
    if !config
        .social
        .trading
        .tradeable_rarities
        .contains(&card.rarity)
    {
        return Err(ApiError::Unavailable(
            "rareté non échangeable actuellement".to_string(),
        ));
    }
    Ok(())
}

async fn lock_players_tx(
    tx: &mut Transaction<'_, Postgres>,
    first: &str,
    second: &str,
) -> Result<(), ApiError> {
    let rows: Vec<String> = sqlx::query_scalar(
        "SELECT address FROM player_state WHERE address=$1 OR address=$2 ORDER BY address FOR UPDATE",
    )
    .bind(first)
    .bind(second)
    .fetch_all(&mut **tx)
    .await?;
    if rows.len() != 2 {
        return Err(ApiError::NotFound);
    }
    Ok(())
}

async fn reserved_outgoing_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    card_id: &str,
    excluding_trade_id: Option<&str>,
) -> Result<i64, ApiError> {
    Ok(sqlx::query_scalar(
        "SELECT COUNT(*)::bigint FROM card_trade_offers WHERE sender=$1 AND offered_card_id=$2 \
         AND status='pending' AND expires_at>now() AND ($3::text IS NULL OR trade_id<>$3)",
    )
    .bind(address)
    .bind(card_id)
    .bind(excluding_trade_id)
    .fetch_one(&mut **tx)
    .await?)
}

async fn quantity_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    card_id: &str,
) -> Result<i64, ApiError> {
    Ok(sqlx::query_scalar(
        "SELECT qty FROM player_cards WHERE address=$1 AND card_id=$2 FOR UPDATE",
    )
    .bind(address)
    .bind(card_id)
    .fetch_optional(&mut **tx)
    .await?
    .unwrap_or(0))
}

fn can_spend_duplicate(qty: i64, reserved: i64, minimum: u32) -> bool {
    let keep = i64::from(minimum.saturating_sub(1));
    qty - keep - reserved >= 1
}

async fn expire_for_tx(tx: &mut Transaction<'_, Postgres>, address: &str) -> Result<(), ApiError> {
    sqlx::query(
        "UPDATE card_trade_offers SET status='expired',resolved_at=now() WHERE status='pending' \
         AND expires_at<=now() AND (sender=$1 OR recipient=$1)",
    )
    .bind(address)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub async fn create(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<CreateTradeReq>,
) -> Result<Json<Value>, ApiError> {
    if body.offered_card_id == body.requested_card_id {
        return Err(ApiError::BadRequest(
            "les deux cartes doivent différer".to_string(),
        ));
    }
    let offered = card(&state.config, &body.offered_card_id)?;
    let requested = card(&state.config, &body.requested_card_id)?;
    ensure_tradeable(&state.config, offered)?;
    ensure_tradeable(&state.config, requested)?;
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("trade_create", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let recipient = friends::address_from_code_tx(&mut tx, &body.recipient_friend_code).await?;
    if recipient == addr.0 {
        return Err(ApiError::BadRequest("destinataire invalide".to_string()));
    }
    lock_players_tx(&mut tx, &addr.0, &recipient).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    expire_for_tx(&mut tx, &addr.0).await?;
    if !friends::are_friends_tx(&mut tx, &addr.0, &recipient).await? {
        return Err(ApiError::Unavailable(
            "échange réservé aux amis".to_string(),
        ));
    }
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::bigint FROM card_trade_offers WHERE sender=$1 AND status='pending' AND expires_at>now()",
    )
    .bind(&addr.0)
    .fetch_one(&mut *tx)
    .await?;
    if pending >= i64::from(state.config.social.trading.max_pending_per_player) {
        return Err(ApiError::Unavailable("trop d'offres pending".to_string()));
    }
    let offered_qty = quantity_tx(&mut tx, &addr.0, &offered.card_id).await?;
    let sender_reserved = reserved_outgoing_tx(&mut tx, &addr.0, &offered.card_id, None).await?;
    let requested_qty = quantity_tx(&mut tx, &recipient, &requested.card_id).await?;
    if !can_spend_duplicate(
        offered_qty,
        sender_reserved,
        state.config.social.trading.min_quantity_to_trade,
    ) || requested_qty < i64::from(state.config.social.trading.min_quantity_to_trade)
    {
        return Err(ApiError::Unavailable(
            "doublon indisponible chez un joueur".to_string(),
        ));
    }
    let ttl = i64::try_from(state.config.social.trading.offer_ttl_ms)
        .map_err(|_| ApiError::Internal(anyhow!("trade offer TTL overflow")))?;
    let expires_at = Utc::now() + chrono::Duration::milliseconds(ttl);
    let trade_id = Uuid::new_v4().to_string();
    sqlx::query(
        "INSERT INTO card_trade_offers(trade_id,sender,recipient,offered_card_id,requested_card_id,expires_at) \
         VALUES($1,$2,$3,$4,$5,$6)",
    )
    .bind(&trade_id)
    .bind(&addr.0)
    .bind(&recipient)
    .bind(&offered.card_id)
    .bind(&requested.card_id)
    .bind(expires_at)
    .execute(&mut *tx)
    .await?;
    let response = json!({"tradeId":trade_id,"status":"pending","recipientPlayerId":body.recipient_friend_code.trim().to_uppercase(),"offeredCardId":offered.card_id,"requestedCardId":requested.card_id,"expiresAtMs":expires_at.timestamp_millis(),"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

async fn prefetch_trade(state: &AppState, trade_id: &str) -> Result<TradeRow, ApiError> {
    sqlx::query_as(
        "SELECT trade_id,sender,recipient,offered_card_id,requested_card_id,status,expires_at \
         FROM card_trade_offers WHERE trade_id=$1",
    )
    .bind(trade_id)
    .fetch_optional(state.db.pool())
    .await?
    .ok_or(ApiError::NotFound)
}

async fn load_trade_locked_tx(
    tx: &mut Transaction<'_, Postgres>,
    trade_id: &str,
) -> Result<TradeRow, ApiError> {
    sqlx::query_as(
        "SELECT trade_id,sender,recipient,offered_card_id,requested_card_id,status,expires_at \
         FROM card_trade_offers WHERE trade_id=$1 FOR UPDATE",
    )
    .bind(trade_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(ApiError::NotFound)
}

fn ensure_pending(row: &TradeRow) -> Result<(), ApiError> {
    if row.status != "pending" {
        return Err(ApiError::Unavailable("offre déjà terminée".to_string()));
    }
    if row.expires_at <= Utc::now() {
        return Err(ApiError::Unavailable("offre expirée".to_string()));
    }
    Ok(())
}

pub async fn accept(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<TradeActionReq>,
) -> Result<Json<Value>, ApiError> {
    let trade_id = canonical_trade_id(&body.trade_id)?;
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key(&format!("trade_accept:{trade_id}"), &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let snapshot = prefetch_trade(&state, &trade_id).await?;
    if snapshot.recipient != addr.0 {
        return Err(ApiError::NotFound);
    }
    let mut tx = state.db.begin().await?;
    lock_players_tx(&mut tx, &snapshot.sender, &snapshot.recipient).await?;
    let row = load_trade_locked_tx(&mut tx, &trade_id).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    ensure_pending(&row)?;
    if row.recipient != addr.0 {
        return Err(ApiError::NotFound);
    }
    let sender_qty = quantity_tx(&mut tx, &row.sender, &row.offered_card_id).await?;
    let sender_reserved = reserved_outgoing_tx(
        &mut tx,
        &row.sender,
        &row.offered_card_id,
        Some(&row.trade_id),
    )
    .await?;
    let recipient_qty = quantity_tx(&mut tx, &row.recipient, &row.requested_card_id).await?;
    let recipient_reserved =
        reserved_outgoing_tx(&mut tx, &row.recipient, &row.requested_card_id, None).await?;
    let minimum = state.config.social.trading.min_quantity_to_trade;
    if !can_spend_duplicate(sender_qty, sender_reserved, minimum)
        || !can_spend_duplicate(recipient_qty, recipient_reserved, minimum)
    {
        return Err(ApiError::Unavailable(
            "un doublon n'est plus disponible".to_string(),
        ));
    }
    sqlx::query("UPDATE player_cards SET qty=qty-1 WHERE address=$1 AND card_id=$2")
        .bind(&row.sender)
        .bind(&row.offered_card_id)
        .execute(&mut *tx)
        .await?;
    let recipient_offered_qty: Option<i64> = sqlx::query_scalar(
        "INSERT INTO player_cards(address,card_id,qty) VALUES($1,$2,1) ON CONFLICT(address,card_id) \
         DO UPDATE SET qty=player_cards.qty+1 WHERE player_cards.qty < 9223372036854775807 RETURNING qty",
    )
    .bind(&row.recipient)
    .bind(&row.offered_card_id)
    .fetch_optional(&mut *tx)
    .await?;
    let recipient_offered_qty = recipient_offered_qty.ok_or_else(|| {
        ApiError::Internal(anyhow!("overflow économique: trade.recipientInventory"))
    })?;
    sqlx::query("UPDATE player_cards SET qty=qty-1 WHERE address=$1 AND card_id=$2")
        .bind(&row.recipient)
        .bind(&row.requested_card_id)
        .execute(&mut *tx)
        .await?;
    let sender_requested_qty: Option<i64> = sqlx::query_scalar(
        "INSERT INTO player_cards(address,card_id,qty) VALUES($1,$2,1) ON CONFLICT(address,card_id) \
         DO UPDATE SET qty=player_cards.qty+1 WHERE player_cards.qty < 9223372036854775807 RETURNING qty",
    )
    .bind(&row.sender)
    .bind(&row.requested_card_id)
    .fetch_optional(&mut *tx)
    .await?;
    let sender_requested_qty = sender_requested_qty
        .ok_or_else(|| ApiError::Internal(anyhow!("overflow économique: trade.senderInventory")))?;
    sqlx::query(
        "UPDATE card_trade_offers SET status='accepted',resolved_at=now() WHERE trade_id=$1",
    )
    .bind(&row.trade_id)
    .execute(&mut *tx)
    .await?;
    let sender_progression =
        progression::refresh_score_tx(&mut tx, &row.sender, &state.config).await?;
    let recipient_progression =
        progression::refresh_score_tx(&mut tx, &row.recipient, &state.config).await?;
    let response = json!({"tradeId":row.trade_id,"status":"accepted","offeredCardId":row.offered_card_id,"requestedCardId":row.requested_card_id,"senderRequestedQuantity":sender_requested_qty,"recipientOfferedQuantity":recipient_offered_qty,"globalProgression":progression::score_json(recipient_progression,&state.config),"serverTimeMs":Utc::now().timestamp_millis()});
    crate::db::Db::audit_tx(
        &mut tx,
        &row.sender,
        "card_trade",
        &json!({"offeredCardId":row.offered_card_id,"requestedCardId":row.requested_card_id}),
        &json!({"status":"accepted","globalScore":sender_progression.total}),
        Some(&rid),
    )
    .await?;
    crate::db::Db::audit_tx(
        &mut tx,
        &row.recipient,
        "card_trade",
        &json!({"offeredCardId":row.requested_card_id,"requestedCardId":row.offered_card_id}),
        &json!({"status":"accepted","globalScore":recipient_progression.total}),
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

async fn resolve_without_exchange(
    state: &AppState,
    actor: &str,
    trade_id: &str,
    rid: &str,
    status: &str,
) -> Result<Value, ApiError> {
    let action = format!("trade_{status}:{trade_id}");
    let key = game::idem_key(&action, actor, rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(value);
    }
    let snapshot = prefetch_trade(state, trade_id).await?;
    let authorized = (status == "declined" && snapshot.recipient == actor)
        || (status == "cancelled" && snapshot.sender == actor);
    if !authorized {
        return Err(ApiError::NotFound);
    }
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT address FROM player_state WHERE address=$1 FOR UPDATE")
        .bind(actor)
        .fetch_one(&mut *tx)
        .await?;
    let row = load_trade_locked_tx(&mut tx, trade_id).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(value);
    }
    ensure_pending(&row)?;
    sqlx::query("UPDATE card_trade_offers SET status=$1,resolved_at=now() WHERE trade_id=$2")
        .bind(status)
        .bind(trade_id)
        .execute(&mut *tx)
        .await?;
    let response =
        json!({"tradeId":trade_id,"status":status,"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(response)
}

macro_rules! trade_handler {
    ($name:ident, $status:literal) => {
        pub async fn $name(
            State(state): State<AppState>,
            Extension(addr): Extension<Addr>,
            headers: HeaderMap,
            Json(body): Json<TradeActionReq>,
        ) -> Result<Json<Value>, ApiError> {
            let trade_id = canonical_trade_id(&body.trade_id)?;
            let rid = game::request_id(&headers, body.request_id.as_deref())?;
            Ok(Json(
                resolve_without_exchange(&state, &addr.0, &trade_id, &rid, $status).await?,
            ))
        }
    };
}

trade_handler!(decline, "declined");
trade_handler!(cancel, "cancelled");

fn public_trade(row: TradeListRow, config: &RemoteConfig, incoming: bool) -> Value {
    let offered = config
        .cards
        .iter()
        .find(|card| card.card_id == row.offered_card_id);
    let requested = config
        .cards
        .iter()
        .find(|card| card.card_id == row.requested_card_id);
    json!({
        "tradeId":row.trade_id,"status":row.status,"incoming":incoming,
        "counterpartyPlayerId":row.counterparty_player_id,"counterpartyDisplayName":row.counterparty_display_name,
        "offeredCardId":row.offered_card_id,"offeredCardName":offered.map(|card|card.name.as_str()).unwrap_or("Unknown"),
        "requestedCardId":row.requested_card_id,"requestedCardName":requested.map(|card|card.name.as_str()).unwrap_or("Unknown"),
        "createdAtMs":row.created_at.timestamp_millis(),"expiresAtMs":row.expires_at.timestamp_millis()
    })
}

pub async fn list(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
) -> Result<Json<Value>, ApiError> {
    let mut tx = state.db.begin().await?;
    expire_for_tx(&mut tx, &addr.0).await?;
    tx.commit().await?;
    let limit = i64::from(state.config.social.trading.history_limit);
    let incoming: Vec<TradeListRow> = sqlx::query_as(
        "SELECT o.trade_id,o.offered_card_id,o.requested_card_id,o.status,o.created_at,o.expires_at, \
         p.friend_code AS counterparty_player_id,p.display_name AS counterparty_display_name \
         FROM card_trade_offers o JOIN player_profiles p ON p.address=o.sender \
         WHERE o.recipient=$1 ORDER BY o.created_at DESC LIMIT $2",
    )
    .bind(&addr.0)
    .bind(limit)
    .fetch_all(state.db.pool())
    .await?;
    let outgoing: Vec<TradeListRow> = sqlx::query_as(
        "SELECT o.trade_id,o.offered_card_id,o.requested_card_id,o.status,o.created_at,o.expires_at, \
         p.friend_code AS counterparty_player_id,p.display_name AS counterparty_display_name \
         FROM card_trade_offers o JOIN player_profiles p ON p.address=o.recipient \
         WHERE o.sender=$1 ORDER BY o.created_at DESC LIMIT $2",
    )
    .bind(&addr.0)
    .bind(limit)
    .fetch_all(state.db.pool())
    .await?;
    Ok(Json(json!({
        "incoming":incoming.into_iter().map(|row|public_trade(row,&state.config,true)).collect::<Vec<_>>(),
        "outgoing":outgoing.into_iter().map(|row|public_trade(row,&state.config,false)).collect::<Vec<_>>(),
        "rules":{"minQuantity":state.config.social.trading.min_quantity_to_trade,"maxPending":state.config.social.trading.max_pending_per_player,"tradeableRarities":state.config.social.trading.tradeable_rarities}
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_reservations_always_keep_one_copy() {
        assert!(can_spend_duplicate(2, 0, 2));
        assert!(!can_spend_duplicate(2, 1, 2));
        assert!(can_spend_duplicate(4, 2, 2));
        assert!(!can_spend_duplicate(1, 0, 2));
    }
}
