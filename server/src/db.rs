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
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .map_err(|e| anyhow!("migrations SQL échouées : {}", e))?;
        Ok(Self { pool })
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    /// Nouvelle transaction (commit/rollback par l'appelant).
    pub async fn begin(&self) -> Result<Transaction<'_, Postgres>> {
        Ok(self.pool.begin().await?)
    }

    /// Crée le joueur s'il est nouveau (spins de bienvenue + `last_spin_at = now`).
    /// Renvoie `true` si le joueur vient d'être créé. Les deux écritures sont
    /// atomiques : pas de joueur sans ligne d'état.
    pub async fn ensure_player(&self, address: &str, new_player_spins: i32) -> Result<bool> {
        let mut tx = self.pool.begin().await?;
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
