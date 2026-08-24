-- R17 — progression, rétention et live-ops. Migration strictement additive.

CREATE TABLE district_completion (
    address      TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    district_id  INTEGER NOT NULL,
    claimed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (address, district_id)
);

CREATE TABLE mission_progress (
    address     TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    mission_id  TEXT NOT NULL,
    mission_day DATE NOT NULL,
    progress    BIGINT NOT NULL DEFAULT 0 CHECK (progress >= 0),
    claimed     BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (address, mission_id, mission_day)
);

CREATE TABLE player_offer_claims (
    address      TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    offer_id     TEXT NOT NULL,
    purchase_id  BIGINT REFERENCES purchases(id),
    claimed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (address, offer_id, claimed_at)
);
CREATE INDEX idx_offer_claim_count ON player_offer_claims(address, offer_id);

CREATE TABLE ad_reward_claims (
    receipt       TEXT PRIMARY KEY,
    address       TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    reward_day    DATE NOT NULL,
    claimed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ad_reward_daily ON ad_reward_claims(address, reward_day);

CREATE TABLE season_progress (
    address       TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    season_id     TEXT NOT NULL,
    points        BIGINT NOT NULL DEFAULT 0 CHECK (points >= 0),
    premium       BOOLEAN NOT NULL DEFAULT false,
    free_claimed  JSONB NOT NULL DEFAULT '[]',
    paid_claimed  JSONB NOT NULL DEFAULT '[]',
    PRIMARY KEY (address, season_id)
);

CREATE INDEX idx_event_score_rank ON event_scores(event_id, points DESC);
CREATE INDEX idx_idempotency_created ON idempotency(created_at);
CREATE INDEX idx_audit_address_ts ON economy_audit(address, ts DESC);
