-- R24 — progression globale et graphe social léger.

CREATE TABLE player_profiles (
    address      TEXT PRIMARY KEY REFERENCES players(address) ON DELETE CASCADE,
    display_name VARCHAR(24) NOT NULL CHECK (char_length(display_name) BETWEEN 3 AND 24),
    friend_code  VARCHAR(20) NOT NULL UNIQUE,
    avatar_id    VARCHAR(32) NOT NULL DEFAULT 'byte',
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO player_profiles(address,display_name,friend_code)
SELECT address,
       'Runner-' || upper(substr(md5(address),1,4)),
       'CYB-' || upper(substr(md5(address),1,12))
FROM players
ON CONFLICT(address) DO NOTHING;

CREATE TABLE progression_scores (
    address    TEXT PRIMARY KEY REFERENCES players(address) ON DELETE CASCADE,
    score      BIGINT NOT NULL DEFAULT 0 CHECK (score >= 0),
    upgrade_score BIGINT NOT NULL DEFAULT 0 CHECK (upgrade_score >= 0),
    district_score BIGINT NOT NULL DEFAULT 0 CHECK (district_score >= 0),
    card_score BIGINT NOT NULL DEFAULT 0 CHECK (card_score >= 0),
    set_score BIGINT NOT NULL DEFAULT 0 CHECK (set_score >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO progression_scores(address)
SELECT address FROM players
ON CONFLICT(address) DO NOTHING;

CREATE TABLE friend_requests (
    requester   TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    addressee   TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(requester,addressee),
    CHECK (requester <> addressee)
);
CREATE INDEX friend_requests_incoming ON friend_requests(addressee,created_at DESC);

CREATE TABLE friendships (
    address_a  TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    address_b  TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(address_a,address_b),
    CHECK (address_a < address_b)
);
CREATE INDEX friendships_by_b ON friendships(address_b,address_a);

CREATE TABLE social_target_preferences (
    attacker   TEXT PRIMARY KEY REFERENCES players(address) ON DELETE CASCADE,
    target     TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    source     TEXT NOT NULL CHECK (source IN ('friend','revenge')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (attacker <> target)
);
