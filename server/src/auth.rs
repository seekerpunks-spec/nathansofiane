//! Auth wallet (Solana Ed25519) + JWT.
//!
//! Flow réel (`DEV_AUTH=false`) :
//!   1. `POST /auth/challenge { address }` → `{ nonce, expiresAt }`
//!   2. Le wallet signe les octets UTF-8 du nonce (Ed25519, signature 64 octets)
//!   3. `POST /auth/verify { address, signature }` → `{ token, refreshToken, isNewPlayer }`
//!      - `address`   = base58 de la clé publique Ed25519 32 octets (convention Solana)
//!      - `signature` = base64 de la signature
//!
//! Flow dev (`DEV_AUTH=true`, à NE JAMAIS activer en production) :
//!   la signature littérale `"dev"` est acceptée pour `DEV_ADDRESS`.
//!
//! JWT : HS256 — access 15 min + refresh 30 jours (`POST /auth/refresh`).
//! Nonces : single-use, TTL 120 s (anti-replay du pair address/signature).

use crate::error::AuthError;
use crate::state::AppState;
use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use base64::Engine;
use chrono::Utc;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

const NONCE_TTL: Duration = Duration::from_secs(120);
const ACCESS_TTL: Duration = Duration::from_secs(15 * 60);
const REFRESH_TTL: Duration = Duration::from_secs(30 * 24 * 3600);

/// Injection du middleware `guard` (main.rs) : adresse du joueur authentifié.
#[derive(Clone)]
pub struct Addr(pub String);

/// Un nonce par adresse (single-use, TTL).
#[derive(Default)]
pub struct NonceStore(Mutex<HashMap<String, (String, i64)>>);

impl NonceStore {
    /// Génère un nouveau nonce pour l'adresse (remplace l'existant).
    pub fn set(&self, address: &str) -> (String, i64) {
        let mut buf = [0u8; 32];
        rand::rngs::OsRng.fill_bytes(&mut buf);
        let nonce: String = buf.iter().map(|b| format!("{:02x}", b)).collect();
        let expires_at = Utc::now().timestamp() + NONCE_TTL.as_secs() as i64;
        let mut map = self
            .0
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if map.len() > 10_000 {
            let now = Utc::now().timestamp();
            map.retain(|_, (_, expires)| *expires >= now);
        }
        map.insert(address.to_string(), (nonce.clone(), expires_at));
        (nonce, expires_at)
    }

    /// Consomme le nonce (single-use). `None` si inconnu ou expiré.
    pub fn take(&self, address: &str) -> Option<String> {
        let mut map = self
            .0
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let entry = map.get(address)?;
        if Utc::now().timestamp() > entry.1 {
            map.remove(address);
            return None;
        }
        map.remove(address).map(|e| e.0)
    }
}

#[derive(Serialize, Deserialize)]
struct Claims {
    sub: String,
    typ: String,
    iat: i64,
    exp: i64,
}

fn make_token(secret: &str, address: &str, typ: &str, ttl: Duration) -> Result<String, AuthError> {
    let now = Utc::now().timestamp();
    let claims = Claims {
        sub: address.to_string(),
        typ: typ.to_string(),
        iat: now,
        exp: now + ttl.as_secs() as i64,
    };
    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| {
        tracing::error!(?e, "echec signature JWT");
        AuthError::InvalidToken
    })
}

fn decode_token(secret: &str, token: &str) -> Result<Claims, AuthError> {
    decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::new(Algorithm::HS256),
    )
    .map(|d| d.claims)
    .map_err(|_| AuthError::InvalidToken)
}

/// Extrait + valide le Bearer token → adresse du joueur.
pub fn auth_address(
    state: &AppState,
    headers: &HeaderMap,
) -> Result<String, crate::error::ApiError> {
    use crate::error::ApiError;
    let header = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or(ApiError::from(AuthError::MissingToken))?;
    let token = header
        .strip_prefix("Bearer ")
        .or_else(|| header.strip_prefix("bearer "))
        .ok_or(ApiError::from(AuthError::InvalidToken))?
        .trim();
    if token.is_empty() {
        return Err(ApiError::from(AuthError::InvalidToken));
    }
    let claims = decode_token(&state.jwt_secret, token)?;
    if claims.typ != "access" {
        return Err(ApiError::from(AuthError::InvalidToken));
    }
    Ok(claims.sub)
}

