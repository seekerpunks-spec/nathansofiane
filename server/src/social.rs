//! Boucle sociale R24 : Signal Jam, Ghost Vault, Firewalls et réparations.

use crate::auth::Addr;
use crate::config::{OutcomeType, RemoteConfig};
use crate::db::Db;
use crate::error::ApiError;
use crate::game;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::{DateTime, Duration, Utc};
use rand::seq::SliceRandom;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{FromRow, Postgres, Transaction};
use uuid::Uuid;

#[derive(Debug, FromRow)]
struct EncounterRow {
    encounter_id: String,
    attacker: String,
    target: Option<String>,
    kind: String,
    status: String,
    multiplier: i32,
    payload: Value,
    reward_credits: i64,
    expires_at: DateTime<Utc>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttackResolveReq {
    encounter_id: String,
    element_id: u32,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaidPickReq {
    encounter_id: String,
    node_index: u32,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaidCashoutReq {
    encounter_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepairReq {
    district_id: u32,
    element_id: u32,
    #[serde(default)]
    request_id: Option<String>,
}

fn short_target(target: Option<&str>) -> String {
    match target {
        Some(address) if address.len() > 12 => {
            format!("{}…{}", &address[..6], &address[address.len() - 4..])
        }
        Some(address) => address.to_string(),
        None => "NEON CORP".to_string(),
    }
}

fn public_encounter(row: &EncounterRow) -> Value {
    let picked = row
        .payload
        .get("picked")
        .and_then(Value::as_array)
        .map_or(0, Vec::len);
    let max_picks = row
        .payload
        .get("maxPicks")
        .and_then(Value::as_u64)
        .unwrap_or(0) as usize;
    json!({
        "encounterId": row.encounter_id,
        "kind": row.kind,
        "status": row.status,
        "multiplier": row.multiplier,
        "target": short_target(row.target.as_deref()),
        "corporate": row.target.is_none(),
        "districtId": row.payload.get("districtId").and_then(Value::as_i64),
        "choices": row.payload.get("choices").cloned().unwrap_or_else(|| json!([])),
        "nodeCount": row.payload.get("nodeCount").and_then(Value::as_u64),
        "picked": row.payload.get("picked").cloned().unwrap_or_else(|| json!([])),
        "picksUsed": picked,
        "picksRemaining": max_picks.saturating_sub(picked),
        "unbankedCredits": row.payload.get("unbankedCredits").and_then(Value::as_u64).unwrap_or(0),
        "canCashout": row.kind == "raid" && picked > 0 && row.status == "pending",
        "rewardCredits": row.reward_credits,
        "expiresAtMs": row.expires_at.timestamp_millis(),
    })
}

async fn expire_pending_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
) -> Result<(), ApiError> {
    sqlx::query(
        "UPDATE social_encounters SET status='expired',resolved_at=now() \
         WHERE attacker=$1 AND status='pending' AND expires_at<=now()",
    )
    .bind(address)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub async fn ensure_no_pending_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
) -> Result<(), ApiError> {
    expire_pending_tx(tx, address).await?;
    let pending: Option<String> = sqlx::query_scalar(
        "SELECT encounter_id FROM social_encounters WHERE attacker=$1 AND status='pending' LIMIT 1",
    )
    .bind(address)
    .fetch_optional(&mut **tx)
    .await?;
    if pending.is_some() {
        return Err(ApiError::Unavailable(
            "action sociale pending à terminer".to_string(),
        ));
    }
    Ok(())
}

async fn choose_target_tx(
    tx: &mut Transaction<'_, Postgres>,
    attacker: &str,
    district_index: i32,
    require_credits: Option<i64>,
) -> Result<Option<String>, ApiError> {
    let target = if let Some(minimum_credits) = require_credits {
        sqlx::query_scalar(
            "SELECT ps.address FROM player_state ps \
             WHERE ps.address<>$1 AND ps.credits>$2 \
             ORDER BY ABS(ps.district_index-$3),random() LIMIT 1",
        )
        .bind(attacker)
        .bind(minimum_credits)
        .bind(district_index)
        .fetch_optional(&mut **tx)
        .await?
    } else {
        sqlx::query_scalar(
            "SELECT ps.address FROM player_state ps \
             WHERE ps.address<>$1 AND EXISTS(SELECT 1 FROM district_progress dp \
                 WHERE dp.address=ps.address AND dp.level>0) \
             ORDER BY ABS(ps.district_index-$2),random() LIMIT 1",
        )
        .bind(attacker)
        .bind(district_index)
        .fetch_optional(&mut **tx)
        .await?
    };
    Ok(target)
}

pub async fn create_encounter_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    district_index: i32,
    outcome_type: OutcomeType,
    multiplier: u32,
    config: &RemoteConfig,
    forced_target: Option<&str>,
) -> Result<Option<Value>, ApiError> {
    let kind = match outcome_type {
        OutcomeType::Attack => "attack",
        OutcomeType::Raid => "raid",
        _ => return Ok(None),
    };
    if let Some(target) = forced_target {
        if target == address {
            return Err(ApiError::BadRequest(
                "cible debug identique à l'attaquant".to_string(),
            ));
        }
        let exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM player_state WHERE address=$1)")
                .bind(target)
                .fetch_one(&mut **tx)
                .await?;
        if !exists {
            return Err(ApiError::BadRequest("cible debug inconnue".to_string()));
        }
    }
    let encounter_id = Uuid::new_v4().to_string();
    let expires_at = Utc::now()
        + Duration::milliseconds(
            i64::try_from(config.social.encounter_ttl_ms)
                .map_err(|_| ApiError::Internal(anyhow!("encounter TTL overflow")))?,
        );
    let (target, payload) = if kind == "attack" {
        let mut target = if let Some(target) = forced_target {
            Some(target.to_string())
        } else {
            choose_target_tx(tx, address, district_index, None).await?
        };
        let choices: Vec<(i32, i32)> = if let Some(target_address) = target.as_deref() {
            sqlx::query_as(
                "SELECT dp.district_id,dp.element_id FROM district_progress dp \
                 LEFT JOIN district_damage dd ON dd.address=dp.address AND dd.district_id=dp.district_id AND dd.element_id=dp.element_id \
                 WHERE dp.address=$1 AND dp.level>0 AND dd.address IS NULL \
                 AND dp.district_id=(SELECT MAX(district_id) FROM district_progress WHERE address=$1 AND level>0) \
                 ORDER BY random() LIMIT 3",
            )
            .bind(target_address)
            .fetch_all(&mut **tx)
            .await?
        } else {
            vec![(1, 1), (1, 2), (1, 3)]
        };
        let choices = if choices.is_empty() {
            target = None;
            vec![(1, 1), (1, 2), (1, 3)]
        } else {
            choices
        };
        let district_id = choices.first().map_or(1, |choice| choice.0);
        (
            target,
            json!({
                "districtId": district_id,
                "choices": choices.into_iter().map(|(_,element_id)| element_id).collect::<Vec<_>>(),
            }),
        )
    } else {
        let protected = game::checked_u64_to_i64(
            config.social.raid.protected_credits,
            "raid.protectedCredits",
        )?;
        let target = if let Some(target) = forced_target {
            Some(target.to_string())
        } else {
            choose_target_tx(tx, address, district_index, Some(protected)).await?
        };
        let configured_pot = game::checked_scale(
            config.social.raid.base_pot_credits,
            multiplier,
            "raid.basePotCredits",
        )?;
        let pot = if let Some(target_address) = target.as_deref() {
            let credits: i64 =
                sqlx::query_scalar("SELECT credits FROM player_state WHERE address=$1")
                    .bind(target_address)
                    .fetch_one(&mut **tx)
                    .await?;
            let available = credits.saturating_sub(protected).max(0) as u64;
            let percentage = ((credits.max(0) as u128) * config.social.raid.max_steal_bps as u128
                / 10_000) as u64;
            configured_pot.min(available).min(percentage)
        } else {
            configured_pot
        };
        let mut indices: Vec<u32> = (0..config.social.raid.node_count).collect();
        indices.shuffle(&mut rand::rngs::OsRng);
        let trace_indices = &indices[..config.social.raid.trace_nodes as usize];
        let mut safe_shares = config.social.raid.safe_node_shares_bps.clone();
        safe_shares.shuffle(&mut rand::rngs::OsRng);
        let mut share_iter = safe_shares.iter();
        let board: Vec<Value> = (0..config.social.raid.node_count)
            .map(|index| {
                if trace_indices.contains(&index) {
                    json!({"kind":"trace","value":0})
                } else {
                    let share = *share_iter.next().unwrap_or(&0);
                    let value = ((pot as u128) * (share as u128) / 10_000) as u64;
                    json!({"kind":"cache","value":value})
                }
            })
            .collect();
        (
            target,
            json!({
                "nodeCount": config.social.raid.node_count,
                "maxPicks": config.social.raid.max_picks,
                "potCredits": pot,
                "board": board,
                "picked": [],
                "unbankedCredits": 0,
            }),
        )
    };
    sqlx::query(
        "INSERT INTO social_encounters(encounter_id,attacker,target,kind,multiplier,payload,expires_at) \
         VALUES($1,$2,$3,$4,$5,$6,$7)",
    )
    .bind(&encounter_id)
    .bind(address)
    .bind(&target)
    .bind(kind)
    .bind(multiplier as i32)
    .bind(&payload)
    .bind(expires_at)
    .execute(&mut **tx)
    .await?;
    let row = EncounterRow {
        encounter_id,
        attacker: address.to_string(),
        target,
        kind: kind.to_string(),
        status: "pending".to_string(),
        multiplier: multiplier as i32,
        payload,
        reward_credits: 0,
        expires_at,
    };
    Ok(Some(public_encounter(&row)))
}

pub async fn apply_shield_tx(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
    multiplier: u32,
    config: &RemoteConfig,
) -> Result<Value, ApiError> {
    let current: (i32, i64) = sqlx::query_as(
        "SELECT firewall_charges,credits FROM player_state WHERE address=$1 FOR UPDATE",
    )
    .bind(address)
    .fetch_one(&mut **tx)
    .await?;
    let maximum = config.social.firewall_max_charges as i32;
    let (charges, overflow) = shield_reward(
        current.0,
        maximum,
        multiplier,
        config.social.shield_overflow_credits,
    )?;
    let credits = game::checked_add_credits(current.1, overflow, "shield.credits")?;
    sqlx::query("UPDATE player_state SET firewall_charges=$1,credits=$2 WHERE address=$3")
        .bind(charges)
        .bind(credits)
        .bind(address)
        .execute(&mut **tx)
        .await?;
    Ok(json!({"firewallCharges":charges,"firewallMax":maximum,"overflowCredits":overflow}))
}

fn shield_reward(
    current: i32,
    maximum: i32,
    multiplier: u32,
    overflow_unit_credits: u64,
) -> Result<(i32, u64), ApiError> {
    let requested = i64::from(current)
        .checked_add(i64::from(multiplier))
        .ok_or_else(|| ApiError::Internal(anyhow!("shield charges overflow")))?;
    let charges = i32::try_from(requested.min(i64::from(maximum)))
        .map_err(|_| ApiError::Internal(anyhow!("shield charges hors i32")))?;
    let overflow_units = u32::try_from((requested - i64::from(maximum)).max(0))
        .map_err(|_| ApiError::Internal(anyhow!("shield overflow units hors u32")))?;
    let overflow = game::checked_scale(overflow_unit_credits, overflow_units, "shield.overflow")?;
    Ok((charges, overflow))
}

async fn load_encounter_locked(
    tx: &mut Transaction<'_, Postgres>,
    encounter_id: &str,
) -> Result<EncounterRow, ApiError> {
    sqlx::query_as(
        "SELECT encounter_id,attacker,target,kind,status,multiplier,payload,reward_credits,expires_at \
         FROM social_encounters WHERE encounter_id=$1 FOR UPDATE",
    )
    .bind(encounter_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(ApiError::NotFound)
}

async fn lock_players(
    tx: &mut Transaction<'_, Postgres>,
    attacker: &str,
    target: Option<&str>,
) -> Result<(), ApiError> {
    if let Some(target) = target {
        sqlx::query(
            "SELECT address FROM player_state WHERE address=$1 OR address=$2 ORDER BY address FOR UPDATE",
        )
        .bind(attacker)
        .bind(target)
        .fetch_all(&mut **tx)
        .await?;
    } else {
        sqlx::query("SELECT address FROM player_state WHERE address=$1 FOR UPDATE")
            .bind(attacker)
            .fetch_one(&mut **tx)
            .await?;
    }
    Ok(())
}

fn ensure_pending(row: &EncounterRow, attacker: &str, kind: &str) -> Result<(), ApiError> {
    if row.attacker != attacker || row.kind != kind {
        return Err(ApiError::NotFound);
    }
    if row.status != "pending" {
        return Err(ApiError::Unavailable("action déjà terminée".to_string()));
    }
    if row.expires_at <= Utc::now() {
        return Err(ApiError::Unavailable("action expirée".to_string()));
    }
    Ok(())
}

pub async fn resolve_attack(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<AttackResolveReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let action = format!("attack_resolve:{}", body.encounter_id);
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let row = load_encounter_locked(&mut tx, &body.encounter_id).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    ensure_pending(&row, &addr.0, "attack")?;
    let choices: Vec<u32> = serde_json::from_value(
        row.payload
            .get("choices")
            .cloned()
            .unwrap_or_else(|| json!([])),
    )
    .map_err(|_| ApiError::Internal(anyhow!("attack choices invalides")))?;
    if !choices.contains(&body.element_id) {
        return Err(ApiError::BadRequest("nœud non proposé".to_string()));
    }
    lock_players(&mut tx, &addr.0, row.target.as_deref()).await?;
    let mut blocked = false;
    if let Some(target) = row.target.as_deref() {
        let consumed = sqlx::query(
            "UPDATE player_state SET firewall_charges=firewall_charges-1 \
             WHERE address=$1 AND firewall_charges>0",
        )
        .bind(target)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        blocked = consumed == 1;
        if !blocked {
            let district_id = row
                .payload
                .get("districtId")
                .and_then(Value::as_i64)
                .unwrap_or(1) as i32;
            sqlx::query(
                "INSERT INTO district_damage(address,district_id,element_id,attacked_by) VALUES($1,$2,$3,$4) \
                 ON CONFLICT(address,district_id,element_id) DO UPDATE SET attacked_by=EXCLUDED.attacked_by,attacked_at=now()",
            )
            .bind(target)
            .bind(district_id)
            .bind(body.element_id as i32)
            .bind(&addr.0)
            .execute(&mut *tx)
            .await?;
        }
    }
    let base_reward = if blocked {
        state.config.social.attack.blocked_reward_credits
    } else {
        state.config.social.attack.base_reward_credits
    };
    let reward = game::checked_scale(base_reward, row.multiplier as u32, "attack.reward")?;
    let credits: i64 = sqlx::query_scalar("SELECT credits FROM player_state WHERE address=$1")
        .bind(&addr.0)
        .fetch_one(&mut *tx)
        .await?;
    let credits = game::checked_add_credits(credits, reward, "attack.credits")?;
    sqlx::query("UPDATE player_state SET credits=$1 WHERE address=$2")
        .bind(credits)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    let progress = game::progress_action_tx(
        &mut tx,
        &addr.0,
        "attack",
        row.multiplier as i64,
        &state.config,
    )
    .await?;
    let credits: i64 = sqlx::query_scalar("SELECT credits FROM player_state WHERE address=$1")
        .bind(&addr.0)
        .fetch_one(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE social_encounters SET status='resolved',reward_credits=$1,resolved_at=now(), \
         payload=payload || jsonb_build_object('elementId',$2::int,'blocked',$3::boolean) WHERE encounter_id=$4",
    )
    .bind(game::checked_u64_to_i64(reward, "attack.reward")?)
    .bind(body.element_id as i32)
    .bind(blocked)
    .bind(&row.encounter_id)
    .execute(&mut *tx)
    .await?;
    let response = json!({
        "encounterId":row.encounter_id,"kind":"attack","target":short_target(row.target.as_deref()),
        "corporate":row.target.is_none(),"elementId":body.element_id,"blocked":blocked,
        "rewardCredits":reward,"credits":credits,"progress":progress,"serverTimeMs":Utc::now().timestamp_millis()
    });
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "attack_resolve",
        &json!({}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

async fn cashout_locked(
    tx: &mut Transaction<'_, Postgres>,
    row: &EncounterRow,
    address: &str,
    config: &RemoteConfig,
) -> Result<(u64, i64, game::ProgressResult), ApiError> {
    lock_players(tx, address, row.target.as_deref()).await?;
    let unbanked = row
        .payload
        .get("unbankedCredits")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    if unbanked == 0 {
        return Err(ApiError::Unavailable("aucun butin à encaisser".to_string()));
    }
    let mut reward = unbanked;
    if let Some(target) = row.target.as_deref() {
        let target_credits: i64 =
            sqlx::query_scalar("SELECT credits FROM player_state WHERE address=$1")
                .bind(target)
                .fetch_one(&mut **tx)
                .await?;
        let protected = game::checked_u64_to_i64(
            config.social.raid.protected_credits,
            "raid.protectedCredits",
        )?;
        reward = reward.min(target_credits.saturating_sub(protected).max(0) as u64);
        sqlx::query("UPDATE player_state SET credits=credits-$1 WHERE address=$2")
            .bind(game::checked_u64_to_i64(reward, "raid.targetDebit")?)
            .bind(target)
            .execute(&mut **tx)
            .await?;
    }
    let attacker_credits: i64 =
        sqlx::query_scalar("SELECT credits FROM player_state WHERE address=$1")
            .bind(address)
            .fetch_one(&mut **tx)
            .await?;
    let credits = game::checked_add_credits(attacker_credits, reward, "raid.credits")?;
    sqlx::query("UPDATE player_state SET credits=$1 WHERE address=$2")
        .bind(credits)
        .bind(address)
        .execute(&mut **tx)
        .await?;
    let progress =
        game::progress_action_tx(tx, address, "raid", row.multiplier as i64, config).await?;
    let credits: i64 = sqlx::query_scalar("SELECT credits FROM player_state WHERE address=$1")
        .bind(address)
        .fetch_one(&mut **tx)
        .await?;
    sqlx::query(
        "UPDATE social_encounters SET status='cashed_out',reward_credits=$1,payload=$2,resolved_at=now() WHERE encounter_id=$3",
    )
    .bind(game::checked_u64_to_i64(reward, "raid.reward")?)
    .bind(&row.payload)
    .bind(&row.encounter_id)
    .execute(&mut **tx)
    .await?;
    Ok((reward, credits, progress))
}

pub async fn raid_pick(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<RaidPickReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let action = format!("raid_pick:{}", body.encounter_id);
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let mut row = load_encounter_locked(&mut tx, &body.encounter_id).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    ensure_pending(&row, &addr.0, "raid")?;
    let node_count = row
        .payload
        .get("nodeCount")
        .and_then(Value::as_u64)
        .unwrap_or(0) as u32;
    if body.node_index >= node_count {
        return Err(ApiError::BadRequest("nodeIndex hors limites".to_string()));
    }
    let mut picked: Vec<u32> = serde_json::from_value(
        row.payload
            .get("picked")
            .cloned()
            .unwrap_or_else(|| json!([])),
    )
    .map_err(|_| ApiError::Internal(anyhow!("raid picked invalide")))?;
    if picked.contains(&body.node_index) {
        return Err(ApiError::BadRequest("nœud déjà révélé".to_string()));
    }
    let board = row
        .payload
        .get("board")
        .and_then(Value::as_array)
        .ok_or_else(|| ApiError::Internal(anyhow!("raid board absent")))?;
    let node = board
        .get(body.node_index as usize)
        .ok_or_else(|| ApiError::Internal(anyhow!("raid node absent")))?;
    let kind = node.get("kind").and_then(Value::as_str).unwrap_or("trace");
    let value = node.get("value").and_then(Value::as_u64).unwrap_or(0);
    picked.push(body.node_index);
    if kind == "trace" {
        row.payload["picked"] = json!(picked);
        row.payload["unbankedCredits"] = json!(0);
        let progress = game::progress_action_tx(
            &mut tx,
            &addr.0,
            "raid",
            row.multiplier as i64,
            &state.config,
        )
        .await?;
        let (spins, credits): (i32, i64) =
            sqlx::query_as("SELECT spins,credits FROM player_state WHERE address=$1")
                .bind(&addr.0)
                .fetch_one(&mut *tx)
                .await?;
        sqlx::query(
            "UPDATE social_encounters SET status='failed',payload=$1,resolved_at=now() WHERE encounter_id=$2",
        )
        .bind(&row.payload)
        .bind(&row.encounter_id)
        .execute(&mut *tx)
        .await?;
        let response = json!({"encounterId":row.encounter_id,"kind":"raid","reveal":{"nodeIndex":body.node_index,"type":"trace","credits":0},"failed":true,"complete":true,"rewardCredits":0,"spins":spins,"credits":credits,"progress":progress,"serverTimeMs":Utc::now().timestamp_millis()});
        Db::audit_tx(
            &mut tx,
            &addr.0,
            "raid_failed",
            &json!({}),
            &response,
            Some(&rid),
        )
        .await?;
        state.db.store_idempotent(&mut tx, &key, &response).await?;
        tx.commit().await?;
        return Ok(Json(response));
    }
    let pot = row
        .payload
        .get("potCredits")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let current = row
        .payload
        .get("unbankedCredits")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let unbanked = current.saturating_add(value).min(pot);
    row.payload["picked"] = json!(picked);
    row.payload["unbankedCredits"] = json!(unbanked);
    let max_picks = row
        .payload
        .get("maxPicks")
        .and_then(Value::as_u64)
        .unwrap_or(1) as usize;
    if picked.len() >= max_picks {
        let (reward, credits, progress) =
            cashout_locked(&mut tx, &row, &addr.0, &state.config).await?;
        let response = json!({"encounterId":row.encounter_id,"kind":"raid","reveal":{"nodeIndex":body.node_index,"type":"cache","credits":value},"failed":false,"complete":true,"autoCashout":true,"rewardCredits":reward,"credits":credits,"progress":progress,"serverTimeMs":Utc::now().timestamp_millis()});
        Db::audit_tx(
            &mut tx,
            &addr.0,
            "raid_cashout",
            &json!({}),
            &response,
            Some(&rid),
        )
        .await?;
        state.db.store_idempotent(&mut tx, &key, &response).await?;
        tx.commit().await?;
        return Ok(Json(response));
    }
    sqlx::query("UPDATE social_encounters SET payload=$1 WHERE encounter_id=$2")
        .bind(&row.payload)
        .bind(&row.encounter_id)
        .execute(&mut *tx)
        .await?;
    let response = json!({"encounterId":row.encounter_id,"kind":"raid","reveal":{"nodeIndex":body.node_index,"type":"cache","credits":value},"failed":false,"complete":false,"unbankedCredits":unbanked,"picksRemaining":max_picks-picked.len(),"canCashout":true,"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn raid_cashout(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<RaidCashoutReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let action = format!("raid_cashout:{}", body.encounter_id);
    let key = game::idem_key(&action, &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let row = load_encounter_locked(&mut tx, &body.encounter_id).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    ensure_pending(&row, &addr.0, "raid")?;
    let (reward, credits, progress) = cashout_locked(&mut tx, &row, &addr.0, &state.config).await?;
    let response = json!({"encounterId":row.encounter_id,"kind":"raid","complete":true,"autoCashout":false,"rewardCredits":reward,"credits":credits,"progress":progress,"serverTimeMs":Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "raid_cashout",
        &json!({}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn repair(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<RepairReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("district_repair", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let district = state
        .config
        .districts
        .iter()
        .find(|district| district.id == body.district_id)
        .ok_or(ApiError::NotFound)?;
    let element = district
        .elements
        .iter()
        .find(|element| element.id == body.element_id)
        .ok_or(ApiError::NotFound)?;
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("player_state absent")))?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let damaged: Option<i32> = sqlx::query_scalar(
        "SELECT element_id FROM district_damage WHERE address=$1 AND district_id=$2 AND element_id=$3 FOR UPDATE",
    )
    .bind(&addr.0)
    .bind(body.district_id as i32)
    .bind(body.element_id as i32)
    .fetch_optional(&mut *tx)
    .await?;
    if damaged.is_none() {
        return Err(ApiError::Unavailable("nœud non endommagé".to_string()));
    }
    let level: i32 = sqlx::query_scalar(
        "SELECT level FROM district_progress WHERE address=$1 AND district_id=$2 AND element_id=$3",
    )
    .bind(&addr.0)
    .bind(body.district_id as i32)
    .bind(body.element_id as i32)
    .fetch_one(&mut *tx)
    .await?;
    let level_cost = element
        .levels
        .iter()
        .find(|entry| entry.level == level as u32)
        .map_or(0, |entry| entry.cost);
    let cost =
        ((level_cost as u128) * state.config.social.attack.repair_cost_bps as u128 / 10_000) as u64;
    let cost_i64 = game::checked_u64_to_i64(cost, "repair.cost")?;
    if player.credits < cost_i64 {
        return Err(ApiError::InsufficientCredits);
    }
    let credits = player.credits - cost_i64;
    sqlx::query("UPDATE player_state SET credits=$1 WHERE address=$2")
        .bind(credits)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "DELETE FROM district_damage WHERE address=$1 AND district_id=$2 AND element_id=$3",
    )
    .bind(&addr.0)
    .bind(body.district_id as i32)
    .bind(body.element_id as i32)
    .execute(&mut *tx)
    .await?;
    let response = json!({"districtId":body.district_id,"elementId":body.element_id,"cost":cost,"credits":credits,"repaired":true,"serverTimeMs":Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "district_repair",
        &json!({"credits":player.credits}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn pending_for(db: &Db, address: &str) -> Result<Option<Value>, ApiError> {
    let row: Option<EncounterRow> = sqlx::query_as(
        "SELECT encounter_id,attacker,target,kind,status,multiplier,payload,reward_credits,expires_at \
         FROM social_encounters WHERE attacker=$1 AND status='pending' AND expires_at>now() LIMIT 1",
    )
    .bind(address)
    .fetch_optional(db.pool())
    .await?;
    Ok(row.as_ref().map(public_encounter))
}

pub async fn damage_for(db: &Db, address: &str) -> Result<Vec<Value>, ApiError> {
    let rows: Vec<(i32, i32, Option<String>, DateTime<Utc>)> = sqlx::query_as(
        "SELECT district_id,element_id,attacked_by,attacked_at FROM district_damage WHERE address=$1 ORDER BY district_id,element_id",
    )
    .bind(address)
    .fetch_all(db.pool())
    .await?;
    Ok(rows
        .into_iter()
        .map(|(district_id, element_id, attacked_by, attacked_at)| {
            json!({"districtId":district_id,"elementId":element_id,"attacker":short_target(attacked_by.as_deref()),"attackedAtMs":attacked_at.timestamp_millis()})
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_raid_never_leaks_hidden_board() {
        let row = EncounterRow {
            encounter_id: "encounter".to_string(),
            attacker: "attacker".to_string(),
            target: Some("target-player-1234".to_string()),
            kind: "raid".to_string(),
            status: "pending".to_string(),
            multiplier: 4,
            payload: json!({
                "nodeCount": 6,
                "maxPicks": 3,
                "picked": [2],
                "unbankedCredits": 100,
                "board": [{"kind":"trace","value":0}],
            }),
            reward_credits: 0,
            expires_at: Utc::now() + Duration::minutes(1),
        };
        let public = public_encounter(&row);
        assert!(public.get("board").is_none());
        assert_eq!(public["picksRemaining"], 2);
        assert_eq!(public["canCashout"], true);
    }

    #[test]
    fn multiplied_shields_fill_then_convert_every_surplus_charge() {
        assert_eq!(shield_reward(1, 3, 4, 75_000).unwrap(), (3, 150_000));
        assert_eq!(shield_reward(3, 3, 4, 75_000).unwrap(), (3, 300_000));
        assert_eq!(shield_reward(0, 3, 2, 75_000).unwrap(), (2, 0));
    }
}
