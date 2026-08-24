-- CYBERSEEKER — schéma initial (MVP)
-- Source : docs/ARCHITECTURE.md §4.4
-- Appliqué automatiquement au boot du serveur (sqlx migrate).

-- Identité
CREATE TABLE players (
    address       TEXT PRIMARY KEY,          -- wallet
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- État joueur (une ligne, mise à jour transactionnelle)
CREATE TABLE player_state (
    address            TEXT PRIMARY KEY REFERENCES players,
    spins              INTEGER   NOT NULL DEFAULT 0,
    credits            BIGINT    NOT NULL DEFAULT 0,
    last_spin_at       TIMESTAMPTZ,          -- base du regen
    district_index     INTEGER   NOT NULL DEFAULT 0,
    daily_streak       INTEGER   NOT NULL DEFAULT 0,
    last_daily_claim   DATE,
    ads_watched_today  INTEGER   NOT NULL DEFAULT 0,
    ads_claimed_date   DATE
);

-- Progression districts (data-driven)
CREATE TABLE district_progress (
    address      TEXT NOT NULL,
    district_id  INTEGER NOT NULL,
    element_id   INTEGER NOT NULL,
    level        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (address, district_id, element_id)
);

-- Cartes (doublons = qty)
CREATE TABLE player_cards (
    address  TEXT NOT NULL,
    card_id  TEXT NOT NULL,
    qty      INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (address, card_id)
);

-- Complétion de sets (anti double-claim)
CREATE TABLE set_completion (
    address  TEXT NOT NULL,
    set_id   TEXT NOT NULL,
    claimed  BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (address, set_id)
);

-- Coffres possédés (non ouverts)
CREATE TABLE player_chests (
    address   TEXT NOT NULL,
    chest_id  TEXT NOT NULL,
    qty       INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (address, chest_id)
);

-- Événements (instance active)
CREATE TABLE events (
    event_id   TEXT PRIMARY KEY,
    template   TEXT NOT NULL,
    starts_at  TIMESTAMPTZ NOT NULL,
    ends_at    TIMESTAMPTZ NOT NULL
);

CREATE TABLE event_scores (
    event_id   TEXT NOT NULL,
    address    TEXT NOT NULL,
    points     BIGINT NOT NULL DEFAULT 0,
    reward_claimed BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (event_id, address)
);

-- Achats (intégrité paiement)
CREATE TABLE purchases (
    id            BIGSERIAL PRIMARY KEY,
    address       TEXT NOT NULL,
    offer_id      TEXT NOT NULL,
    tx_signature  TEXT NOT NULL UNIQUE,      -- signature Solana
    token_mint    TEXT NOT NULL,
    amount_u64    BIGINT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'pending',  -- pending|credited|rejected
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Idempotence
CREATE TABLE idempotency (
    key         TEXT PRIMARY KEY,            -- requestId client
    response    JSONB NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Audit économie
CREATE TABLE economy_audit (
    id          BIGSERIAL PRIMARY KEY,
    address     TEXT NOT NULL,
    action      TEXT NOT NULL,
    before      JSONB NOT NULL,
    after       JSONB NOT NULL,
    request_id  TEXT,
    ts          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Analytics (MVP)
CREATE TABLE analytics_events (
    id         BIGSERIAL PRIMARY KEY,
    address    TEXT NOT NULL,
    name       TEXT NOT NULL,
    props      JSONB NOT NULL DEFAULT '{}',
    ts         TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_analytics_ts ON analytics_events (ts);
