//! Rate limiting partagé dans PostgreSQL.
//!
//! La mise à jour est un UPSERT atomique basé sur l'horloge de la base. Deux
//! instances serveur appliquent donc la même fenêtre et le même quota.

use sqlx::PgPool;
use std::time::Duration;

#[derive(Clone)]
pub struct RateLimiter {
    pool: PgPool,
    window_seconds: i32,
    max: i32,
}

impl RateLimiter {
    pub fn new(pool: PgPool, window: Duration, max: u32) -> Self {
        let window_seconds = i32::try_from(window.as_secs()).unwrap_or(i32::MAX).max(1);
        let max = i32::try_from(max)
            .unwrap_or(i32::MAX - 1)
            .clamp(1, i32::MAX - 1);
        Self {
            pool,
            window_seconds,
            max,
        }
    }

    /// `true` si la requête est autorisée. Les requêtes refusées saturent le
    /// compteur à `max + 1`, ce qui évite tout overflow sous attaque soutenue.
    pub async fn check(&self, key: &str) -> Result<bool, sqlx::Error> {
        let count: i32 = sqlx::query_scalar(
            "INSERT INTO api_rate_limits(client_key,window_started_at,request_count,updated_at) \
             VALUES($1,statement_timestamp(),1,statement_timestamp()) \
             ON CONFLICT(client_key) DO UPDATE SET \
               window_started_at=CASE \
                 WHEN api_rate_limits.window_started_at <= statement_timestamp() - make_interval(secs => $2) \
                 THEN statement_timestamp() ELSE api_rate_limits.window_started_at END, \
               request_count=CASE \
                 WHEN api_rate_limits.window_started_at <= statement_timestamp() - make_interval(secs => $2) \
                 THEN 1 ELSE LEAST(api_rate_limits.request_count + 1,$3) END, \
               updated_at=statement_timestamp() \
             RETURNING request_count",
        )
        .bind(key)
        .bind(self.window_seconds)
        .bind(self.max + 1)
        .fetch_one(&self.pool)
        .await?;
        Ok(count <= self.max)
    }
}

#[cfg(test)]
mod tests {
    use super::RateLimiter;
    use std::time::Duration;

    #[tokio::test]
    async fn postgres_instances_share_the_same_limit() -> anyhow::Result<()> {
        let Ok(database_url) = std::env::var("CYBERSEEKER_TEST_DATABASE_URL") else {
            return Ok(());
        };
        let db = crate::db::Db::connect(&database_url).await?;
        let first = RateLimiter::new(db.pool().clone(), Duration::from_secs(60), 2);
        let second = RateLimiter::new(db.pool().clone(), Duration::from_secs(60), 2);
        let key = format!("test:{}", uuid::Uuid::new_v4());

        assert!(first.check(&key).await?);
        assert!(second.check(&key).await?);
        assert!(!first.check(&key).await?);

        sqlx::query("DELETE FROM api_rate_limits WHERE client_key=$1")
            .bind(&key)
            .execute(db.pool())
            .await?;
        Ok(())
    }
}
