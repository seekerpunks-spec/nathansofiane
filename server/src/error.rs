//! Erreurs API — format de réponse uniforme : `{ "error": { "code", "message", ["details"] } }`.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("missing bearer token")]
    MissingToken,
    #[error("invalid token")]
    InvalidToken,
    #[error("invalid address")]
    InvalidAddress,
    #[error("invalid signature")]
    InvalidSignature,
    #[error("invalid or expired nonce")]
    InvalidNonce,
}

#[derive(Debug, Error)]
pub enum ApiError {
    #[error("{0}")]
    BadRequest(String),
    #[error("unauthorized")]
    Unauthorized(#[from] AuthError),
    #[error("not found")]
    NotFound,
    #[error("insufficient credits")]
    InsufficientCredits,
    #[error("reward already claimed")]
    AlreadyClaimed,
    #[error("resource unavailable")]
    Unavailable(String),
    #[error("no spins available")]
    NoSpins { next_spin_at_ms: Option<i64> },
    #[error("too many requests")]
    RateLimited,
    #[error("database error")]
    Db(#[from] sqlx::Error),
    #[error("internal server error")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code, message) = match &self {
            ApiError::BadRequest(m) => (StatusCode::BAD_REQUEST, "BAD_REQUEST", m.clone()),
            ApiError::Unauthorized(e) => (StatusCode::UNAUTHORIZED, "UNAUTHORIZED", e.to_string()),
            ApiError::NotFound => (
                StatusCode::NOT_FOUND,
                "NOT_FOUND",
                "resource not found".to_string(),
            ),
            ApiError::InsufficientCredits => (
                StatusCode::BAD_REQUEST,
                "INSUFFICIENT_CREDITS",
                "insufficient credits".to_string(),
            ),
            ApiError::AlreadyClaimed => (
                StatusCode::CONFLICT,
                "ALREADY_CLAIMED",
                "reward already claimed".to_string(),
            ),
            ApiError::Unavailable(message) => {
                (StatusCode::FORBIDDEN, "UNAVAILABLE", message.clone())
            }
            ApiError::NoSpins { .. } => (
                StatusCode::FORBIDDEN,
                "NO_SPINS",
                "no spins available".to_string(),
            ),
            ApiError::RateLimited => (
                StatusCode::TOO_MANY_REQUESTS,
                "RATE_LIMITED",
                "too many requests".to_string(),
            ),
            ApiError::Db(e) => {
                tracing::error!(error = ?e, "database error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "INTERNAL",
                    "internal server error".to_string(),
                )
            }
            ApiError::Internal(e) => {
                tracing::error!(error = ?e, "internal error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "INTERNAL",
                    "internal server error".to_string(),
                )
            }
        };

        let mut err = json!({ "code": code, "message": message });
        if let ApiError::NoSpins { next_spin_at_ms } = &self {
            err["details"] = json!({ "nextSpinAtMs": next_spin_at_ms });
        }

        let body = Json(json!({ "error": err }));
        (status, body).into_response()
    }
}
