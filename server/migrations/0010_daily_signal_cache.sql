-- R24 — bonus quotidien mystère, séparé de la série de connexion.

CREATE TABLE daily_bonus_claims (
    address     TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    bonus_id    TEXT NOT NULL,
    claim_day   DATE NOT NULL,
    outcome_id  TEXT NOT NULL,
    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(address,bonus_id,claim_day)
);

CREATE INDEX daily_bonus_recent ON daily_bonus_claims(address,claimed_at DESC);
