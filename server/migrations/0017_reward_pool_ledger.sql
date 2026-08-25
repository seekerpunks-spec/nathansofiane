-- Architecture future du pool saisonnier SKR. Aucun payout n'est exposé au
-- client : le ledger reste inactif tant que config et provider sont désactivés.

CREATE TABLE reward_pool_allocations (
    pool_id      TEXT NOT NULL CHECK (char_length(pool_id) BETWEEN 1 AND 64),
    address      TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    source_key   TEXT NOT NULL CHECK (char_length(source_key) BETWEEN 1 AND 160),
    amount_u64   BIGINT NOT NULL CHECK (amount_u64 > 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (pool_id, address, source_key)
);
CREATE INDEX reward_pool_allocations_total ON reward_pool_allocations(pool_id);

CREATE TABLE reward_pool_balances (
    pool_id      TEXT NOT NULL CHECK (char_length(pool_id) BETWEEN 1 AND 64),
    address      TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    pending_u64  BIGINT NOT NULL DEFAULT 0 CHECK (pending_u64 >= 0),
    settled_u64  BIGINT NOT NULL DEFAULT 0 CHECK (settled_u64 >= 0),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (pool_id, address)
);

CREATE TABLE reward_pool_settlements (
    settlement_ref  TEXT PRIMARY KEY CHECK (char_length(settlement_ref) BETWEEN 1 AND 160),
    pool_id         TEXT NOT NULL,
    address         TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    amount_u64      BIGINT NOT NULL CHECK (amount_u64 > 0),
    settled_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX reward_pool_settlements_player ON reward_pool_settlements(pool_id,address);
