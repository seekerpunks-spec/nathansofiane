//! CYBERSEEKER — serveur (Rust/Axum) — R17
//!
//! Backend AUTHORITATIVE (GDD §37-39, ARCH §4) :
//!   - auth wallet (challenge/nonce Ed25519 + JWT HS256)
//!   - `POST /spin`  : CSPRNG serveur, regen temporelle, idempotence, audit
//!   - `GET  /state` : snapshot joueur (+ regen d'affichage, non persistée)
//!   - `GET  /config`: remote config versionnée (hash SHA-256)
//!   - `POST /analytics` : ingestion batch (≤ 100 événements)
//!   - `GET  /health`: liveness + version config
//!
//! Anti-triche : horloge serveur, transactions SQL, idempotence atomique,
//! rate limiting, audit de chaque mutation et preuves externes refusées par défaut.

mod auth;
mod collection;
mod commerce;
mod config;
mod db;
mod district;
mod engagement;
mod env;
mod error;
mod game;
mod rate_limit;
mod spin;
mod state;

use crate::error::ApiError;
use crate::state::AppState;
use anyhow::anyhow;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Extension, State};
use axum::http::{HeaderValue, Method, Request};
use axum::middleware;
use axum::response::Response;
use axum::routing::{get, post};
use axum::Json;
use axum::Router;
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    env::load_dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

    let database_url =
        std::env::var("DATABASE_URL").expect("DATABASE_URL manquante (voir server/.env.example)");
    let jwt_secret = match std::env::var("JWT_SECRET") {
        Ok(s) if s.len() >= 32 => s,
        _ => {
            if cfg!(debug_assertions) {
                tracing::warn!("JWT_SECRET absente/courte — secret dev utilisé (JAMAIS en prod)");
                "dev-only-change-me".to_string()
            } else {
                panic!("JWT_SECRET doit être définie (>= 32 caractères) en production");
            }
        }
    };
    let config_dir = std::env::var("CONFIG_DIR").unwrap_or_else(|_| "../config".to_string());
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);
    let dev_auth = std::env::var("DEV_AUTH")
        .map(|v| v == "true")
        .unwrap_or(false);
    if dev_auth && !cfg!(debug_assertions) {
        return Err(anyhow!("DEV_AUTH=true est interdit dans un build release"));
    }
    let dev_address = std::env::var("DEV_ADDRESS").ok();
    let rate_per_min: u32 = std::env::var("RATE_LIMIT_PER_MINUTE")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(30);

    let config = Arc::new(config::RemoteConfig::load(std::path::Path::new(
        &config_dir,
    ))?);
    tracing::info!(version = %config.version, "remote config chargée + validée");
    if dev_auth {
        tracing::warn!(
            dev_address = ?dev_address,
            "!!! DEV AUTH ACTIVE — usage local uniquement, JAMAIS en production !!!"
        );
    }

    let db = db::Db::connect(&database_url).await?;
    tracing::info!("Postgres connecté, migrations appliquées");

    let state = Arc::new(AppState {
        db,
        config: Arc::clone(&config),
        jwt_secret,
        dev_auth,
        dev_address,
        nonce: Arc::new(auth::NonceStore::default()),
        rate: Arc::new(rate_limit::RateLimiter::new(
            Duration::from_secs(60),
            rate_per_min,
        )),
        started_at: std::time::Instant::now(),
    });

    // Maintenance bornée des réponses rejouables. Les audits économiques ne
    // sont pas touchés par cette tâche et suivent la rétention de production.
    let maintenance_pool = state.db.pool().clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(3600));
        loop {
            interval.tick().await;
            if let Err(error) =
                sqlx::query("DELETE FROM idempotency WHERE created_at < now() - interval '30 days'")
                    .execute(&maintenance_pool)
                    .await
            {
                tracing::warn!(?error, "nettoyage idempotency échoué");
            }
        }
    });

    let cors = if dev_auth {
        CorsLayer::permissive()
    } else if let Ok(origin) = std::env::var("CORS_ORIGIN") {
        let origin: HeaderValue = origin
            .parse()
            .map_err(|_| anyhow!("CORS_ORIGIN invalide"))?;
        CorsLayer::new()
            .allow_origin(origin)
            .allow_methods([Method::GET, Method::POST])
            .allow_headers([
                axum::http::header::AUTHORIZATION,
                axum::http::header::CONTENT_TYPE,
                axum::http::HeaderName::from_static("x-request-id"),
            ])
    } else {
        CorsLayer::new()
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/config", get(config_endpoint))
        .route("/auth/challenge", post(auth::challenge))
        .route("/auth/verify", post(auth::verify))
        .route("/auth/refresh", post(auth::refresh))
        .route("/state", get(get_state))
        .route("/spin", post(spin::spin))
        .route("/district/upgrade", post(district::upgrade))
        .route("/chest/buy", post(collection::buy_chest))
        .route("/chest/open", post(collection::open_chest))
        .route("/set/claim", post(collection::claim_set))
        .route("/daily/claim", post(engagement::claim_daily))
        .route("/mission/claim", post(engagement::claim_mission))
        .route(
            "/events/:event_id/leaderboard",
            get(engagement::leaderboard),
        )
        .route(
            "/events/:event_id/milestones/:milestone_index/claim",
            post(engagement::claim_event_milestone),
        )
        .route("/events/:event_id/claim", post(engagement::claim_event))
        .route("/season/claim", post(engagement::claim_season))
        .route("/ad/reward", post(commerce::reward_ad))
        .route("/purchase/verify", post(commerce::verify_purchase))
        .route("/analytics", post(analytics))
        .layer(middleware::from_fn_with_state(Arc::clone(&state), guard))
        .layer(DefaultBodyLimit::max(256 * 1024))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state.as_ref().clone());

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!(%addr, "cyberseeker-server R17 en écoute");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    // Le middleware `guard` extrait `ConnectInfo<SocketAddr>` (IP client, rate limit) :
    // sans `into_make_service_with_connect_info`, l'extractor échoue et TOUTES les
    // routes renvoyent 500. API axum 0.7 : la méthode est sur le Router (pas sur
    // le `Serve` renvoyé par `axum::serve`).
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;
    Ok(())
}

