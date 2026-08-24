-- R24 — déduplication des batches analytics après retry réseau.

CREATE TABLE IF NOT EXISTS analytics_batches (
    address    TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    batch_id   TEXT NOT NULL,
    accepted   INTEGER NOT NULL CHECK (accepted BETWEEN 0 AND 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (address, batch_id)
);

CREATE INDEX IF NOT EXISTS idx_analytics_batches_created
    ON analytics_batches(created_at);
