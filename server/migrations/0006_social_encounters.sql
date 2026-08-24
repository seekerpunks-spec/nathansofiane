-- R24 — Signal Jam, Ghost Vault et Firewalls.

ALTER TABLE player_state
    ADD COLUMN IF NOT EXISTS firewall_charges INTEGER NOT NULL DEFAULT 0;

ALTER TABLE player_state
    ADD CONSTRAINT player_state_firewall_nonnegative
        CHECK (firewall_charges >= 0) NOT VALID;
ALTER TABLE player_state VALIDATE CONSTRAINT player_state_firewall_nonnegative;

CREATE TABLE district_damage (
    address     TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    district_id INTEGER NOT NULL CHECK (district_id > 0),
    element_id  INTEGER NOT NULL CHECK (element_id > 0),
    attacked_by TEXT REFERENCES players(address) ON DELETE SET NULL,
    attacked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (address, district_id, element_id)
);

CREATE TABLE social_encounters (
    encounter_id  TEXT PRIMARY KEY,
    attacker      TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    target        TEXT REFERENCES players(address) ON DELETE SET NULL,
    kind          TEXT NOT NULL CHECK (kind IN ('attack','raid')),
    status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','resolved','cashed_out','failed','expired')),
    multiplier    INTEGER NOT NULL CHECK (multiplier > 0),
    payload       JSONB NOT NULL DEFAULT '{}',
    reward_credits BIGINT NOT NULL DEFAULT 0 CHECK (reward_credits >= 0),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL,
    resolved_at   TIMESTAMPTZ
);

CREATE UNIQUE INDEX social_encounters_one_pending_per_attacker
    ON social_encounters(attacker) WHERE status = 'pending';
CREATE INDEX social_encounters_target_history
    ON social_encounters(target, created_at DESC);
CREATE INDEX social_encounters_expiry
    ON social_encounters(expires_at) WHERE status = 'pending';
