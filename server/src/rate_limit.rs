//! Rate limiting — fenêtre fixe, en mémoire (M1).
//!
//! M4 : passage à Redis (partagé entre instances) — ARCH §1 / §4.2.
//! La clé est l'adresse wallet sur les routes protégées, l'IP sur `/auth/*`.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Clone)]
pub struct RateLimiter {
    window: Duration,
    max: u32,
    hits: Arc<Mutex<HashMap<String, (Instant, u32)>>>,
}

impl RateLimiter {
    pub fn new(window: Duration, max: u32) -> Self {
        Self {
            window,
            max,
            hits: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// `true` si la requête est autorisée.
    pub fn check(&self, key: &str) -> bool {
        let now = Instant::now();
        let mut map = self
            .hits
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        // Nettoyage opportuniste pour éviter la croissance infinie.
        if map.len() > 10_000 {
            map.retain(|_, (start, _)| now.duration_since(*start) < self.window);
        }
        let entry = map.entry(key.to_string()).or_insert_with(|| (now, 0));
        if now.duration_since(entry.0) >= self.window {
            *entry = (now, 1);
            return true;
        }
        if entry.1 >= self.max {
            return false;
        }
        entry.1 += 1;
        true
    }
}
