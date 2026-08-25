-- Garde-fous partagés entre toutes les instances du serveur.
-- Les nonces restent opaques et éphémères ; leur consommation est atomique.

CREATE TABLE auth_nonces (
    address     TEXT PRIMARY KEY CHECK (char_length(address) BETWEEN 1 AND 128),
    nonce       TEXT NOT NULL CHECK (char_length(nonce) = 64),
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX auth_nonces_expiry ON auth_nonces(expires_at);

-- Une ligne par identité de limitation. La fenêtre fixe est remise à zéro
-- atomiquement par l'UPSERT ; aucun état local n'est nécessaire.
CREATE TABLE api_rate_limits (
    client_key         TEXT PRIMARY KEY CHECK (char_length(client_key) BETWEEN 1 AND 160),
    window_started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    request_count      INTEGER NOT NULL DEFAULT 1 CHECK (request_count >= 1),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX api_rate_limits_updated_at ON api_rate_limits(updated_at);