/// Middleware : auth (JWT) + rate limiting + injection `Addr` pour les handlers.
async fn guard(
    State(state): State<Arc<AppState>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    mut req: Request<axum::body::Body>,
    next: middleware::Next,
) -> Result<Response, ApiError> {
    let path = req.uri().path().to_string();

    // Sans auth ni rate limit.
    if path == "/health" || path == "/config" {
        return Ok(next.run(req).await);
    }

    // Routes publiques d'auth : rate limit par IP (anti brute-force).
    if path.starts_with("/auth/") {
        // Ne jamais faire confiance à X-Forwarded-For sans proxy de confiance.
        let ip = peer.ip().to_string();
        if !state.rate.check(&format!("ip:{ip}")) {
            return Err(ApiError::RateLimited);
        }
        return Ok(next.run(req).await);
    }

    // Routes protégées : JWT obligatoire + rate limit par adresse.
    let address = auth::auth_address(&state, &req.headers())?;
    if !state.rate.check(&address) {
        return Err(ApiError::RateLimited);
    }
    req.extensions_mut().insert(auth::Addr(address));
    Ok(next.run(req).await)
}

/// `GET /health` — publique.
async fn health(State(state): State<AppState>) -> Json<Value> {
    Json(json!({
        "status": "ok",
        "version": env!("CARGO_PKG_VERSION"),
        "configVersion": state.config.version,
        "uptimeMs": state.started_at.elapsed().as_millis() as u64,
    }))
}

