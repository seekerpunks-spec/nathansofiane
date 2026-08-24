-- Cache d'entitlements vérifiés par un provider serveur futur. Aucun client ne
-- peut écrire ces lignes et tout droit expire automatiquement sans revalidation.

CREATE TABLE player_entitlements (
    address          TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    entitlement_id   TEXT NOT NULL,
    active           BOOLEAN NOT NULL DEFAULT false,
    verifier         TEXT NOT NULL CHECK (char_length(verifier) BETWEEN 1 AND 48),
    ownership_ref    TEXT NOT NULL CHECK (char_length(ownership_ref) BETWEEN 1 AND 160),
    verified_at      TIMESTAMPTZ NOT NULL,
    expires_at       TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (address, entitlement_id),
    CHECK (expires_at >= verified_at)
);
CREATE INDEX player_entitlements_active_expiry
    ON player_entitlements(address, expires_at)
    WHERE active=true;
