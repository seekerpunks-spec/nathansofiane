//! Pool Postgres + accès à l'état joueur (une ligne par joueur, mise à jour
//! transactionnelle). Le serveur est la source de vérité : tout passe ici.

use anyhow::{anyhow, Result};
use chrono::{DateTime, NaiveDate, Utc};
use serde_json::{json, Value};
use sqlx::postgres::{PgPool, PgPoolOptions};
use sqlx::{Postgres, Transaction};

#[derive(Debug, Clone)]
pub struct Db {
    pool: PgPool,
}

/// Ligne `player_state` (état complet du joueur).
#[derive(Debug, sqlx::FromRow)]
pub struct StateRow {
    pub spins: i32,
    pub credits: i64,
    pub last_spin_at: Option<DateTime<Utc>>,
    pub district_index: i32,
    pub daily_streak: i32,
    pub last_daily_claim: Option<NaiveDate>,
    pub ads_watched_today: i32,
    pub ads_claimed_date: Option<NaiveDate>,
    pub firewall_charges: i32,
}

const STATE_SELECT: &str = "SELECT spins, credits, last_spin_at, district_index, daily_streak, \
                            last_daily_claim, ads_watched_today, ads_claimed_date, firewall_charges \
                            FROM player_state WHERE address = $1";

impl Db {
    /// Connexion + migrations automatiques (embarquées via `migrate!`).
    pub async fn connect(database_url: &str) -> Result<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(16)
            .acquire_timeout(std::time::Duration::from_secs(10))
            .connect(database_url)
            .await
            .map_err(|e| anyhow!("connexion Postgres impossible : {}", e))?;
        // Les migrations embarquées, immuables après application, incluent la
        // cascade complète nécessaire à l'effacement transactionnel d'un compte.
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .map_err(|e| anyhow!("migrations SQL échouées : {}", e))?;
        Ok(Self { pool })
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    /// Une session consommée par rotation/logout garde son access JWT jusqu'à
    /// son expiration courte. L'effacement du compte détruit toutes les sessions.
    pub async fn access_session_exists(&self, address: &str, jti_hash: &str) -> Result<bool> {
        Ok(
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM refresh_sessions WHERE address=$1 AND jti_hash=$2 AND expires_at>=now())")
                .bind(address)
                .bind(jti_hash)
                .fetch_one(&self.pool)
                .await?,
        )
    }

    /// Nouvelle transaction (commit/rollback par l'appelant).
    pub async fn begin(&self) -> Result<Transaction<'_, Postgres>> {
        Ok(self.pool.begin().await?)
    }

    /// Crée un challenge ou renvoie celui qui est encore valide. PostgreSQL est
    /// la source partagée entre instances. Un appel public répété ne doit pas
    /// écraser le nonce qu'un wallet est précisément en train de signer.
    pub async fn store_auth_nonce(
        &self,
        address: &str,
        nonce: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<(String, DateTime<Utc>)> {
        let stored = sqlx::query_as(
            "INSERT INTO auth_nonces(address,nonce,expires_at) VALUES($1,$2,$3) \
             ON CONFLICT(address) DO UPDATE SET \
             nonce=CASE WHEN auth_nonces.expires_at<now() THEN EXCLUDED.nonce ELSE auth_nonces.nonce END, \
             expires_at=CASE WHEN auth_nonces.expires_at<now() THEN EXCLUDED.expires_at ELSE auth_nonces.expires_at END, \
             created_at=CASE WHEN auth_nonces.expires_at<now() THEN now() ELSE auth_nonces.created_at END \
             RETURNING nonce,expires_at",
        )
        .bind(address)
        .bind(nonce)
        .bind(expires_at)
        .fetch_one(&self.pool)
        .await?;
        Ok(stored)
    }

    pub async fn peek_auth_nonce(&self, address: &str) -> Result<Option<String>> {
        Ok(sqlx::query_scalar(
            "SELECT nonce FROM auth_nonces WHERE address=$1 AND expires_at>=now()",
        )
        .bind(address)
        .fetch_optional(&self.pool)
        .await?)
    }

    /// Comparaison/consommation atomique après vérification de signature.
    pub async fn consume_auth_nonce(&self, address: &str, nonce: &str) -> Result<bool> {
        let row: Option<String> = sqlx::query_scalar(
            "DELETE FROM auth_nonces WHERE address=$1 AND nonce=$2 AND expires_at>=now() RETURNING nonce",
        )
        .bind(address)
        .bind(nonce)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.is_some())
    }

    pub async fn store_refresh_session(
        &self,
        address: &str,
        jti_hash: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<()> {
        sqlx::query("INSERT INTO refresh_sessions(jti_hash,address,expires_at) VALUES($1,$2,$3)")
            .bind(jti_hash)
            .bind(address)
            .bind(expires_at)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Consomme l'ancien refresh et crée son remplaçant dans la même
    /// transaction. Deux instances concurrentes ne peuvent obtenir qu'un succès.
    pub async fn rotate_refresh_session(
        &self,
        address: &str,
        old_jti_hash: &str,
        new_jti_hash: &str,
        new_expires_at: DateTime<Utc>,
    ) -> Result<bool> {
        let mut tx = self.pool.begin().await?;
        let consumed = sqlx::query(
            "UPDATE refresh_sessions SET consumed_at=now(),replaced_by_hash=$1 \
             WHERE jti_hash=$2 AND address=$3 AND consumed_at IS NULL AND expires_at>=now()",
        )
        .bind(new_jti_hash)
        .bind(old_jti_hash)
        .bind(address)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if consumed == 0 {
            tx.rollback().await?;
            return Ok(false);
        }
        sqlx::query("INSERT INTO refresh_sessions(jti_hash,address,expires_at) VALUES($1,$2,$3)")
            .bind(new_jti_hash)
            .bind(address)
            .bind(new_expires_at)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(true)
    }

    /// Révoque une session refresh précise. L'opération est idempotente :
    /// `false` signifie que le jeton était déjà consommé ou expiré.
    pub async fn revoke_refresh_session(&self, address: &str, jti_hash: &str) -> Result<bool> {
        let revoked = sqlx::query(
            "UPDATE refresh_sessions SET consumed_at=now() \
             WHERE jti_hash=$1 AND address=$2 AND consumed_at IS NULL AND expires_at>=now()",
        )
        .bind(jti_hash)
        .bind(address)
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(revoked == 1)
    }

    /// Crée le joueur s'il est nouveau (spins de bienvenue + `last_spin_at = now`).
    /// Renvoie `true` si le joueur vient d'être créé. Les deux écritures sont
    /// atomiques : pas de joueur sans ligne d'état.
    pub async fn ensure_player(&self, address: &str, new_player_spins: i32) -> Result<bool> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,4))")
            .bind(address)
            .execute(&mut *tx)
            .await?;
        let inserted = sqlx::query(
            "INSERT INTO players (address) VALUES ($1) ON CONFLICT (address) DO NOTHING",
        )
        .bind(address)
        .execute(&mut *tx)
        .await?
        .rows_affected();

        if inserted == 1 {
            sqlx::query(
                "INSERT INTO player_state (address, spins, last_spin_at) VALUES ($1, $2, now())",
            )
            .bind(address)
            .bind(new_player_spins)
            .execute(&mut *tx)
            .await?;
            tracing::info!(address, new_player_spins, "nouveau joueur créé");
        } else {
            sqlx::query(
                "UPDATE players SET previous_seen_at=last_seen_at,last_seen_at=now() WHERE address=$1",
            )
                .bind(address)
                .execute(&mut *tx)
                .await?;
        }
        sqlx::query(
            "INSERT INTO player_profiles(address,display_name,friend_code) \
             VALUES($1,'Runner-' || upper(substr(md5($1),1,4)),'CYB-' || upper(substr(md5($1),1,12))) \
             ON CONFLICT(address) DO NOTHING",
        )
        .bind(address)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO progression_scores(address) VALUES($1) ON CONFLICT(address) DO NOTHING",
        )
        .bind(address)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(inserted == 1)
    }

    /// État simple (lecture seule, pas de verrou).
    pub async fn fetch_state(&self, address: &str) -> Result<Option<StateRow>> {
        let row: Option<StateRow> = sqlx::query_as::<Postgres, StateRow>(STATE_SELECT)
            .bind(address)
            .fetch_optional(&self.pool)
            .await?;
        Ok(row)
    }

    /// État verrouillé (`FOR UPDATE`) — à appeler DANS une transaction.
    pub async fn fetch_state_locked<'e>(
        &self,
        tx: &mut Transaction<'e, Postgres>,
        address: &str,
    ) -> Result<Option<StateRow>> {
        let row: Option<StateRow> =
            sqlx::query_as::<Postgres, StateRow>(&format!("{STATE_SELECT} FOR UPDATE"))
                .bind(address)
                .fetch_optional(&mut **tx)
                .await?;
        Ok(row)
    }

    /// Ligne d'audit économie (dans la transaction en cours).
    pub async fn audit_tx(
        tx: &mut Transaction<'_, Postgres>,
        address: &str,
        action: &str,
        before: &Value,
        after: &Value,
        request_id: Option<&str>,
    ) -> Result<()> {
        sqlx::query(
            "INSERT INTO economy_audit (address, action, before, after, request_id) \
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(address)
        .bind(action)
        .bind(before)
        .bind(after)
        .bind(request_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    /// Idempotence — lecture (hors transaction, fast path).
    pub async fn fetch_idempotent(&self, key: &str) -> Result<Option<Value>> {
        let row: Option<(Value,)> =
            sqlx::query_as("SELECT response FROM idempotency WHERE key = $1")
                .bind(key)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|r| r.0))
    }

    /// Idempotence — lecture (dans la transaction, après le verrou ligne).
    pub async fn fetch_idempotent_locked<'e>(
        &self,
        tx: &mut Transaction<'e, Postgres>,
        key: &str,
    ) -> Result<Option<Value>> {
        let row: Option<(Value,)> =
            sqlx::query_as("SELECT response FROM idempotency WHERE key = $1")
                .bind(key)
                .fetch_optional(&mut **tx)
                .await?;
        Ok(row.map(|r| r.0))
    }

    /// Idempotence — écriture (dans la transaction qui fait la mutation).
    pub async fn store_idempotent(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        key: &str,
        response: &Value,
    ) -> Result<()> {
        sqlx::query("INSERT INTO idempotency (key, response) VALUES ($1, $2)")
            .bind(key)
            .bind(response)
            .execute(&mut **tx)
            .await?;
        Ok(())
    }

    /// Cartes possédées (vide en M1, rempli en M3).
    pub async fn fetch_cards(&self, address: &str) -> Result<Vec<Value>> {
        let rows: Vec<(String, i64)> = sqlx::query_as(
            "SELECT card_id, qty FROM player_cards WHERE address = $1 ORDER BY card_id",
        )
        .bind(address)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|(card_id, qty)| json!({ "cardId": card_id, "qty": qty }))
            .collect())
    }

    /// Coffres possédés non ouverts (vide en M1, rempli en M3).
    pub async fn fetch_chests(&self, address: &str) -> Result<Vec<Value>> {
        let rows: Vec<(String, i64)> = sqlx::query_as(
            "SELECT chest_id, qty FROM player_chests WHERE address = $1 AND qty > 0 \
             ORDER BY chest_id",
        )
        .bind(address)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|(chest_id, qty)| json!({ "chestId": chest_id, "qty": qty }))
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, Utc};

    #[tokio::test]
    async fn postgres_nonce_is_shared_single_use_and_expires() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_nonce_is_shared_single_use_and_expires").await
        else {
            return Ok(());
        };
        let address = format!("nonce-test-{}", uuid::Uuid::new_v4());
        let nonce = "a".repeat(64);
        let first_expiry = Utc::now() + Duration::minutes(1);
        let stored = db.store_auth_nonce(&address, &nonce, first_expiry).await?;
        assert_eq!(stored.0, nonce);

        // Un second appel public pendant que le wallet signe ne doit jamais
        // invalider le premier challenge.
        let replacement = "b".repeat(64);
        let repeated = db
            .store_auth_nonce(&address, &replacement, Utc::now() + Duration::minutes(1))
            .await?;
        assert_eq!(repeated.0, nonce);
        assert_eq!(repeated.1, stored.1);

        let first_db = db.clone();
        let second_db = db.clone();
        let first_address = address.clone();
        let second_address = address.clone();
        assert!(!db.consume_auth_nonce(&address, "wrong-proof").await?);
        assert_eq!(
            db.peek_auth_nonce(&address).await?.as_deref(),
            Some(nonce.as_str())
        );
        let first_nonce = nonce.clone();
        let second_nonce = nonce.clone();
        let (first, second) = tokio::join!(
            async move {
                first_db
                    .consume_auth_nonce(&first_address, &first_nonce)
                    .await
            },
            async move {
                second_db
                    .consume_auth_nonce(&second_address, &second_nonce)
                    .await
            }
        );
        let consumed = [first?, second?];
        assert_eq!(consumed.iter().filter(|value| **value).count(), 1);

        db.store_auth_nonce(&address, &nonce, Utc::now() + Duration::minutes(1))
            .await?;
        // Représente un vrai challenge créé puis expiré, sans violer l'ordre
        // temporel protégé par la migration 0019.
        sqlx::query(
            "UPDATE auth_nonces SET created_at=now()-interval '2 minutes', \
             expires_at=now()-interval '1 minute' WHERE address=$1",
        )
        .bind(&address)
        .execute(db.pool())
        .await?;
        assert!(db.peek_auth_nonce(&address).await?.is_none());
        assert!(!db.consume_auth_nonce(&address, &nonce).await?);
        Ok(())
    }

    #[tokio::test]
    async fn postgres_refresh_rotation_has_one_concurrent_winner() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_refresh_rotation_has_one_concurrent_winner").await
        else {
            return Ok(());
        };
        let address = format!("refresh-test-{}", uuid::Uuid::new_v4());
        db.ensure_player(&address, 1).await?;
        let old = uuid::Uuid::new_v4().simple().to_string().repeat(2);
        let first_new = uuid::Uuid::new_v4().simple().to_string().repeat(2);
        let second_new = uuid::Uuid::new_v4().simple().to_string().repeat(2);
        let expiry = Utc::now() + Duration::days(1);
        db.store_refresh_session(&address, &old, expiry).await?;

        let first_db = db.clone();
        let second_db = db.clone();
        let first_address = address.clone();
        let second_address = address.clone();
        let old_first = old.clone();
        let old_second = old.clone();
        let (first, second) = tokio::join!(
            async move {
                first_db
                    .rotate_refresh_session(&first_address, &old_first, &first_new, expiry)
                    .await
            },
            async move {
                second_db
                    .rotate_refresh_session(&second_address, &old_second, &second_new, expiry)
                    .await
            }
        );
        assert_eq!([first?, second?].into_iter().filter(|won| *won).count(), 1);
        let active: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM refresh_sessions WHERE address=$1 AND consumed_at IS NULL",
        )
        .bind(&address)
        .fetch_one(db.pool())
        .await?;
        assert_eq!(active, 1);

        let active_hash: String = sqlx::query_scalar(
            "SELECT jti_hash FROM refresh_sessions WHERE address=$1 AND consumed_at IS NULL",
        )
        .bind(&address)
        .fetch_one(db.pool())
        .await?;
        assert!(db.revoke_refresh_session(&address, &active_hash).await?);
        assert!(!db.revoke_refresh_session(&address, &active_hash).await?);
        let active_after_logout: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM refresh_sessions WHERE address=$1 AND consumed_at IS NULL",
        )
        .bind(&address)
        .fetch_one(db.pool())
        .await?;
        assert_eq!(active_after_logout, 0);

        sqlx::query("DELETE FROM player_state WHERE address=$1")
            .bind(&address)
            .execute(db.pool())
            .await?;
        sqlx::query("DELETE FROM players WHERE address=$1")
            .bind(&address)
            .execute(db.pool())
            .await?;
        Ok(())
    }

    #[tokio::test]
    async fn postgres_rejects_self_target_and_two_team_owners() -> anyhow::Result<()> {
        let Some(db) =
            crate::testdb::connect("postgres_rejects_self_target_and_two_team_owners").await
        else {
            return Ok(());
        };
        let first = format!("invariant-a-{}", uuid::Uuid::new_v4());
        let second = format!("invariant-b-{}", uuid::Uuid::new_v4());
        db.ensure_player(&first, 1).await?;
        db.ensure_player(&second, 1).await?;

        let mut encounter_tx = db.begin().await?;
        let self_target = sqlx::query(
            "INSERT INTO social_encounters(encounter_id,attacker,target,kind,multiplier,expires_at) \
             VALUES($1,$2,$2,'attack',1,$3)",
        )
        .bind(uuid::Uuid::new_v4().to_string())
        .bind(&first)
        .bind(Utc::now() + Duration::minutes(1))
        .execute(&mut *encounter_tx)
        .await;
        assert!(self_target.is_err());
        encounter_tx.rollback().await?;

        let mut team_tx = db.begin().await?;
        let team_id = uuid::Uuid::new_v4().to_string();
        let team_code = format!("QA-{}", &uuid::Uuid::new_v4().simple().to_string()[..12]);
        let team_name = format!("QA {}", &uuid::Uuid::new_v4().simple().to_string()[..8]);
        sqlx::query("INSERT INTO teams(team_id,team_code,name,owner_address) VALUES($1,$2,$3,$4)")
            .bind(&team_id)
            .bind(&team_code)
            .bind(&team_name)
            .bind(&first)
            .execute(&mut *team_tx)
            .await?;
        sqlx::query("INSERT INTO team_members(team_id,address,role) VALUES($1,$2,'owner')")
            .bind(&team_id)
            .bind(&first)
            .execute(&mut *team_tx)
            .await?;
        let second_owner =
            sqlx::query("INSERT INTO team_members(team_id,address,role) VALUES($1,$2,'owner')")
                .bind(&team_id)
                .bind(&second)
                .execute(&mut *team_tx)
                .await;
        assert!(second_owner.is_err());
        team_tx.rollback().await?;

        sqlx::query("DELETE FROM player_state WHERE address=$1 OR address=$2")
            .bind(&first)
            .bind(&second)
            .execute(db.pool())
            .await?;
        sqlx::query("DELETE FROM players WHERE address=$1 OR address=$2")
            .bind(&first)
            .bind(&second)
            .execute(db.pool())
            .await?;
        Ok(())
    }
}
