//! Équipes légères : roster, recherche et classement, sans chat libre.

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
    Ok(Some(json!({
        "teamId":team_id,"teamCode":team_code,"name":name,"role":role,"score":score,
        "members":rows.into_iter().map(|r|json!({"playerId":r.0,"displayName":r.1,"avatarId":r.2,"role":r.3,"score":r.4,"districtIndex":r.5})).collect::<Vec<_>>()
    })))
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
         WHERE $1='' OR upper(t.team_code)=upper($1) OR t.name ILIKE '%' || $1 || '%' \
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
    .bind(body.team_code.trim())
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
        sqlx::query_as("SELECT team_id,role FROM team_members WHERE address=$1 FOR UPDATE")
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
    let target = friends::address_from_code_tx(&mut tx, friend_code).await?;
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
    let response = json!({"playerId":friend_code.trim().to_uppercase(),"transferred":transfer,"kicked":!transfer,"serverTimeMs":Utc::now().timestamp_millis()});
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

    #[test]
    fn team_names_are_safe_and_bounded() {
        assert_eq!(
            valid_team_name("  Neon Crew ").as_deref(),
            Some("Neon Crew")
        );
        assert!(valid_team_name("no").is_none());
        assert!(valid_team_name("bad/team").is_none());
    }
}
