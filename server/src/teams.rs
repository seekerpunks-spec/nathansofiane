//! Équipes légères : roster, classement, entraide et messages prédéfinis.

use crate::auth::Addr;
use crate::db::Db;
use crate::error::ApiError;
use crate::friends;
use crate::game;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{Extension, Query, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

type HelpFeedRow = (
    String,
    String,
    String,
    i32,
    i32,
    chrono::DateTime<Utc>,
    bool,
);

#[derive(Deserialize)]
pub struct TeamQuery {
    #[serde(default)]
    q: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateTeamReq {
    name: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeamCodeReq {
    team_code: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeamMemberReq {
    friend_code: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeamLeaveReq {
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickMessageReq {
    phrase_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HelpRequestReq {
    #[serde(default)]
    request_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HelpDonateReq {
    help_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

fn valid_team_name(raw: &str) -> Option<String> {
    let name = raw.trim();
    if !(3..=24).contains(&name.chars().count())
        || !name
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, ' ' | '_' | '-' | '.'))
    {
        return None;
    }
    Some(name.to_string())
}

fn normalize_team_code(raw: &str) -> Result<String, ApiError> {
    let code = raw.trim().to_ascii_uppercase();
    if code.len() != 20
        || !code.starts_with("NET-")
        || !code[4..].bytes().all(|byte| byte.is_ascii_hexdigit())
    {
        return Err(ApiError::BadRequest("teamCode invalide".to_string()));
    }
    Ok(code)
}

async fn lock_players_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
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

async fn own_team(state: &AppState, address: &str) -> Result<Option<Value>, ApiError> {
    let own: Option<(String, String, String, String)> = sqlx::query_as(
        "SELECT t.team_id,t.team_code,t.name,tm.role FROM team_members tm JOIN teams t ON t.team_id=tm.team_id WHERE tm.address=$1",
    )
    .bind(address)
    .fetch_optional(state.db.pool())
    .await?;
    let Some((team_id, team_code, name, role)) = own else {
        return Ok(None);
    };
    let rows: Vec<(String, String, String, String, i64, i32)> = sqlx::query_as(
        "SELECT p.friend_code,p.display_name,p.avatar_id,tm.role,COALESCE(ps.score,0),s.district_index \
         FROM team_members tm JOIN player_profiles p ON p.address=tm.address \
         JOIN player_state s ON s.address=tm.address LEFT JOIN progression_scores ps ON ps.address=tm.address \
         WHERE tm.team_id=$1 ORDER BY (tm.role='owner') DESC,ps.score DESC,p.friend_code",
    )
    .bind(&team_id)
    .fetch_all(state.db.pool())
    .await?;
    let score = rows.iter().try_fold(0i64, |total, row| {
        total
            .checked_add(row.4)
            .ok_or_else(|| ApiError::Internal(anyhow!("team score overflow")))
    })?;
    let message_limit = i64::from(state.config.social.teams.chat_history_limit);
    let messages: Vec<(String, String, String, chrono::DateTime<Utc>)> = sqlx::query_as(
        "SELECT m.phrase_id,p.display_name,p.avatar_id,m.created_at FROM team_quick_messages m \
         JOIN player_profiles p ON p.address=m.address WHERE m.team_id=$1 \
         ORDER BY m.created_at DESC,m.message_id DESC LIMIT $2",
    )
    .bind(&team_id)
    .bind(message_limit)
    .fetch_all(state.db.pool())
    .await?;
    let help: Vec<HelpFeedRow> = sqlx::query_as(
        "SELECT h.help_id,p.friend_code,p.display_name,h.requested_spins,h.donated_spins,h.expires_at, \
         NOT EXISTS(SELECT 1 FROM team_help_donations d WHERE d.help_id=h.help_id AND d.donor=$2) \
         FROM team_help_requests h JOIN player_profiles p ON p.address=h.requester \
         WHERE h.team_id=$1 AND h.status='open' AND h.expires_at>now() \
         ORDER BY h.created_at DESC LIMIT 20",
    )
    .bind(&team_id)
    .bind(address)
    .fetch_all(state.db.pool())
    .await?;
    Ok(Some(json!({
        "teamId":team_id,"teamCode":team_code,"name":name,"role":role,"score":score,
        "members":rows.into_iter().map(|r|json!({"playerId":r.0,"displayName":r.1,"avatarId":r.2,"role":r.3,"score":r.4,"districtIndex":r.5})).collect::<Vec<_>>(),
        "messages":messages.into_iter().rev().map(|r|json!({"phraseId":r.0,"displayName":r.1,"avatarId":r.2,"createdAtMs":r.3.timestamp_millis()})).collect::<Vec<_>>(),
        "helpRequests":help.into_iter().map(|r|json!({"helpId":r.0,"requesterPlayerId":r.1,"displayName":r.2,"requestedSpins":r.3,"donatedSpins":r.4,"expiresAtMs":r.5.timestamp_millis(),"canDonate":r.6})).collect::<Vec<_>>(),
        "quickChatPhrases":state.config.social.teams.quick_chat_phrases,
        "helpRules":{"requestSpins":state.config.social.teams.donation_request_spins,"maxPerMember":state.config.social.teams.donation_max_per_member,"requestCooldownMs":state.config.social.teams.donation_request_cooldown_ms,"requestTtlMs":state.config.social.teams.donation_request_ttl_ms}
    })))
}

/// Même ordre que join/leave : joueur, puis crew. Ne jamais verrouiller une
/// demande d'aide avant les joueurs qu'elle va débiter/créditer.
async fn lock_current_team_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    address: &str,
) -> Result<String, ApiError> {
    sqlx::query("SELECT address FROM player_state WHERE address=$1 FOR UPDATE")
        .bind(address)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or(ApiError::NotFound)?;
    let team_id: String = sqlx::query_scalar("SELECT team_id FROM team_members WHERE address=$1")
        .bind(address)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| ApiError::Unavailable("crew requise".into()))?;
    sqlx::query("SELECT team_id FROM teams WHERE team_id=$1 FOR UPDATE")
        .bind(&team_id)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or(ApiError::NotFound)?;
    Ok(team_id)
}

pub async fn list(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    Query(query): Query<TeamQuery>,
) -> Result<Json<Value>, ApiError> {
    let q = query.q.as_deref().unwrap_or("").trim();
    if q.chars().count() > 24 || q.chars().any(char::is_control) {
        return Err(ApiError::BadRequest(
            "recherche équipe invalide".to_string(),
        ));
    }
    let limit = i64::from(state.config.social.teams.search_limit);
    let rows: Vec<(String, String, i64, i64)> = sqlx::query_as(
        "SELECT t.team_code,t.name,COUNT(tm.address)::bigint,COALESCE(SUM(ps.score),0)::bigint \
         FROM teams t LEFT JOIN team_members tm ON tm.team_id=t.team_id \
         LEFT JOIN progression_scores ps ON ps.address=tm.address \
         WHERE $1='' OR upper(t.team_code)=upper($1) OR position(lower($1) in lower(t.name))>0 \
         GROUP BY t.team_id ORDER BY (upper(t.team_code)=upper($1)) DESC,COALESCE(SUM(ps.score),0) DESC,t.team_code LIMIT $2",
    )
    .bind(q)
    .bind(limit)
    .fetch_all(state.db.pool())
    .await?;
    Ok(Json(json!({
        "ownTeam":own_team(&state,&addr.0).await?,
        "results":rows.into_iter().map(|r|json!({"teamCode":r.0,"name":r.1,"memberCount":r.2,"score":r.3,"full":r.2>=i64::from(state.config.social.teams.max_members)})).collect::<Vec<_>>()
    })))
}

pub async fn create(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<CreateTeamReq>,
) -> Result<Json<Value>, ApiError> {
    let name = valid_team_name(&body.name)
        .ok_or_else(|| ApiError::BadRequest("nom équipe invalide".to_string()))?;
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("team_create", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let player = state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or(ApiError::NotFound)?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let member: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM team_members WHERE address=$1)")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    if member {
        return Err(ApiError::Unavailable("déjà dans une équipe".to_string()));
    }
    let name_taken: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM teams WHERE lower(name)=lower($1))")
            .bind(&name)
            .fetch_one(&mut *tx)
            .await?;
    if name_taken {
        return Err(ApiError::Unavailable("nom équipe déjà pris".to_string()));
    }
    let cost = game::checked_u64_to_i64(
        state.config.social.teams.create_cost_credits,
        "team.createCostCredits",
    )?;
    if player.credits < cost {
        return Err(ApiError::InsufficientCredits);
    }
    let team_id = Uuid::new_v4().to_string();
    let compact = Uuid::new_v4().simple().to_string();
    let team_code = format!("NET-{}", compact[..16].to_uppercase());
    sqlx::query("UPDATE player_state SET credits=credits-$1 WHERE address=$2")
        .bind(cost)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    let inserted = sqlx::query(
        "INSERT INTO teams(team_id,team_code,name,owner_address) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING",
    )
        .bind(&team_id)
        .bind(&team_code)
        .bind(&name)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?
        .rows_affected();
    if inserted != 1 {
        return Err(ApiError::Unavailable("nom équipe déjà pris".to_string()));
    }
    sqlx::query("INSERT INTO team_members(team_id,address,role) VALUES($1,$2,'owner')")
        .bind(&team_id)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    let credits = player.credits - cost;
    let response = json!({"teamCode":team_code,"name":name,"role":"owner","cost":cost,"credits":credits,"serverTimeMs":Utc::now().timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "team_create",
        &json!({"credits":player.credits}),
        &response,
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn join(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<TeamCodeReq>,
) -> Result<Json<Value>, ApiError> {
    let team_code = normalize_team_code(&body.team_code)?;
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("team_join", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or(ApiError::NotFound)?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let team: (String, String, String) = sqlx::query_as(
        "SELECT team_id,team_code,name FROM teams WHERE upper(team_code)=upper($1) FOR UPDATE",
    )
    .bind(team_code)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound)?;
    let existing: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM team_members WHERE address=$1)")
            .bind(&addr.0)
            .fetch_one(&mut *tx)
            .await?;
    if existing {
        return Err(ApiError::Unavailable("déjà dans une équipe".to_string()));
    }
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM team_members WHERE team_id=$1")
            .bind(&team.0)
            .fetch_one(&mut *tx)
            .await?;
    if count >= i64::from(state.config.social.teams.max_members) {
        return Err(ApiError::Unavailable("équipe complète".to_string()));
    }
    sqlx::query("INSERT INTO team_members(team_id,address) VALUES($1,$2)")
        .bind(&team.0)
        .bind(&addr.0)
        .execute(&mut *tx)
        .await?;
    let response = json!({"teamCode":team.1,"name":team.2,"role":"member","memberCount":count+1,"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn leave(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<TeamLeaveReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("team_leave", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    state
        .db
        .fetch_state_locked(&mut tx, &addr.0)
        .await?
        .ok_or(ApiError::NotFound)?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let membership: (String, String) =
        sqlx::query_as("SELECT team_id,role FROM team_members WHERE address=$1")
            .bind(&addr.0)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| ApiError::Unavailable("aucune équipe".to_string()))?;
    sqlx::query("SELECT team_id FROM teams WHERE team_id=$1 FOR UPDATE")
        .bind(&membership.0)
        .fetch_one(&mut *tx)
        .await?;
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::bigint FROM team_members WHERE team_id=$1")
            .bind(&membership.0)
            .fetch_one(&mut *tx)
            .await?;
    let deleted_team = membership.1 == "owner" && count == 1;
    if membership.1 == "owner" && count > 1 {
        return Err(ApiError::Unavailable(
            "transfère la propriété avant de partir".to_string(),
        ));
    }
    if deleted_team {
        sqlx::query("DELETE FROM teams WHERE team_id=$1")
            .bind(&membership.0)
            .execute(&mut *tx)
            .await?;
    } else {
        sqlx::query("DELETE FROM team_members WHERE team_id=$1 AND address=$2")
            .bind(&membership.0)
            .bind(&addr.0)
            .execute(&mut *tx)
            .await?;
    }
    let response = json!({"left":true,"teamDeleted":deleted_team,"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

async fn owner_member_action(
    state: &AppState,
    owner: &str,
    friend_code: &str,
    rid: &str,
    transfer: bool,
) -> Result<Value, ApiError> {
    let friend_code = friends::normalize_friend_code(friend_code)?;
    let action = if transfer {
        "team_transfer"
    } else {
        "team_kick"
    };
    let key = game::idem_key(action, owner, rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(value);
    }
    let mut tx = state.db.begin().await?;
    let target = friends::address_from_code_tx(&mut tx, &friend_code).await?;
    if target == owner {
        return Err(ApiError::BadRequest("membre invalide".to_string()));
    }
    lock_players_tx(&mut tx, owner, &target).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(value);
    }
    let team_id: String =
        sqlx::query_scalar("SELECT team_id FROM team_members WHERE address=$1 AND role='owner'")
            .bind(owner)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| ApiError::Unavailable("owner requis".to_string()))?;
    sqlx::query("SELECT team_id FROM teams WHERE team_id=$1 FOR UPDATE")
        .bind(&team_id)
        .fetch_one(&mut *tx)
        .await?;
    let target_member: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM team_members WHERE team_id=$1 AND address=$2)",
    )
    .bind(&team_id)
    .bind(&target)
    .fetch_one(&mut *tx)
    .await?;
    if !target_member {
        return Err(ApiError::Unavailable("joueur hors équipe".to_string()));
    }
    if transfer {
        sqlx::query("UPDATE team_members SET role='member' WHERE team_id=$1 AND address=$2")
            .bind(&team_id)
            .bind(owner)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE team_members SET role='owner' WHERE team_id=$1 AND address=$2")
            .bind(&team_id)
            .bind(&target)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE teams SET owner_address=$1 WHERE team_id=$2")
            .bind(&target)
            .bind(&team_id)
            .execute(&mut *tx)
            .await?;
    } else {
        sqlx::query("DELETE FROM team_members WHERE team_id=$1 AND address=$2")
            .bind(&team_id)
            .bind(&target)
            .execute(&mut *tx)
            .await?;
    }
    let response = json!({"playerId":friend_code,"transferred":transfer,"kicked":!transfer,"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(response)
}

macro_rules! owner_handler {
    ($name:ident, $transfer:literal) => {
        pub async fn $name(
            State(state): State<AppState>,
            Extension(addr): Extension<Addr>,
            headers: HeaderMap,
            Json(body): Json<TeamMemberReq>,
        ) -> Result<Json<Value>, ApiError> {
            let rid = game::request_id(&headers, body.request_id.as_deref())?;
            Ok(Json(
                owner_member_action(&state, &addr.0, &body.friend_code, &rid, $transfer).await?,
            ))
        }
    };
}

owner_handler!(kick, false);
owner_handler!(transfer, true);

pub async fn quick_message(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<QuickMessageReq>,
) -> Result<Json<Value>, ApiError> {
    if !state
        .config
        .social
        .teams
        .quick_chat_phrases
        .iter()
        .any(|phrase| phrase.id == body.phrase_id)
    {
        return Err(ApiError::BadRequest("phraseId invalide".to_string()));
    }
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("team_quick_message", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let team_id = lock_current_team_tx(&mut tx, &addr.0).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let message_id = Uuid::new_v4().to_string();
    sqlx::query(
        "INSERT INTO team_quick_messages(message_id,team_id,address,phrase_id) VALUES($1,$2,$3,$4)",
    )
    .bind(&message_id)
    .bind(&team_id)
    .bind(&addr.0)
    .bind(&body.phrase_id)
    .execute(&mut *tx)
    .await?;
    let response = json!({"messageId":message_id,"phraseId":body.phrase_id,"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn request_help(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<HelpRequestReq>,
) -> Result<Json<Value>, ApiError> {
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("team_help_request", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let team_id = lock_current_team_tx(&mut tx, &addr.0).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    sqlx::query("UPDATE team_help_requests SET status='expired' WHERE requester=$1 AND status='open' AND (expires_at<=now() OR team_id<>$2)")
        .bind(&addr.0)
        .bind(&team_id)
        .execute(&mut *tx)
        .await?;
    let open: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM team_help_requests WHERE requester=$1 AND status='open')",
    )
    .bind(&addr.0)
    .fetch_one(&mut *tx)
    .await?;
    if open {
        return Err(ApiError::Unavailable(
            "demande d'entraide encore ouverte".into(),
        ));
    }
    let latest: Option<chrono::DateTime<Utc>> = sqlx::query_scalar(
        "SELECT created_at FROM team_help_requests WHERE requester=$1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(&addr.0)
    .fetch_optional(&mut *tx)
    .await?;
    let cooldown = chrono::Duration::milliseconds(
        i64::try_from(state.config.social.teams.donation_request_cooldown_ms)
            .map_err(|_| ApiError::Internal(anyhow!("help cooldown overflow")))?,
    );
    if latest.is_some_and(|created| created + cooldown > Utc::now()) {
        return Err(ApiError::Unavailable(
            "demande d'entraide en recharge".to_string(),
        ));
    }
    let ttl = chrono::Duration::milliseconds(
        i64::try_from(state.config.social.teams.donation_request_ttl_ms)
            .map_err(|_| ApiError::Internal(anyhow!("help ttl overflow")))?,
    );
    let requested = i32::try_from(state.config.social.teams.donation_request_spins)
        .map_err(|_| ApiError::Internal(anyhow!("help amount overflow")))?;
    let help_id = Uuid::new_v4().to_string();
    let expires_at = Utc::now() + ttl;
    sqlx::query("INSERT INTO team_help_requests(help_id,team_id,requester,requested_spins,expires_at) VALUES($1,$2,$3,$4,$5)")
        .bind(&help_id)
        .bind(&team_id)
        .bind(&addr.0)
        .bind(requested)
        .bind(expires_at)
        .execute(&mut *tx)
        .await?;
    let response = json!({"helpId":help_id,"requestedSpins":requested,"donatedSpins":0,"expiresAtMs":expires_at.timestamp_millis(),"serverTimeMs":Utc::now().timestamp_millis()});
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn donate_help(
    State(state): State<AppState>,
    Extension(addr): Extension<Addr>,
    headers: HeaderMap,
    Json(body): Json<HelpDonateReq>,
) -> Result<Json<Value>, ApiError> {
    let help_id = body.help_id.trim();
    if help_id.len() != 36 || Uuid::parse_str(help_id).is_err() {
        return Err(ApiError::BadRequest("helpId invalide".to_string()));
    }
    let rid = game::request_id(&headers, body.request_id.as_deref())?;
    let key = game::idem_key("team_help_donate", &addr.0, &rid);
    if let Some(value) = state.db.fetch_idempotent(&key).await? {
        return Ok(Json(value));
    }
    let mut tx = state.db.begin().await?;
    let (team_id, requester): (String, String) =
        sqlx::query_as("SELECT team_id,requester FROM team_help_requests WHERE help_id=$1")
            .bind(help_id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or(ApiError::NotFound)?;
    if requester == addr.0 {
        return Err(ApiError::BadRequest(
            "impossible de répondre à sa propre demande".into(),
        ));
    }
    lock_players_tx(&mut tx, &addr.0, &requester).await?;
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    sqlx::query("SELECT team_id FROM teams WHERE team_id=$1 FOR UPDATE")
        .bind(&team_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(ApiError::NotFound)?;
    let request: (String, String, i32, i32, String, chrono::DateTime<Utc>) = sqlx::query_as(
        "SELECT team_id,requester,requested_spins,donated_spins,status,expires_at FROM team_help_requests WHERE help_id=$1 FOR UPDATE",
    )
    .bind(help_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound)?;
    if request.4 != "open" || request.5 <= Utc::now() {
        sqlx::query(
            "UPDATE team_help_requests SET status='expired' WHERE help_id=$1 AND status='open'",
        )
        .bind(help_id)
        .execute(&mut *tx)
        .await?;
        return Err(ApiError::Unavailable("demande expirée".to_string()));
    }
    if request.1 == addr.0 {
        return Err(ApiError::BadRequest(
            "impossible de répondre à sa propre demande".to_string(),
        ));
    }
    let members: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM team_members WHERE team_id=$1 AND (address=$2 OR address=$3)",
    )
    .bind(&request.0)
    .bind(&addr.0)
    .bind(&request.1)
    .fetch_one(&mut *tx)
    .await?;
    if members != 2 {
        return Err(ApiError::Unavailable("crew différente".to_string()));
    }
    let locked: Vec<(String, i32, Option<chrono::DateTime<Utc>>)> = sqlx::query_as(
        "SELECT address,spins,last_spin_at FROM player_state WHERE address=$1 OR address=$2 ORDER BY address FOR UPDATE",
    )
    .bind(&addr.0)
    .bind(&request.1)
    .fetch_all(&mut *tx)
    .await?;
    if locked.len() != 2 {
        return Err(ApiError::NotFound);
    }
    if let Some(value) = state.db.fetch_idempotent_locked(&mut tx, &key).await? {
        tx.rollback().await?;
        return Ok(Json(value));
    }
    let donated_before: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM team_help_donations WHERE help_id=$1 AND donor=$2)",
    )
    .bind(help_id)
    .bind(&addr.0)
    .fetch_one(&mut *tx)
    .await?;
    if donated_before {
        return Err(ApiError::Unavailable("aide déjà envoyée".to_string()));
    }
    let donor = locked
        .iter()
        .find(|row| row.0 == addr.0)
        .ok_or(ApiError::NotFound)?;
    let recipient = locked
        .iter()
        .find(|row| row.0 == request.1)
        .ok_or(ApiError::NotFound)?;
    let now = Utc::now();
    let donor_regen = crate::spin::regen_state(donor.2, now, donor.1, &state.config);
    let recipient_regen = crate::spin::regen_state(recipient.2, now, recipient.1, &state.config);
    let donor_before = donor_regen.spins;
    let recipient_before = recipient_regen.spins;
    // À plafond gratuit, une dépense redémarre le timer à maintenant.
    let donor_anchor = donor_regen.anchor.unwrap_or(now);
    let recipient_anchor = recipient_regen.anchor.unwrap_or(now);
    let remaining = request.2 - request.3;
    let per_member = i32::try_from(state.config.social.teams.donation_max_per_member)
        .map_err(|_| ApiError::Internal(anyhow!("donation amount overflow")))?;
    let amount = remaining.min(per_member);
    if amount <= 0 {
        return Err(ApiError::Unavailable("demande déjà remplie".to_string()));
    }
    if donor_before < amount {
        return Err(ApiError::InsufficientSpins {
            required_spins: u32::try_from(amount).unwrap_or_default(),
            available_spins: donor_before,
            next_spin_at_ms: donor_regen.next_spin_at_ms,
        });
    }
    let donor_after = donor_before - amount;
    let recipient_after = recipient_before
        .checked_add(amount)
        .ok_or_else(|| ApiError::Internal(anyhow!("donation balance overflow")))?;
    sqlx::query("UPDATE player_state SET spins=CASE WHEN address=$1 THEN $3 ELSE $4 END,last_spin_at=CASE WHEN address=$1 THEN $5 ELSE $6 END WHERE address=$1 OR address=$2")
        .bind(&addr.0)
        .bind(&request.1)
        .bind(donor_after)
        .bind(recipient_after)
        .bind(donor_anchor)
        .bind(recipient_anchor)
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO team_help_donations(help_id,donor,spins) VALUES($1,$2,$3)")
        .bind(help_id)
        .bind(&addr.0)
        .bind(amount)
        .execute(&mut *tx)
        .await?;
    let donated = request.3 + amount;
    let fulfilled = donated >= request.2;
    sqlx::query("UPDATE team_help_requests SET donated_spins=$1,status=$2 WHERE help_id=$3")
        .bind(donated)
        .bind(if fulfilled { "fulfilled" } else { "open" })
        .bind(help_id)
        .execute(&mut *tx)
        .await?;
    let next_spin_at_ms =
        crate::spin::regen_state(Some(donor_anchor), now, donor_after, &state.config)
            .next_spin_at_ms;
    let response = json!({"helpId":help_id,"donatedSpins":amount,"totalDonatedSpins":donated,"fulfilled":fulfilled,"spins":donor_after,"nextSpinAtMs":next_spin_at_ms,"serverTimeMs":now.timestamp_millis()});
    Db::audit_tx(
        &mut tx,
        &addr.0,
        "team_help_donated",
        &json!({"spins":donor_before}),
        &json!({"spins":donor_after,"donatedSpins":amount}),
        Some(&rid),
    )
    .await?;
    Db::audit_tx(
        &mut tx,
        &request.1,
        "team_help_received",
        &json!({"spins":recipient_before}),
        &json!({"spins":recipient_after,"receivedSpins":amount}),
        Some(&rid),
    )
    .await?;
    state.db.store_idempotent(&mut tx, &key, &response).await?;
    tx.commit().await?;
    Ok(Json(response))
}

pub async fn leaderboard(
    State(state): State<AppState>,
    Extension(_addr): Extension<Addr>,
) -> Result<Json<Value>, ApiError> {
    let limit = i64::from(state.config.social.teams.leaderboard_limit);
    let rows: Vec<(i64, String, String, i64, i64)> = sqlx::query_as(
        "SELECT DENSE_RANK() OVER(ORDER BY COALESCE(SUM(ps.score),0) DESC),t.team_code,t.name, \
         COUNT(tm.address)::bigint,COALESCE(SUM(ps.score),0)::bigint FROM teams t \
         LEFT JOIN team_members tm ON tm.team_id=t.team_id LEFT JOIN progression_scores ps ON ps.address=tm.address \
         GROUP BY t.team_id ORDER BY COALESCE(SUM(ps.score),0) DESC,t.team_code LIMIT $1",
    )
    .bind(limit)
    .fetch_all(state.db.pool())
    .await?;
    Ok(Json(
        json!({"entries":rows.into_iter().map(|r|json!({"rank":r.0,"teamCode":r.1,"name":r.2,"memberCount":r.3,"score":r.4})).collect::<Vec<_>>()}),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::RemoteConfig;
    use crate::rate_limit::RateLimiter;
    use std::sync::Arc;

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
            auth_domain: "qa.cyberseeker.local".to_string(),
            dev_auth: false,
            dev_address: None,
            started_at: std::time::Instant::now(),
        })
    }

    #[test]
    fn team_names_are_safe_and_bounded() {
        assert_eq!(
            valid_team_name("  Neon Crew ").as_deref(),
            Some("Neon Crew")
        );
        assert!(valid_team_name("no").is_none());
        assert!(valid_team_name("bad/team").is_none());
    }

    #[tokio::test]
    async fn postgres_team_help_has_one_concurrent_donation() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_team_help_has_one_concurrent_donation").await
        else {
            return Ok(());
        };
        let state = state_for_tests(db.clone())?;
        let requester = format!("qa-help-requester-{}", Uuid::new_v4());
        let donor = format!("qa-help-donor-{}", Uuid::new_v4());
        db.ensure_player(&requester, 0).await?;
        db.ensure_player(&donor, 10).await?;
        let team_id = format!("qa-help-team-{}", Uuid::new_v4());
        let team_code = format!("NET-{}", &Uuid::new_v4().simple().to_string()[..16]);
        sqlx::query("INSERT INTO teams(team_id,team_code,name,owner_address) VALUES($1,$2,$3,$4)")
            .bind(&team_id)
            .bind(team_code)
            .bind(format!(
                "Help {}",
                &Uuid::new_v4().simple().to_string()[..8]
            ))
            .bind(&requester)
            .execute(db.pool())
            .await?;
        sqlx::query(
            "INSERT INTO team_members(team_id,address,role) VALUES($1,$2,'owner'),($1,$3,'member')",
        )
        .bind(&team_id)
        .bind(&requester)
        .bind(&donor)
        .execute(db.pool())
        .await?;
        let help_id = Uuid::new_v4().to_string();
        sqlx::query("INSERT INTO team_help_requests(help_id,team_id,requester,requested_spins,expires_at) VALUES($1,$2,$3,5,now()+interval '1 day')")
            .bind(&help_id)
            .bind(&team_id)
            .bind(&requester)
            .execute(db.pool())
            .await?;

        let first = donate_help(
            State(state.clone()),
            Extension(Addr(donor.clone())),
            HeaderMap::new(),
            Json(HelpDonateReq {
                help_id: help_id.clone(),
                request_id: Some(Uuid::new_v4().to_string()),
            }),
        );
        let second = donate_help(
            State(state.clone()),
            Extension(Addr(donor.clone())),
            HeaderMap::new(),
            Json(HelpDonateReq {
                help_id: help_id.clone(),
                request_id: Some(Uuid::new_v4().to_string()),
            }),
        );
        let (first, second) = tokio::join!(first, second);
        let outcomes = [first, second];
        assert_eq!(outcomes.iter().filter(|result| result.is_ok()).count(), 1);
        assert!(outcomes
            .iter()
            .any(|result| matches!(result, Err(ApiError::Unavailable(_)))));
        let donor_spins: i32 =
            sqlx::query_scalar("SELECT spins FROM player_state WHERE address=$1")
                .bind(&donor)
                .fetch_one(db.pool())
                .await?;
        let requester_spins: i32 =
            sqlx::query_scalar("SELECT spins FROM player_state WHERE address=$1")
                .bind(&requester)
                .fetch_one(db.pool())
                .await?;
        assert_eq!(donor_spins, 8);
        assert_eq!(requester_spins, 2);
        let donations: i64 =
            sqlx::query_scalar("SELECT COUNT(*)::bigint FROM team_help_donations WHERE help_id=$1")
                .bind(&help_id)
                .fetch_one(db.pool())
                .await?;
        assert_eq!(donations, 1);

        // Cooldown écoulé, mais demande non remplie : erreur métier, pas SQL 500.
        sqlx::query(
            "UPDATE team_help_requests SET created_at=now()-interval '9 hours' WHERE help_id=$1",
        )
        .bind(&help_id)
        .execute(db.pool())
        .await?;
        let still_open = request_help(
            State(state.clone()),
            Extension(Addr(requester.clone())),
            HeaderMap::new(),
            Json(HelpRequestReq {
                request_id: Some(Uuid::new_v4().to_string()),
            }),
        )
        .await;
        assert!(matches!(still_open, Err(ApiError::Unavailable(_))));

        // Nouvelle demande bornée à 2 : deux retries simultanés doivent tous
        // deux réussir même si le premier la remplit intégralement.
        sqlx::query("UPDATE team_help_requests SET status='expired' WHERE help_id=$1")
            .bind(&help_id)
            .execute(db.pool())
            .await?;
        let next_help = request_help(
            State(state.clone()),
            Extension(Addr(requester.clone())),
            HeaderMap::new(),
            Json(HelpRequestReq {
                request_id: Some(Uuid::new_v4().to_string()),
            }),
        )
        .await?
        .0;
        let next_id = next_help["helpId"].as_str().unwrap().to_string();
        sqlx::query("UPDATE team_help_requests SET requested_spins=2 WHERE help_id=$1")
            .bind(&next_id)
            .execute(db.pool())
            .await?;
        let interval = i64::try_from(state.config.economy.spin_regen_ms)?;
        sqlx::query("UPDATE player_state SET spins=0,last_spin_at=now()-($3 * interval '1 millisecond') WHERE address=$1 OR address=$2")
            .bind(&donor).bind(&requester).bind(interval * 2 + interval / 2).execute(db.pool()).await?;
        let rid = Uuid::new_v4().to_string();
        let retry = || {
            donate_help(
                State(state.clone()),
                Extension(Addr(donor.clone())),
                HeaderMap::new(),
                Json(HelpDonateReq {
                    help_id: next_id.clone(),
                    request_id: Some(rid.clone()),
                }),
            )
        };
        let (first, second) = tokio::join!(retry(), retry());
        let first = first?.0;
        assert_eq!(first, second?.0);
        assert_eq!(first["spins"], 0);
        assert_eq!(first["fulfilled"], true);
        let recipient_after: i32 =
            sqlx::query_scalar("SELECT spins FROM player_state WHERE address=$1")
                .bind(&requester)
                .fetch_one(db.pool())
                .await?;
        assert_eq!(recipient_after, 4);
        let until_next = first["nextSpinAtMs"].as_i64().unwrap() - Utc::now().timestamp_millis();
        assert!(until_next > 0 && until_next <= interval / 2);

        // Un demandeur ayant quitté la crew ne peut plus recevoir de dons.
        sqlx::query(
            "UPDATE team_help_requests SET requested_spins=5,status='open' WHERE help_id=$1",
        )
        .bind(&next_id)
        .execute(db.pool())
        .await?;
        sqlx::query("DELETE FROM team_members WHERE address=$1")
            .bind(&requester)
            .execute(db.pool())
            .await?;
        let former_member = donate_help(
            State(state.clone()),
            Extension(Addr(donor.clone())),
            HeaderMap::new(),
            Json(HelpDonateReq {
                help_id: next_id,
                request_id: Some(Uuid::new_v4().to_string()),
            }),
        )
        .await;
        assert!(matches!(former_member, Err(ApiError::Unavailable(_))));
        Ok(())
    }
}
