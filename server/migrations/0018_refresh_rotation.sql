-- Rotation des refresh tokens partagée entre instances. Le JWT complet n'est
-- jamais stocké ; seul le hash SHA-256 de son identifiant aléatoire est conservé.

CREATE TABLE refresh_sessions (
    jti_hash          TEXT PRIMARY KEY CHECK (char_length(jti_hash) = 64),
    address           TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    expires_at        TIMESTAMPTZ NOT NULL,
    consumed_at       TIMESTAMPTZ,
    replaced_by_hash  TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (replaced_by_hash IS NULL OR char_length(replaced_by_hash) = 64)
);
CREATE INDEX refresh_sessions_player_active
    ON refresh_sessions(address, expires_at) WHERE consumed_at IS NULL;
CREATE INDEX refresh_sessions_expiry ON refresh_sessions(expires_at);