/// `GET /config` — publique. Le client compare le hash local ; différent →
/// téléchargement + purge du cache économique (live-ops, ARCH §5.2).
async fn config_endpoint(State(state): State<AppState>) -> Json<Value> {
    Json(json!({
        "version": state.config.version,
        "hash": state.config.hash,
        "payload": state.config.payload(),
    }))
}

/// `GET /state` — snapshot joueur.
///
/// La regen est calculée pour l'AFFICHAGE (non persistée) : le spin effectif
/// est la seule mutation, et il recalcule exactement la même chose.
async fn get_state(
    State(state): State<AppState>,
    Extension(addr): Extension<auth::Addr>,
) -> Result<Json<Value>, ApiError> {
    let address = addr.0;
    let row = state
        .db
        .fetch_state(&address)
        .await?
        .ok_or_else(|| ApiError::Internal(anyhow!("pas de player_state pour {address}")))?;

    let now = Utc::now();
    let regen = spin::regen_state(row.last_spin_at, now, row.spins, &state.config);
    let spins = regen.spins;
    let next_spin_at = regen.next_spin_at_ms;

    let cards = state.db.fetch_cards(&address).await?;
    let chests = state.db.fetch_chests(&address).await?;
    let district_progress: Vec<(i32, i32, i32)> = sqlx::query_as(
        "SELECT district_id,element_id,level FROM district_progress WHERE address=$1 ORDER BY district_id,element_id",
    ).bind(&address).fetch_all(state.db.pool()).await?;
    let completed_sets: Vec<String> = sqlx::query_scalar(
        "SELECT set_id FROM set_completion WHERE address=$1 AND claimed=true ORDER BY set_id",
    )
    .bind(&address)
    .fetch_all(state.db.pool())
    .await?;
    let today = now.date_naive();
    let mission_rows: Vec<(String, i64, bool)> = sqlx::query_as(
        "SELECT mission_id,progress,claimed FROM mission_progress WHERE address=$1 AND mission_day=$2",
    ).bind(&address).bind(today).fetch_all(state.db.pool()).await?;
    let missions: Vec<Value> = state.config.daily.missions.iter().map(|m| {
        let row = mission_rows.iter().find(|(id,_,_)| id == &m.mission_id);
        json!({"missionId":m.mission_id,"name":m.name,"action":m.action,"target":m.target,
            "progress":row.map(|r| r.1).unwrap_or(0),"claimed":row.map(|r|r.2).unwrap_or(false),"reward":m.reward})
    }).collect();
    let event_scores: Vec<(String, i64, bool)> =
        sqlx::query_as("SELECT event_id,points,reward_claimed FROM event_scores WHERE address=$1")
            .bind(&address)
            .fetch_all(state.db.pool())
            .await?;
    let milestone_claims: Vec<(String, i32, bool)> = sqlx::query_as(
        "SELECT event_id,milestone_index,auto_claimed FROM event_milestone_claims WHERE address=$1",
    )
    .bind(&address)
    .fetch_all(state.db.pool())
    .await?;
    let events: Vec<Value> = state.config.events.iter().map(|e| {
        let score = event_scores.iter().find(|(id,_,_)| id == &e.event_id);
        let milestones: Vec<Value> = e.milestones.iter().enumerate().map(|(index,milestone)| {
            let claim = milestone_claims.iter().find(|(event_id,milestone_index,_)| {
                event_id == &e.event_id && *milestone_index == index as i32
            });
            json!({"index":index,"points":milestone.points,"reward":milestone.reward,
                "autoClaim":milestone.auto_claim,"claimed":claim.is_some(),
                "autoClaimed":claim.map(|row|row.2).unwrap_or(false)})
        }).collect();
        json!({"eventId":e.event_id,"name":e.name,"startsAtMs":e.starts_at_ms,"endsAtMs":e.ends_at_ms,
            "points":score.map(|s|s.1).unwrap_or(0),"rewardClaimed":score.map(|s|s.2).unwrap_or(false),
            "milestones":milestones})
    }).collect();
    let season_rows: Vec<(String, i64, bool, Value, Value)> = sqlx::query_as(
        "SELECT season_id,points,premium,free_claimed,paid_claimed FROM season_progress WHERE address=$1",
    ).bind(&address).fetch_all(state.db.pool()).await?;
    let seasons: Vec<Value> = state.config.seasons.iter().map(|s| {
        let row = season_rows.iter().find(|(id,_,_,_,_)| id == &s.season_id);
        json!({"seasonId":s.season_id,"name":s.name,"startsAtMs":s.starts_at_ms,"endsAtMs":s.ends_at_ms,
            "points":row.map(|r|r.1).unwrap_or(0),"premium":row.map(|r|r.2).unwrap_or(false),
            "freeClaimed":row.map(|r|r.3.clone()).unwrap_or_else(||json!([])),"paidClaimed":row.map(|r|r.4.clone()).unwrap_or_else(||json!([]))})
    }).collect();

    Ok(Json(json!({
        "address": address,
        "spins": spins,
        "credits": row.credits,
        "lastSpinAtMs": row.last_spin_at.map(|t| t.timestamp_millis()),
        "nextSpinAtMs": next_spin_at,
        "districtIndex": row.district_index,
        "dailyStreak": row.daily_streak,
        "lastDailyClaim": row.last_daily_claim.map(|d| d.format("%Y-%m-%d").to_string()),
        "adsWatchedToday": row.ads_watched_today,
        "adsClaimedDate": row.ads_claimed_date.map(|d| d.format("%Y-%m-%d").to_string()),
        // Vides en M1 — remplis en M2 (districts) / M3 (coffres) / M4 (événements).
        "districtProgress": district_progress.into_iter().map(|(district_id,element_id,level)| json!({"districtId":district_id,"elementId":element_id,"level":level})).collect::<Vec<_>>(),
        "cards": cards,
        "chests": chests,
        "completedSets": completed_sets,
        "dailyAvailable": row.last_daily_claim != Some(today),
        "missions": missions,
        "events": events,
        "seasons": seasons,
        "configVersion": state.config.version,
        // Horloge serveur — le client en dérive son offset clock-skew (regen/countdowns).
        "serverTimeMs": now.timestamp_millis(),
    })))
}

