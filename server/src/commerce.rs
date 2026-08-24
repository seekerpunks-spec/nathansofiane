//! Continuité de session, publicité récompensée et vérification d'offres.
//!
//! Les reçus `dev:*` ne sont acceptés que lorsque DEV_AUTH est actif. En
//! production, l'endpoint refuse tout crédit tant qu'un provider de preuve
//! publicitaire/paiement n'est pas raccordé : jamais de confiance au client.

use crate::auth::Addr;
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdReq {
    receipt: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PurchaseReq {
    offer_id: String,
    tx_signature: String,
    token_mint: String,
    amount_u64: u64,
    #[serde(default)]
    request_id: Option<String>,
}

pub async fn reward_ad(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<AdReq>,
) -> Result<Json<Value>, ApiError> {
    if !state.dev_auth || !body.receipt.starts_with("dev:") {
        return Err(ApiError::Unavailable(
            "provider publicitaire non configuré".to_string(),
        ));
    }
    if body.receipt.len() > 160 {
        return Err(ApiError::BadRequest("receipt trop long".to_string()));
    }
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("ad_reward", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let cfg = &state.config.economy.ads_config;
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    let today = Utc::now().date_naive();
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM ad_reward_claims WHERE address=$1 AND reward_day=$2",
    )
    .bind(&addr.0)
    .bind(today)
    .fetch_one(&mut *tx)
    .await?;
    if count >= cfg.max_rewarded_ads_per_day as i64 {
        tx.rollback().await?;
        return Err(ApiError::Unavailable(
            "limite quotidienne atteinte".to_string(),
        ));
    }
    let last_ms: Option<i64> = sqlx::query_scalar("SELECT (EXTRACT(EPOCH FROM MAX(claimed_at))*1000)::BIGINT FROM ad_reward_claims WHERE address=$1")
        .bind(&addr.0).fetch_one(&mut *tx).await?;
    if let Some(last) = last_ms {
        if Utc::now().timestamp_millis() - last < cfg.cooldown_ms as i64 {
            tx.rollback().await?;
            return Err(ApiError::Unavailable("publicité en cooldown".to_string()));
        }
    }
    let inserted = sqlx::query("INSERT INTO ad_reward_claims(receipt,address,reward_day) VALUES($1,$2,$3) ON CONFLICT DO NOTHING")
        .bind(&body.receipt).bind(&addr.0).bind(today).execute(&mut *tx).await?.rows_affected();
    if inserted == 0 {
        tx.rollback().await?;
        return Err(ApiError::AlreadyClaimed);
    }
    let spins = player.spins + cfg.reward_per_ad as i32;
    sqlx::query("UPDATE player_state SET spins=$1,ads_watched_today=$2,ads_claimed_date=$3 WHERE address=$4")
        .bind(spins).bind((count + 1) as i32).bind(today).bind(&addr.0).execute(&mut *tx).await?;
    let response = json!({"rewardSpins": cfg.reward_per_ad, "spins": spins, "adsWatchedToday": count+1, "adsRemaining": cfg.max_rewarded_ads_per_day as i64-count-1, "serverTimeMs": Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "ad_reward",
        &json!({"spins":player.spins}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn verify_purchase(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<PurchaseReq>,
) -> Result<Json<Value>, ApiError> {
    if !state.dev_auth || !body.tx_signature.starts_with("dev:") {
        return Err(ApiError::Unavailable(
            "vérificateur Solana/SKR non configuré".to_string(),
        ));
    }
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("purchase_verify", &addr.0, &rid);
    if let Some(v) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(v));
    }
    let offer = state
        .config
        .offers
        .iter()
        .find(|o| o.offer_id == body.offer_id)
        .ok_or(ApiError::NotFound)?;
    let now_ms = Utc::now().timestamp_millis();
    if now_ms < offer.starts_at_ms || now_ms >= offer.ends_at_ms {
        return Err(ApiError::Unavailable("offre expirée".to_string()));
    }
    if body.token_mint != offer.price_token || body.amount_u64 != offer.price_u64 {
        return Err(ApiError::BadRequest(
            "preuve de paiement non conforme".to_string(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM player_offer_claims WHERE address=$1 AND offer_id=$2",
    )
    .bind(&addr.0)
    .bind(&offer.offer_id)
    .fetch_one(&mut *tx)
    .await?;
    if count >= offer.max_per_player as i64 {
        tx.rollback().await?;
        return Err(ApiError::Unavailable(
            "limite de l'offre atteinte".to_string(),
        ));
    }
    let purchase_id: i64 = sqlx::query_scalar(
        "INSERT INTO purchases(address,offer_id,tx_signature,token_mint,amount_u64,status) VALUES($1,$2,$3,$4,$5,'credited') RETURNING id",
    ).bind(&addr.0).bind(&offer.offer_id).bind(&body.tx_signature).bind(&body.token_mint).bind(body.amount_u64 as i64)
     .fetch_one(&mut *tx).await.map_err(|e| if matches!(&e, sqlx::Error::Database(db) if db.is_unique_violation()) { ApiError::AlreadyClaimed } else { ApiError::Db(e) })?;
    let mut spins_add = 0i32;
    let mut credits_add = 0i64;
    for content in &offer.contents {
        match content.content_type.as_str() {
            "spins" => spins_add += content.amount as i32,
            "credits" => credits_add += content.amount as i64,
            "chest" => {
                let chest = content
                    .id
                    .as_deref()
                    .ok_or_else(|| ApiError::Internal(anyhow!("offre chest sans id")))?;
                sqlx::query("INSERT INTO player_chests(address,chest_id,qty) VALUES($1,$2,$3) ON CONFLICT(address,chest_id) DO UPDATE SET qty=player_chests.qty+EXCLUDED.qty")
                    .bind(&addr.0).bind(chest).bind(content.amount as i32).execute(&mut *tx).await?;
            }
            "season_premium" => {
                let season = content
                    .id
                    .as_deref()
                    .ok_or_else(|| ApiError::Internal(anyhow!("premium sans saison")))?;
                sqlx::query("INSERT INTO season_progress(address,season_id,premium) VALUES($1,$2,true) ON CONFLICT(address,season_id) DO UPDATE SET premium=true")
                    .bind(&addr.0).bind(season).execute(&mut *tx).await?;
            }
            _ => return Err(ApiError::Internal(anyhow!("contenu d'offre inconnu"))),
        }
    }
    sqlx::query("UPDATE player_state SET spins=spins+$1,credits=credits+$2 WHERE address=$3")
        .bind(spins_add)
        .bind(credits_add)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO player_offer_claims(address,offer_id,purchase_id) VALUES($1,$2,$3)")
        .bind(&addr.0)
        .bind(&offer.offer_id)
        .bind(purchase_id)
        .execute(&mut *tx)
        .await?;
    let response = json!({"offerId":offer.offer_id,"purchaseId":purchase_id,"contents":offer.contents,"spins":player.spins+spins_add,"credits":player.credits+credits_add,"serverTimeMs":now_ms});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "purchase_credit",
        &json!({"spins":player.spins,"credits":player.credits}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}
