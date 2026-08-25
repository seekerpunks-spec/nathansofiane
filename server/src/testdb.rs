//! Support de test Postgres — fail-closed.
//!
//! Avant R26, chaque test DB sortait silencieusement en `Ok(())` quand
//! `CYBERSEEKER_TEST_DATABASE_URL` manquait : 8 tests « verts » en 0,00 s qui
//! ne prouvaient rien (même classe de bug que la gate sécurité vacueuse
//! réparée en R25). Ce helper inverse le défaut : sans URL, on PANIQUE avec la
//! marche à suivre. Le saut reste possible mais doit être explicite
//! (`CYBERSEEKER_ALLOW_DB_TEST_SKIP=1`) et s'imprime en clair.
//!
//! `tools/validate_all.ps1` compte les marqueurs `DB_TEST_RAN:` émis ici et
//! les compare au nombre d'appels du helper dans les sources : un test qui ne
//! s'exécute pas fait échouer la gate.

use crate::db::Db;

/// Connexion à la base de test (migrations incluses via `Db::connect`, donc
/// utilisable sur une base vierge quel que soit l'ordre des tests).
/// `None` uniquement en cas de saut explicitement demandé.
pub async fn connect(test_name: &str) -> Option<Db> {
    match std::env::var("CYBERSEEKER_TEST_DATABASE_URL") {
        Ok(url) => {
            let db = Db::connect(&url).await.unwrap_or_else(|error| {
                panic!("base de test injoignable ({test_name}) : {error}")
            });
            println!("DB_TEST_RAN: {test_name}");
            Some(db)
        }
        Err(_) if std::env::var("CYBERSEEKER_ALLOW_DB_TEST_SKIP").as_deref() == Ok("1") => {
            println!("DB_TEST_SKIPPED: {test_name}");
            None
        }
        Err(_) => panic!(
            "CYBERSEEKER_TEST_DATABASE_URL manquante pour {test_name}. \
             Créer une base dédiée (ex. `CREATE DATABASE cyberseeker_test`) puis exporter \
             CYBERSEEKER_TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/cyberseeker_test, \
             ou poser CYBERSEEKER_ALLOW_DB_TEST_SKIP=1 pour sauter explicitement les tests DB."
        ),
    }
}