#[derive(Deserialize)]
struct AnalyticsBody {
    events: Vec<AnalyticsEvent>,
}

#[derive(Deserialize)]
struct AnalyticsEvent {
    name: String,
    #[serde(default)]
    props: Option<Value>,
}

/// `POST /analytics` — ingestion batch (≤ 100 événements, ARCH §4.1).
/// Horloge SERVEUR (jamais l'horloge client — GDD §39).
async fn analytics(
    State(state): State<AppState>,
    Extension(addr): Extension<auth::Addr>,
    Json(body): Json<AnalyticsBody>,
) -> Result<Json<Value>, ApiError> {
    if body.events.is_empty() {
        return Ok(Json(json!({ "accepted": 0 })));
    }
    if body.events.len() > 100 {
        return Err(ApiError::BadRequest("max 100 events par batch".to_string()));
    }
    for e in &body.events {
        let valid = !e.name.is_empty()
            && e.name.len() <= 64
            && e.name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | ':'));
        if !valid {
            return Err(ApiError::BadRequest(format!(
                "nom d'événement invalide : {}",
                e.name
            )));
        }
    }
    let mut tx = state.db.begin().await?;
    for e in &body.events {
        let props = e.props.clone().unwrap_or_else(|| json!({}));
        sqlx::query(
            "INSERT INTO analytics_events (address, name, props, ts) VALUES ($1, $2, $3, now())",
        )
        .bind(&addr.0)
        .bind(&e.name)
        .bind(&props)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(Json(json!({ "accepted": body.events.len() })))
}
