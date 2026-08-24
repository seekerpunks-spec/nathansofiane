//! Profils, invitations, amis et sélection d'une cible sociale.

use crate::auth::Addr;
use crate::error::ApiError;
use crate::game;
use crate::progression;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, Query, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{Postgres, Transaction};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateProfileReq {
    display_name: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendActionReq {
    friend_code: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
pub struct SearchQuery {
    q: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TargetPreferenceReq {
    friend_code: String,
    source: String,
    #[serde(default)]
    request_id: Option<String>,
}

fn valid_display_name(raw: &str) -> Option<String> {
    let name = raw.trim();
    let count = name.chars().count();
    if !(3..=24).contains(&count)
        || !name
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, ' ' | '_' | '-' | '.'))
    {
        return None;
    }
    Some(name.to_string())
}

pub(crate) async fn address_from_code_tx(
    tx: &mut Transaction<'_, Postgres>,
    friend_code: &str,
) -> Result<String, ApiError> {
    sqlx::query_scalar("SELECT address FROM player_profiles WHERE upper(friend_code)=upper($1)")
        .bind(friend_code.trim())
        .fetch_optional(&mut **tx)
        .await?
        .ok_or(ApiError::NotFound)
}

pub(crate) async fn lock_profiles_tx(
    tx: &mut Transaction<'_, Postgres>,
    first: &str,
    second: &str,
) -> Result<(), ApiError> {
    let rows: Vec<String> = sqlx::query_scalar(
        "SELECT address FROM player_profiles WHERE address=$1 OR address=$2 ORDER BY address FOR UPDATE",
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

pub(crate) async fn are_friends_tx(
    tx: &mut Transaction<'_, Postgres>,
    first: &str,
    second: &str,
) -> Result<bool, ApiError> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM friendships WHERE address_a=LEAST($1,$2) AND address_b=GREATEST($1,$2))",
    )
    .bind(first)
    .bind(second)
    .fetch_one(&mut **tx)
    .await?)
}

async fn public_profile_pool(state: &AppState, address: &str) -> Result<Value, ApiError> {
    let row: (String, String, String, i64, i32, i64, i64) = sqlx::query_as(
        "SELECT p.friend_code,p.display_name,p.avatar_id,COALESCE(ps.score,0),s.district_index, \
         (SELECT COUNT(*)::bigint FROM player_cards c WHERE c.address=p.address AND c.qty>0), \
         (SELECT COUNT(*)::bigint FROM set_completion sc WHERE sc.address=p.address AND sc.claimed=true) \
         FROM player_profiles p JOIN player_state s ON s.address=p.address \
         LEFT JOIN progression_scores ps ON ps.address=p.address WHERE p.address=$1",
    )
    .bind(address)
    .fetch_optional(state.db.pool())
    .await?
    .ok_or(ApiError::NotFound)?;
    Ok(
        json!({"playerId":row.0,"displayName":row.1,"avatarId":row.2,"score":row.3,"districtIndex":row.4,"uniqueCards":row.5,"completedSets":row.6}),
    )
}

pub async fn profile_for_state(state: &AppState, address: &str) -> Result<Value, ApiError> {
    public_profile_pool(state, address).await
}

pub async fn own_profile(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
) -> Result<Json<Value>, ApiError> {
    let score = progression::refresh_score(&state, &addr.0).await?;
    let mut profile = public_profile_pool(&state, &addr.0).await?;
    profile["progression"] = progression::score_json(score, &state.config);
    Ok(Json(profile))
}

