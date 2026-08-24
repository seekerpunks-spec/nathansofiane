-- Achievements permanents data-driven et claims personnels idempotents.

CREATE TABLE player_action_totals (
    address TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    action  TEXT NOT NULL CHECK (char_length(action) BETWEEN 1 AND 48),
    amount  BIGINT NOT NULL DEFAULT 0 CHECK (amount >= 0),
    PRIMARY KEY (address, action)
);

CREATE TABLE achievement_claims (
    achievement_id TEXT NOT NULL,
    address        TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    claimed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (achievement_id, address)
);
CREATE INDEX achievement_claims_player
    ON achievement_claims(address, claimed_at DESC);