fn normalize_address(raw: &str, state: &AppState) -> Result<String, crate::error::ApiError> {
    use crate::error::ApiError;
    let a = raw.trim().to_lowercase();
    if a.is_empty() {
        return Err(ApiError::BadRequest("address est requis".into()));
    }
    if state.dev_auth {
        // Dev : identifiant court libre (ex. dev-player-0001).
        if a.len() > 64 {
            return Err(ApiError::BadRequest("address trop long".into()));
        }
        if state.dev_address.as_deref() != Some(a.as_str()) {
            return Err(ApiError::from(AuthError::InvalidAddress));
        }
        return Ok(a);
    }
    // Réel : adresse Solana = base58 d'une clé publique Ed25519 de 32 octets.
    let bytes = bs58::decode(&a)
        .into_vec()
        .map_err(|_| ApiError::from(AuthError::InvalidAddress))?;
    if bytes.len() != 32 {
        return Err(ApiError::from(AuthError::InvalidAddress));
    }
    Ok(a)
}

#[derive(Deserialize)]
pub struct ChallengeReq {
    address: String,
}

/// `POST /auth/challenge` — publique.
pub async fn challenge(
    State(state): State<AppState>,
    Json(body): Json<ChallengeReq>,
) -> Result<Json<Value>, crate::error::ApiError> {
    let address = normalize_address(&body.address, &state)?;
    let (nonce, expires_at) = state.nonce.set(&address);
    Ok(Json(json!({
        "nonce": nonce,
        "expiresAt": expires_at,
    })))
}

#[derive(Deserialize)]
pub struct VerifyReq {
    address: String,
    signature: String,
}

/// `POST /auth/verify` — publique. Crée le joueur au premier login.
pub async fn verify(
    State(state): State<AppState>,
    Json(body): Json<VerifyReq>,
) -> Result<Json<Value>, crate::error::ApiError> {
    use crate::error::ApiError;
    let address = normalize_address(&body.address, &state)?;
    // Nonce single-use : anti-replay du pair (address, signature).
    let nonce = state
        .nonce
        .take(&address)
        .ok_or(ApiError::from(AuthError::InvalidNonce))?;

    if state.dev_auth {
        // DEV MODE : signature littérale "dev" (aucune vérification Ed25519).
        if body.signature.trim() != "dev" {
            return Err(ApiError::from(AuthError::InvalidSignature));
        }
    } else {
        let sig_bytes = base64::engine::general_purpose::STANDARD
            .decode(body.signature.trim())
            .map_err(|_| AuthError::InvalidSignature)?;
        let sig = match sig_bytes.as_slice().try_into() {
            Ok(arr) => Signature::from_bytes(arr),
            Err(_) => return Err(ApiError::from(AuthError::InvalidSignature)),
        };
        let pk = bs58::decode(&address)
            .into_vec()
            .map_err(|_| AuthError::InvalidAddress)?;
        let pk_arr = match pk.as_slice().try_into() {
            Ok(arr) => arr,
            Err(_) => return Err(ApiError::from(AuthError::InvalidAddress)),
        };
        let vk = VerifyingKey::from_bytes(&pk_arr).map_err(|_| AuthError::InvalidAddress)?;
        // Message signé : le nonce en UTF-8 (format v1 — sera versionné à
        // l'intégration Seeker avec le vrai SDK wallet).
        vk.verify(nonce.as_bytes(), &sig)
            .map_err(|_| AuthError::InvalidSignature)?;
    }

    let is_new = state
        .db
        .ensure_player(&address, state.config.economy.new_player_spins as i32)
        .await?;
    let token = make_token(&state.jwt_secret, &address, "access", ACCESS_TTL)?;
    let refresh_token = make_token(&state.jwt_secret, &address, "refresh", REFRESH_TTL)?;
    Ok(Json(json!({
        "token": token,
        "refreshToken": refresh_token,
        "isNewPlayer": is_new,
        "address": address,
    })))
}

#[derive(Deserialize)]
pub struct RefreshReq {
    #[serde(rename = "refreshToken")]
    refresh_token: String,
}

/// `POST /auth/refresh` — échange un refresh token contre un nouveau pair.
pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshReq>,
) -> Result<Json<Value>, crate::error::ApiError> {
    use crate::error::ApiError;
    let claims = decode_token(&state.jwt_secret, body.refresh_token.trim())?;
    if claims.typ != "refresh" {
        return Err(ApiError::from(AuthError::InvalidToken));
    }
    let token = make_token(&state.jwt_secret, &claims.sub, "access", ACCESS_TTL)?;
    let refresh_token = make_token(&state.jwt_secret, &claims.sub, "refresh", REFRESH_TTL)?;
    Ok(Json(json!({
        "token": token,
        "refreshToken": refresh_token,
    })))
}
