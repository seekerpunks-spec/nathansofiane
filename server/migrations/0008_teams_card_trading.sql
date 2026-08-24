-- R24 — équipes légères et échanges carte-contre-carte non financiers.

CREATE TABLE teams (
    team_id       TEXT PRIMARY KEY,
    team_code     VARCHAR(20) NOT NULL UNIQUE,
    name          VARCHAR(24) NOT NULL CHECK (char_length(name) BETWEEN 3 AND 24),
    owner_address TEXT NOT NULL REFERENCES players(address) ON DELETE RESTRICT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX teams_name_unique_ci ON teams(lower(name));

CREATE TABLE team_members (
    team_id     TEXT NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    address     TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    role        TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner','member')),
    joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(team_id,address),
    UNIQUE(address)
);
CREATE INDEX team_members_joined ON team_members(team_id,joined_at);

CREATE TABLE card_trade_offers (
    trade_id          TEXT PRIMARY KEY,
    sender            TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    recipient         TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    offered_card_id   TEXT NOT NULL,
    requested_card_id TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','accepted','declined','cancelled','expired')),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ NOT NULL,
    resolved_at       TIMESTAMPTZ,
    CHECK (sender <> recipient),
    CHECK (offered_card_id <> requested_card_id)
);
CREATE INDEX card_trade_incoming ON card_trade_offers(recipient,status,created_at DESC);
CREATE INDEX card_trade_outgoing ON card_trade_offers(sender,status,created_at DESC);
CREATE INDEX card_trade_expiry ON card_trade_offers(expires_at) WHERE status='pending';
