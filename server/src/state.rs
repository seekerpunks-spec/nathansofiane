//! État applicatif partagé (cloné à travers les handlers via `Arc`).

use crate::config::RemoteConfig;
use crate::db::Db;
use crate::rate_limit::RateLimiter;
use std::sync::Arc;
use std::time::Instant;

#[derive(Clone)]
pub struct AppState {
    pub db: Db,
    /// Remote config versionnée (hash SHA-256, validée au boot).
    pub config: Arc<RemoteConfig>,
    pub jwt_secret: String,
    /// Domaine inclus dans le message signé afin qu'un challenge obtenu sur un
    /// autre service ne puisse pas être relayé vers CyberSeeker.
    pub auth_domain: String,
    /// DEV (à NE JAMAIS activer en production) : accepte la signature "dev".
    pub dev_auth: bool,
    pub dev_address: Option<String>,
    pub rate: Arc<RateLimiter>,
    pub started_at: Instant,
}
