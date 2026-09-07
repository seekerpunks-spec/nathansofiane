//! Auth wallet (Solana Ed25519) + JWT.
//!
//! Flow réel (`DEV_AUTH=false`) :
//!   1. `POST /auth/challenge { address }` → `{ nonce, expiresAt }`
//!   2. Le wallet signe les octets UTF-8 du message retourné (Ed25519)
//!   3. `POST /auth/verify { address, signature }` → `{ token, refreshToken, isNewPlayer }`
//!      - `address`   = base58 de la clé publique Ed25519 32 octets (convention Solana)
//!      - `signature` = base64 de la signature
//!
//! Flow dev (`DEV_AUTH=true`, à NE JAMAIS activer en production) :
//!   la signature littérale `"dev"` est acceptée pour `DEV_ADDRESS`.
//!
//! JWT : HS256 — access 15 min + refresh 30 jours (`POST /auth/refresh`).
//! La déconnexion révoque le refresh courant (`POST /auth/logout`).
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
use sha2::{Digest, Sha256};
use std::time::Duration;

const NONCE_TTL: Duration = Duration::from_secs(120);
const ACCESS_TTL: Duration = Duration::from_secs(15 * 60);
const REFRESH_TTL: Duration = Duration::from_secs(30 * 24 * 3600);

fn sign_in_message(domain: &str, address: &str, nonce: &str) -> String {
    format!("CyberSeeker authentication\nDomain: {domain}\nAddress: {address}\nNonce: {nonce}")
}

/// Injection du middleware `guard` (main.rs) : adresse du joueur authentifié.
#[derive(Clone)]
pub struct Addr(pub String);

#[derive(Serialize, Deserialize)]
struct Claims {
    sub: String,
    typ: String,
    iat: i64,
    exp: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    jti: Option<String>,
}

