//! Export et effacement des données joueur.
//!
//! L'export couvre le snapshot de jeu et les historiques directement liés à
//! l'adresse. L'effacement transfère proprement une crew possédée, supprime les
//! archives sans FK, puis s'appuie sur les cascades relationnelles.

use crate::auth::Addr;
use crate::error::ApiError;
use crate::game;
use crate::state::AppState;
use axum::extract::{Extension, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::postgres::PgPool;
use sqlx::{Postgres, Transaction};

const DELETE_CONFIRMATION: &str = "DELETE CYBERSEEKER ACCOUNT";

fn address_hash(address: &str) -> String {
    Sha256::digest(address.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

async fn json_rows(
    pool: &PgPool,
    sql: &'static str,
    address: &str,
) -> Result<Vec<Value>, ApiError> {
    Ok(sqlx::query_scalar(sql)
        .bind(address)
        .fetch_all(pool)
        .await?)
}

pub async fn deletion_was_recorded(
    pool: &PgPool,
    address: &str,
    request_id: &str,
) -> Result<bool, ApiError> {
    Ok(sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM account_deletion_tombstones WHERE address_hash=$1 AND request_id=$2)")
        .bind(address_hash(address)).bind(request_id).fetch_one(pool).await?)
}

/// `GET /account/export` — copie portable des données liées au wallet.
pub async fn export(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
) -> Result<Json<Value>, ApiError> {
    let snapshot = crate::get_state(State(state.clone()), Extension(addr.clone())).await?;
    let purchases = json_rows(
        state.db.pool(),
        "SELECT to_jsonb(row) FROM (SELECT offer_id,tx_signature,token_mint,amount_u64,status,created_at FROM purchases WHERE address=$1 ORDER BY created_at) row",
        &addr.0,
    )
    .await?;
    let economy_audit = json_rows(
        state.db.pool(),
        "SELECT to_jsonb(row) FROM (SELECT action,before,after,request_id,ts FROM economy_audit WHERE address=$1 ORDER BY ts) row",
        &addr.0,
    )
    .await?;
    let analytics = json_rows(
        state.db.pool(),
        "SELECT to_jsonb(row) FROM (SELECT name,props,ts FROM analytics_events WHERE address=$1 ORDER BY ts) row",
        &addr.0,
    )
    .await?;
    let friendships = json_rows(
        state.db.pool(),
        "SELECT jsonb_build_object('playerId',p.friend_code,'createdAt',f.created_at) FROM friendships f JOIN player_profiles p ON p.address=CASE WHEN f.address_a=$1 THEN f.address_b ELSE f.address_a END WHERE f.address_a=$1 OR f.address_b=$1 ORDER BY f.created_at",
        &addr.0,
    )
    .await?;
    let trades = json_rows(
        state.db.pool(),
        "SELECT to_jsonb(row) FROM (SELECT t.trade_id,s.friend_code AS sender_player_id,r.friend_code AS recipient_player_id,t.offered_card_id,t.requested_card_id,t.status,t.created_at,t.expires_at,t.resolved_at FROM card_trade_offers t JOIN player_profiles s ON s.address=t.sender JOIN player_profiles r ON r.address=t.recipient WHERE t.sender=$1 OR t.recipient=$1 ORDER BY t.created_at) row",
        &addr.0,
    )
    .await?;
    let liveops_archive = json_rows(
        state.db.pool(),
        "SELECT jsonb_build_object('kind',kind,'data',data) FROM (SELECT 'event_score'::text AS kind,to_jsonb(e) AS data FROM event_scores_archive e WHERE address=$1 UNION ALL SELECT 'team_contribution',to_jsonb(c) FROM team_event_contributions_archive c WHERE address=$1 UNION ALL SELECT 'event_milestone',to_jsonb(m) FROM event_milestone_claims_archive m WHERE address=$1 UNION ALL SELECT 'team_event_claim',to_jsonb(t) FROM team_event_claims_archive t WHERE address=$1) exported",
        &addr.0,
    )
    .await?;
    let social_support = json_rows(
        state.db.pool(),
        "SELECT jsonb_build_object('kind',kind,'data',data) FROM (SELECT 'friend_gift'::text AS kind,(to_jsonb(g)-'sender'-'recipient') || jsonb_build_object('senderPlayerId',s.friend_code,'recipientPlayerId',r.friend_code) AS data FROM friend_gifts g JOIN player_profiles s ON s.address=g.sender JOIN player_profiles r ON r.address=g.recipient WHERE g.sender=$1 OR g.recipient=$1 UNION ALL SELECT 'team_message',to_jsonb(m) FROM team_quick_messages m WHERE address=$1 UNION ALL SELECT 'team_help_request',to_jsonb(h) FROM team_help_requests h WHERE requester=$1 UNION ALL SELECT 'team_help_donation',to_jsonb(d) FROM team_help_donations d WHERE donor=$1) exported",
        &addr.0,
    )
    .await?;

    let encounters = json_rows(state.db.pool(),
        "SELECT to_jsonb(row) FROM (SELECT e.encounter_id,a.friend_code AS attacker_player_id,t.friend_code AS target_player_id,e.kind,e.status,e.multiplier,e.reward_credits,e.created_at,e.expires_at,e.resolved_at FROM social_encounters e JOIN player_profiles a ON a.address=e.attacker LEFT JOIN player_profiles t ON t.address=e.target WHERE e.attacker=$1 OR e.target=$1 ORDER BY e.created_at) row",
        &addr.0).await?;
    Ok(Json(json!({
        "formatVersion": 1,
        "generatedAtMs": Utc::now().timestamp_millis(),
        "gameState": snapshot.0,
        "purchases": purchases,
        "economyAudit": economy_audit,
        "analyticsEvents": analytics,
        "friendships": friendships,
        "trades": trades,
        "liveOpsArchive": liveops_archive,
        "socialSupport": social_support,
        "encounters": encounters,
    })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteRequest {
    confirmation: String,
    request_id: Option<String>,
}

async fn transfer_or_delete_owned_team(
    tx: &mut Transaction<'_, Postgres>,
    address: &str,
) -> Result<(), ApiError> {
    let owned_team: Option<String> =
        sqlx::query_scalar("SELECT team_id FROM teams WHERE owner_address=$1 FOR UPDATE")
            .bind(address)
            .fetch_optional(&mut **tx)
            .await?;
    let Some(team_id) = owned_team else {
        return Ok(());
    };
    let successor: Option<String> = sqlx::query_scalar(
        "SELECT address FROM team_members WHERE team_id=$1 AND address<>$2 ORDER BY joined_at,address LIMIT 1 FOR UPDATE",
    )
    .bind(&team_id)
    .bind(address)
    .fetch_optional(&mut **tx)
    .await?;
    if let Some(successor) = successor {
        sqlx::query("UPDATE team_members SET role='member' WHERE team_id=$1 AND address=$2")
            .bind(&team_id)
            .bind(address)
            .execute(&mut **tx)
            .await?;
        sqlx::query("UPDATE team_members SET role='owner' WHERE team_id=$1 AND address=$2")
            .bind(&team_id)
            .bind(&successor)
            .execute(&mut **tx)
            .await?;
        sqlx::query("UPDATE teams SET owner_address=$1 WHERE team_id=$2")
            .bind(&successor)
            .bind(&team_id)
            .execute(&mut **tx)
            .await?;
    } else {
        sqlx::query("DELETE FROM teams WHERE team_id=$1")
            .bind(&team_id)
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

/// Effacement transactionnel réutilisé par le handler et les tests DB.
pub async fn delete_account_data(
    pool: &PgPool,
    address: &str,
    request_id: &str,
    session_hash: Option<&str>,
) -> Result<bool, ApiError> {
    let hash = address_hash(address);
    let mut tx = pool.begin().await?;
    // Sérialise suppression/recréation sans verrouiller les comptes voisins.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,4))")
        .bind(address)
        .execute(&mut *tx)
        .await?;
    let replayed: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM account_deletion_tombstones WHERE address_hash=$1 AND request_id=$2)",
    )
    .bind(&hash)
    .bind(request_id)
    .fetch_one(&mut *tx)
    .await?;
    if replayed {
        tx.rollback().await?;
        return Ok(false);
    }
    if let Some(session_hash) = session_hash {
        let valid: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM refresh_sessions WHERE address=$1 AND jti_hash=$2 AND expires_at>=now())")
            .bind(address).bind(session_hash).fetch_one(&mut *tx).await?;
        if !valid {
            return Err(ApiError::Unauthorized(
                crate::error::AuthError::InvalidToken,
            ));
        }
    }
    // Ordre compatible avec les mutations de profil, d'économie et de crew.
    sqlx::query("SELECT address FROM player_profiles WHERE address=$1 FOR UPDATE")
        .bind(address)
        .fetch_optional(&mut *tx)
        .await?;
    let player: Option<String> =
        sqlx::query_scalar("SELECT address FROM player_state WHERE address=$1 FOR UPDATE")
            .bind(address)
            .fetch_optional(&mut *tx)
            .await?;
    if player.is_none() {
        tx.rollback().await?;
        return Ok(false);
    }

    transfer_or_delete_owned_team(&mut tx, address).await?;
    for statement in [
        "DELETE FROM event_scores_archive WHERE address=$1",
        "DELETE FROM team_event_contributions_archive WHERE address=$1",
        "DELETE FROM event_milestone_claims_archive WHERE address=$1",
        "DELETE FROM team_event_claims_archive WHERE address=$1",
    ] {
        sqlx::query(statement)
            .bind(address)
            .execute(&mut *tx)
            .await?;
    }
    sqlx::query("DELETE FROM auth_nonces WHERE address=$1")
        .bind(address)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM api_rate_limits WHERE client_key=$1")
        .bind(format!("wallet:{address}"))
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM idempotency WHERE split_part(key,'|',2)=$1")
        .bind(address)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM players WHERE address=$1")
        .bind(address)
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO account_deletion_tombstones(address_hash,request_id) VALUES($1,$2)")
        .bind(hash)
        .bind(request_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(true)
}

/// `POST /account/delete` — confirmation explicite et retry sûr.
pub async fn delete(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<DeleteRequest>,
) -> Result<Json<Value>, ApiError> {
    if body.confirmation.trim() != DELETE_CONFIRMATION {
        return Err(ApiError::BadRequest(format!(
            "confirmation requise: {DELETE_CONFIRMATION}"
        )));
    }
    let request_id = game::request_id(&headers, body.request_id.as_deref())?;
    let (_, session_hash) = crate::auth::auth_session(&state, &headers)?;
    let deleted =
        delete_account_data(state.db.pool(), &addr.0, &request_id, Some(&session_hash)).await?;
    Ok(Json(json!({
        "deleted": true,
        "replayed": !deleted,
        "serverTimeMs": Utc::now().timestamp_millis(),
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn postgres_account_delete_scrubs_archives_and_transfers_team() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_account_delete_scrubs_archives_and_transfers_team")
                .await
        else {
            return Ok(());
        };
        let owner = format!("qa-delete-owner-{}", uuid::Uuid::new_v4());
        let successor = format!("qa-delete-member-{}", uuid::Uuid::new_v4());
        db.ensure_player(&owner, 1).await?;
        db.ensure_player(&successor, 1).await?;
        let team_id = format!("qa-team-{}", uuid::Uuid::new_v4());
        let team_code = format!("QD{}", &uuid::Uuid::new_v4().simple().to_string()[..12]);
        let team_name = format!("Delete-{}", &uuid::Uuid::new_v4().simple().to_string()[..8]);
        sqlx::query("INSERT INTO teams(team_id,team_code,name,owner_address) VALUES($1,$2,$3,$4)")
            .bind(&team_id)
            .bind(team_code)
            .bind(team_name)
            .bind(&owner)
            .execute(db.pool())
            .await?;
        sqlx::query(
            "INSERT INTO team_members(team_id,address,role) VALUES($1,$2,'owner'),($1,$3,'member')",
        )
        .bind(&team_id)
        .bind(&owner)
        .bind(&successor)
        .execute(db.pool())
        .await?;
        sqlx::query("INSERT INTO event_scores_archive(event_key,address,points,cohort_id,reward_claimed) VALUES('qa-delete-event',$1,10,1,false)")
            .bind(&owner)
            .execute(db.pool())
            .await?;

        assert!(delete_account_data(db.pool(), &owner, "delete-once", None).await?);
        assert!(!delete_account_data(db.pool(), &owner, "delete-once", None).await?);
        let owner_exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM players WHERE address=$1)")
                .bind(&owner)
                .fetch_one(db.pool())
                .await?;
        assert!(!owner_exists);
        let new_owner: String =
            sqlx::query_scalar("SELECT owner_address FROM teams WHERE team_id=$1")
                .bind(&team_id)
                .fetch_one(db.pool())
                .await?;
        assert_eq!(new_owner, successor);
        let archived: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM event_scores_archive WHERE address=$1")
                .bind(&owner)
                .fetch_one(db.pool())
                .await?;
        assert_eq!(archived, 0);
        Ok(())
    }
}
