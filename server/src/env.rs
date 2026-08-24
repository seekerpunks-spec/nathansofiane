//! Loader `.env` minimal (pas de dépendance ajoutée).
//!
//! Lit `KEY=VALUE` dans `.env` (CWD du processus = `server/`) si le fichier
//! existe. Ne JAMAIS écraser une variable déjà définie dans l'environnement
//! (le CI / le PaaS l'emporte toujours sur le `.env` local).

use std::fs;

pub fn load_dotenv() {
    let Ok(content) = fs::read_to_string(".env") else {
        return;
    };
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .to_string();
        if key.is_empty() {
            continue;
        }
        if std::env::var(key).is_err() {
            std::env::set_var(key, value);
        }
    }
}