fn make_token(
    secret: &str,
    address: &str,
    typ: &str,
    ttl: Duration,
    jti: Option<&str>,
) -> Result<String, AuthError> {
    let now = Utc::now().timestamp();
    let claims = Claims {
        sub: address.to_string(),
        typ: typ.to_string(),
        iat: now,
        exp: now + ttl.as_secs() as i64,
        jti: jti.map(str::to_string),
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

fn hash_jti(jti: &str) -> String {
    let digest = Sha256::digest(jti.as_bytes());
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

async fn issue_initial_tokens(
    state: &AppState,
    address: &str,
) -> Result<(String, String), crate::error::ApiError> {
    let jti = uuid::Uuid::new_v4().to_string();
    let token = make_token(&state.jwt_secret, address, "access", ACCESS_TTL, Some(&jti))?;
    let refresh_token = make_token(
        &state.jwt_secret,
        address,
        "refresh",
        REFRESH_TTL,
        Some(&jti),
    )?;
    let expires_at = Utc::now()
        + chrono::Duration::from_std(REFRESH_TTL)
            .map_err(|error| crate::error::ApiError::Internal(error.into()))?;
    state
        .db
        .store_refresh_session(address, &hash_jti(&jti), expires_at)
        .await?;
    Ok((token, refresh_token))
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
    auth_session(state, headers).map(|(address, _)| address)
}

/// Identité et session de connexion : la signature seule ne suffit pas après
/// suppression puis recréation d'un compte avec la même adresse.
pub fn auth_session(
    state: &AppState,
    headers: &HeaderMap,
) -> Result<(String, String), crate::error::ApiError> {
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
    let jti = claims.jti.ok_or(ApiError::from(AuthError::InvalidToken))?;
    Ok((claims.sub, hash_jti(&jti)))
}

fn normalize_address(raw: &str, state: &AppState) -> Result<String, crate::error::ApiError> {
    use crate::error::ApiError;
    // Une adresse Solana est en Base58 et donc sensible à la casse. Ne jamais
    // la normaliser en minuscules : cela change la clé publique signataire.
    let a = raw.trim().to_string();
    if a.is_empty() {
        return Err(ApiError::BadRequest("address est requis".into()));
    }
    if state.dev_auth {
        // Dev : identifiant court libre (ex. dev-player-0001).
        if a.len() > 64 {
            return Err(ApiError::BadRequest("address trop long".into()));
        }
        if state.dev_address.as_deref().map(str::trim) != Some(a.as_str()) {
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
    let mut bytes = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let nonce: String = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
    let expires_at = Utc::now()
        + chrono::Duration::from_std(NONCE_TTL)
            .map_err(|error| crate::error::ApiError::Internal(error.into()))?;
    let (nonce, expires_at) = state
        .db
        .store_auth_nonce(&address, &nonce, expires_at)
        .await?;
    let message = sign_in_message(&state.auth_domain, &address, &nonce);
    Ok(Json(json!({
        "nonce": nonce,
        "message": message,
        // Compatibilité du contrat v1 en secondes + forme explicite v2 en ms.
        "expiresAt": expires_at.timestamp(),
        "expiresAtMs": expires_at.timestamp_millis(),
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
        .db
        .peek_auth_nonce(&address)
        .await?
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
        // Message signé v2 : domaine + adresse + nonce. Le domaine empêche le
        // relay d'un challenge signé pour une autre application.
        let message = sign_in_message(&state.auth_domain, &address, &nonce);
        vk.verify(message.as_bytes(), &sig)
            .map_err(|_| AuthError::InvalidSignature)?;
    }

    // Ne consommer qu'après validation, avec comparaison atomique du nonce.
    // Une preuve invalide ne doit pas invalider le challenge du vrai joueur.
    if !state.db.consume_auth_nonce(&address, &nonce).await? {
        return Err(ApiError::from(AuthError::InvalidNonce));
    }
    let is_new = state
        .db
        .ensure_player(&address, state.config.economy.new_player_spins as i32)
        .await?;
    let (token, refresh_token) = issue_initial_tokens(&state, &address).await?;
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
    let old_jti = claims
        .jti
        .as_deref()
        .ok_or(ApiError::from(AuthError::InvalidToken))?;
    let new_jti = uuid::Uuid::new_v4().to_string();
    let token = make_token(
        &state.jwt_secret,
        &claims.sub,
        "access",
        ACCESS_TTL,
        Some(&new_jti),
    )?;
    let refresh_token = make_token(
        &state.jwt_secret,
        &claims.sub,
        "refresh",
        REFRESH_TTL,
        Some(&new_jti),
    )?;
    let expires_at = Utc::now()
        + chrono::Duration::from_std(REFRESH_TTL)
            .map_err(|error| ApiError::Internal(error.into()))?;
    if !state
        .db
        .rotate_refresh_session(
            &claims.sub,
            &hash_jti(old_jti),
            &hash_jti(&new_jti),
            expires_at,
        )
        .await?
    {
        return Err(ApiError::from(AuthError::InvalidToken));
    }
    Ok(Json(json!({
        "token": token,
        "refreshToken": refresh_token,
    })))
}

/// `POST /auth/logout` — révoque le refresh courant. Un second appel avec le
/// même JWT signé reste un succès idempotent et n'expose aucune autre session.
pub async fn logout(
    State(state): State<AppState>,
    Json(body): Json<RefreshReq>,
) -> Result<Json<Value>, crate::error::ApiError> {
    use crate::error::ApiError;
    let claims = decode_token(&state.jwt_secret, body.refresh_token.trim())?;
    if claims.typ != "refresh" {
        return Err(ApiError::from(AuthError::InvalidToken));
    }
    let jti = claims
        .jti
        .as_deref()
        .ok_or(ApiError::from(AuthError::InvalidToken))?;
    let revoked = state
        .db
        .revoke_refresh_session(&claims.sub, &hash_jti(jti))
        .await?;
    Ok(Json(json!({ "revoked": revoked })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn postgres_real_signature_is_single_use_and_invalid_proof_preserves_nonce(
    ) -> anyhow::Result<()> {
        use ed25519_dalek::{Signer, SigningKey};
        let Some(db) = crate::testdb::connect(
            "postgres_real_signature_is_single_use_and_invalid_proof_preserves_nonce",
        )
        .await
        else {
            return Ok(());
        };
        let config = crate::config::RemoteConfig::load(
            &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../config"),
        )?;
        let state = AppState {
            rate: std::sync::Arc::new(crate::rate_limit::RateLimiter::new(
                db.pool().clone(),
                Duration::from_secs(60),
                10_000,
            )),
            db: db.clone(),
            config: std::sync::Arc::new(config),
            jwt_secret: "test-secret-for-real-signature-and-session".into(),
            auth_domain: "qa.cyberseeker.local".into(),
            dev_auth: false,
            dev_address: None,
            started_at: std::time::Instant::now(),
        };
        let mut seed = [0u8; 32];
        rand::rngs::OsRng.fill_bytes(&mut seed);
        let key = SigningKey::from_bytes(&seed);
        let address = bs58::encode(key.verifying_key().as_bytes()).into_string();
        let challenge = challenge(
            State(state.clone()),
            Json(ChallengeReq {
                address: address.clone(),
            }),
        )
        .await?
        .0;
        let nonce = challenge["nonce"].as_str().unwrap();
        let forged = verify(
            State(state.clone()),
            Json(VerifyReq {
                address: address.clone(),
                signature: "invalid".into(),
            }),
        )
        .await;
        assert!(forged.is_err());
        assert_eq!(db.peek_auth_nonce(&address).await?.as_deref(), Some(nonce));
        let signature = base64::engine::general_purpose::STANDARD.encode(
            key.sign(challenge["message"].as_str().unwrap().as_bytes())
                .to_bytes(),
        );
        let login = || {
            verify(
                State(state.clone()),
                Json(VerifyReq {
                    address: address.clone(),
                    signature: signature.clone(),
                }),
            )
        };
        let (first, second) = tokio::join!(login(), login());
        assert_ne!(first.is_ok(), second.is_ok());
        let response = first.or(second)?.0;
        let claims = decode_token(&state.jwt_secret, response["token"].as_str().unwrap())?;
        let session_hash = hash_jti(claims.jti.as_deref().unwrap());
        assert!(db.access_session_exists(&address, &session_hash).await?);
        crate::account::delete_account_data(
            db.pool(),
            &address,
            "real-signature-delete",
            Some(&session_hash),
        )
        .await?;
        db.ensure_player(&address, 0).await?;
        assert!(!db.access_session_exists(&address, &session_hash).await?);
        assert!(crate::account::delete_account_data(
            db.pool(),
            &address,
            "stale-new-request",
            Some(&session_hash)
        )
        .await
        .is_err());
        Ok(())
    }

    #[test]
    fn solana_base58_case_is_significant() {
        let address = bs58::encode([7u8; 32]).into_string();
        assert!(address.chars().any(|c| c.is_ascii_uppercase()));
        assert_ne!(address, address.to_lowercase());
        let decoded = bs58::decode(&address).into_vec().unwrap();
        assert_eq!(decoded, vec![7u8; 32]);
    }

    #[test]
    fn sign_in_message_is_bound_to_domain_address_and_nonce() {
        let message = sign_in_message("api.cyberseeker.game", "WalletABC", "nonce-123");
        assert!(message.contains("Domain: api.cyberseeker.game"));
        assert!(message.contains("Address: WalletABC"));
        assert!(message.contains("Nonce: nonce-123"));
        assert_ne!(
            message,
            sign_in_message("evil.example", "WalletABC", "nonce-123")
        );
    }
}