pub async fn update_profile(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<UpdateProfileReq>,
) -> Result<Json<Value>, ApiError> {
    let name = valid_display_name(&body.display_name).ok_or_else(|| {
        ApiError::BadRequest("displayName doit contenir 3 à 24 caractères".to_string())
    })?;
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("profile_update", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT address FROM player_profiles WHERE address=$1 FOR UPDATE")
        .bind(&addr.0)
        .fetch_one(&mut *tx)
        .await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let (friend_code, avatar_id): (String, String) = sqlx::query_as(
        "UPDATE player_profiles SET display_name=$1,updated_at=now() WHERE address=$2 RETURNING friend_code,avatar_id",
    )
    .bind(&name)
    .bind(&addr.0)
    .fetch_one(&mut *tx)
    .await?;
    let response = json!({"playerId":friend_code,"displayName":name,"avatarId":avatar_id,"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn search(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Query(query): Query<SearchQuery>,
) -> Result<Json<Value>, ApiError> {
    let q = query.q.trim();
    if q.chars().count() < 2 || q.chars().count() > 24 || q.chars().any(char::is_control) {
        return Err(ApiError::BadRequest(
            "recherche entre 2 et 24 caractères".to_string(),
        ));
    }
    let rows: Vec<(String, String, String, i64, i32, String)> = sqlx::query_as(
        "SELECT p.friend_code,p.display_name,p.avatar_id,COALESCE(ps.score,0),s.district_index, \
         CASE WHEN f.address_a IS NOT NULL THEN 'friend' \
              WHEN incoming.requester IS NOT NULL THEN 'incoming' \
              WHEN outgoing.requester IS NOT NULL THEN 'outgoing' ELSE 'none' END AS relationship \
         FROM player_profiles p JOIN player_state s ON s.address=p.address \
         LEFT JOIN progression_scores ps ON ps.address=p.address \
         LEFT JOIN friendships f ON f.address_a=LEAST($1,p.address) AND f.address_b=GREATEST($1,p.address) \
         LEFT JOIN friend_requests incoming ON incoming.requester=p.address AND incoming.addressee=$1 \
         LEFT JOIN friend_requests outgoing ON outgoing.requester=$1 AND outgoing.addressee=p.address \
         WHERE p.address<>$1 AND (upper(p.friend_code)=upper($2) OR p.display_name ILIKE '%' || $2 || '%') \
         ORDER BY (upper(p.friend_code)=upper($2)) DESC,COALESCE(ps.score,0) DESC,p.friend_code LIMIT 20",
    )
    .bind(&addr.0)
    .bind(q)
    .fetch_all(state.db.pool())
    .await?;
    Ok(Json(
        json!({"results":rows.into_iter().map(|row|json!({"playerId":row.0,"displayName":row.1,"avatarId":row.2,"score":row.3,"districtIndex":row.4,"relationship":row.5})).collect::<Vec<_>>()}),
    ))
}

pub async fn list(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
) -> Result<Json<Value>, ApiError> {
    let friends: Vec<(String, String, String, i64, i32)> = sqlx::query_as(
        "SELECT p.friend_code,p.display_name,p.avatar_id,COALESCE(ps.score,0),s.district_index FROM ( \
         SELECT CASE WHEN address_a=$1 THEN address_b ELSE address_a END AS other FROM friendships WHERE address_a=$1 OR address_b=$1 \
         ) x JOIN player_profiles p ON p.address=x.other JOIN player_state s ON s.address=p.address \
         LEFT JOIN progression_scores ps ON ps.address=p.address ORDER BY ps.score DESC,p.friend_code",
    )
    .bind(&addr.0)
    .fetch_all(state.db.pool())
    .await?;
    let incoming: Vec<(String, String, String, i64)> = sqlx::query_as(
        "SELECT p.friend_code,p.display_name,p.avatar_id,COALESCE(ps.score,0) FROM friend_requests r \
         JOIN player_profiles p ON p.address=r.requester LEFT JOIN progression_scores ps ON ps.address=p.address \
         WHERE r.addressee=$1 ORDER BY r.created_at DESC",
    )
    .bind(&addr.0)
    .fetch_all(state.db.pool())
    .await?;
    let outgoing: Vec<(String, String)> = sqlx::query_as(
        "SELECT p.friend_code,p.display_name FROM friend_requests r JOIN player_profiles p ON p.address=r.addressee \
         WHERE r.requester=$1 ORDER BY r.created_at DESC",
    )
    .bind(&addr.0)
    .fetch_all(state.db.pool())
    .await?;
    let attacks: Vec<(String, String, bool, chrono::DateTime<Utc>)> = sqlx::query_as(
        "SELECT p.friend_code,p.display_name,COALESCE((e.payload->>'blocked')::boolean,false),e.created_at \
         FROM social_encounters e JOIN player_profiles p ON p.address=e.attacker \
         WHERE e.target=$1 AND e.kind='attack' AND e.status='resolved' ORDER BY e.created_at DESC LIMIT 20",
    )
    .bind(&addr.0)
    .fetch_all(state.db.pool())
    .await?;
    let revenge_cutoff = Utc::now()
        - chrono::Duration::milliseconds(
            i64::try_from(state.config.social.revenge_window_ms)
                .map_err(|_| ApiError::Internal(anyhow!("revengeWindowMs overflow")))?,
        );
    let preference: Option<(String, String, String, chrono::DateTime<Utc>)> = sqlx::query_as(
        "SELECT p.friend_code,p.display_name,t.source,t.expires_at FROM social_target_preferences t \
         JOIN player_profiles p ON p.address=t.target WHERE t.attacker=$1 AND t.expires_at>now()",
    )
    .bind(&addr.0)
    .fetch_optional(state.db.pool())
    .await?;
    Ok(Json(json!({
        "friends":friends.into_iter().map(|r|json!({"playerId":r.0,"displayName":r.1,"avatarId":r.2,"score":r.3,"districtIndex":r.4})).collect::<Vec<_>>(),
        "incoming":incoming.into_iter().map(|r|json!({"playerId":r.0,"displayName":r.1,"avatarId":r.2,"score":r.3})).collect::<Vec<_>>(),
        "outgoing":outgoing.into_iter().map(|r|json!({"playerId":r.0,"displayName":r.1})).collect::<Vec<_>>(),
        "recentAttacks":attacks.into_iter().map(|r|json!({"playerId":r.0,"displayName":r.1,"blocked":r.2,"attackedAtMs":r.3.timestamp_millis(),"canRevenge":r.3>revenge_cutoff})).collect::<Vec<_>>(),
        "targetPreference":preference.map(|r|json!({"playerId":r.0,"displayName":r.1,"source":r.2,"expiresAtMs":r.3.timestamp_millis()}))
    })))
}

async fn friend_mutation(
    state: &AppState,
    address: &str,
    friend_code: &str,
    rid: &str,
    action: &str,
) -> Result<Value, ApiError> {
    let key = game::idem_key(action, address, rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(value);
    }
    let mut tx = state.db.begin().await?;
    let target = address_from_code_tx(&mut tx, friend_code).await?;
    if target == address {
        return Err(ApiError::BadRequest(
            "impossible de s'ajouter soi-même".to_string(),
        ));
    }
    lock_profiles_tx(&mut tx, address, &target).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(value);
    }
    let accepted = match action {
        "friend_request" => {
            if are_friends_tx(&mut tx, address, &target).await? {
                return Err(ApiError::Unavailable("déjà amis".to_string()));
            }
            let reverse =
                sqlx::query("DELETE FROM friend_requests WHERE requester=$1 AND addressee=$2")
                    .bind(&target)
                    .bind(address)
                    .execute(&mut *tx)
                    .await?
                    .rows_affected()
                    == 1;
            if reverse {
                sqlx::query(
                    "INSERT INTO friendships(address_a,address_b) VALUES(LEAST($1,$2),GREATEST($1,$2)) ON CONFLICT DO NOTHING",
                )
                .bind(address)
                .bind(&target)
                .execute(&mut *tx)
                .await?;
                true
            } else {
                sqlx::query(
                    "INSERT INTO friend_requests(requester,addressee) VALUES($1,$2) ON CONFLICT DO NOTHING",
                )
                .bind(address)
                .bind(&target)
                .execute(&mut *tx)
                .await?;
                false
            }
        }
        "friend_accept" => {
            let removed =
                sqlx::query("DELETE FROM friend_requests WHERE requester=$1 AND addressee=$2")
                    .bind(&target)
                    .bind(address)
                    .execute(&mut *tx)
                    .await?
                    .rows_affected();
            if removed != 1 {
                return Err(ApiError::Unavailable("invitation absente".to_string()));
            }
            sqlx::query(
                "INSERT INTO friendships(address_a,address_b) VALUES(LEAST($1,$2),GREATEST($1,$2)) ON CONFLICT DO NOTHING",
            )
            .bind(address)
            .bind(&target)
            .execute(&mut *tx)
            .await?;
            true
        }
        "friend_decline" => {
            let removed =
                sqlx::query("DELETE FROM friend_requests WHERE requester=$1 AND addressee=$2")
                    .bind(&target)
                    .bind(address)
                    .execute(&mut *tx)
                    .await?
                    .rows_affected();
            if removed != 1 {
                return Err(ApiError::Unavailable("invitation absente".to_string()));
            }
            false
        }
        "friend_remove" => {
            let removed = sqlx::query(
                "DELETE FROM friendships WHERE address_a=LEAST($1,$2) AND address_b=GREATEST($1,$2)",
            )
            .bind(address)
            .bind(&target)
            .execute(&mut *tx)
            .await?
            .rows_affected();
            if removed != 1 {
                return Err(ApiError::Unavailable("amitié absente".to_string()));
            }
            false
        }
        _ => return Err(ApiError::BadRequest("action sociale inconnue".to_string())),
    };
    let response = json!({"playerId":friend_code.trim().to_uppercase(),"status":if accepted{"friend"}else if action=="friend_request"{"outgoing"}else{"none"},"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(response)
}

macro_rules! friend_handler {
    ($name:ident, $action:literal) => {
        pub async fn $name(
            State(state): State<AppState>,
            Extension(addr): Extension<Addr>,
            headers: HeaderMap,
            Json(body): Json<FriendActionReq>,
        ) -> Result<Json<Value>, ApiError> {
            let rid = game::request_id(&headers, body.request_id.as_deref())?;
            Ok(Json(
                friend_mutation(&state, &addr.0, &body.friend_code, &rid, $action).await?,
            ))
        }
    };
}

friend_handler!(request_friend, "friend_request");
friend_handler!(accept_friend, "friend_accept");
friend_handler!(decline_friend, "friend_decline");
friend_handler!(remove_friend, "friend_remove");

pub async fn select_target(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<TargetPreferenceReq>,
) -> Result<Json<Value>, ApiError> {
    if body.source != "friend" && body.source != "revenge" {
        return Err(ApiError::BadRequest(
            "source doit être friend ou revenge".to_string(),
        ));
    }
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("social_target", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let target = address_from_code_tx(&mut tx, &body.friend_code).await?;
    if target == addr.0 {
        return Err(ApiError::BadRequest(
            "cible identique au joueur".to_string(),
        ));
    }
    lock_profiles_tx(&mut tx, &addr.0, &target).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let allowed = if body.source == "friend" {
        are_friends_tx(&mut tx, &addr.0, &target).await?
    } else {
        let revenge_cutoff = Utc::now()
            - chrono::Duration::milliseconds(
                i64::try_from(state.config.social.revenge_window_ms)
                    .map_err(|_| ApiError::Internal(anyhow!("revengeWindowMs overflow")))?,
            );
        sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM social_encounters WHERE attacker=$1 AND target=$2 AND kind='attack' AND status='resolved' AND created_at>=$3)",
        )
        .bind(&target)
        .bind(&addr.0)
        .bind(revenge_cutoff)
        .fetch_one(&mut *tx)
        .await?
    };
    if !allowed {
        return Err(ApiError::Unavailable(
            "cible non autorisée pour cette source".to_string(),
        ));
    }
    let attackable: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM district_progress dp LEFT JOIN district_damage dd \
         ON dd.address=dp.address AND dd.district_id=dp.district_id AND dd.element_id=dp.element_id \
         WHERE dp.address=$1 AND dp.level>0 AND dd.address IS NULL)",
    )
    .bind(&target)
    .fetch_one(&mut *tx)
    .await?;
    if !attackable {
        return Err(ApiError::Unavailable(
            "cible sans nœud attaquable".to_string(),
        ));
    }
    let expires_at = Utc::now()
        + chrono::Duration::milliseconds(
            i64::try_from(state.config.social.target_preference_ttl_ms)
                .map_err(|_| ApiError::Internal(anyhow!("targetPreferenceTtlMs overflow")))?,
        );
    sqlx::query(
        "INSERT INTO social_target_preferences(attacker,target,source,expires_at) VALUES($1,$2,$3,$4) \
         ON CONFLICT(attacker) DO UPDATE SET target=EXCLUDED.target,source=EXCLUDED.source,expires_at=EXCLUDED.expires_at,created_at=now()",
    )
    .bind(&addr.0)
    .bind(&target)
    .bind(&body.source)
    .bind(expires_at)
    .execute(&mut *tx)
    .await?;
    let response = json!({"playerId":body.friend_code.trim().to_uppercase(),"source":body.source,"expiresAtMs":expires_at.timestamp_millis(),"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profile_names_are_trimmed_and_bounded() {
        assert_eq!(
            valid_display_name("  Neon Fox  ").as_deref(),
            Some("Neon Fox")
        );
        assert!(valid_display_name("ab").is_none());
        assert!(valid_display_name("bad\nname").is_none());
        assert!(valid_display_name("bad👾name").is_none());
        assert!(valid_display_name(&"x".repeat(25)).is_none());
    }
}
