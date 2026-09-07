-- R41 — entraide sociale bornée : cadeau ami gratuit, demande de spins en
-- crew et chat à phrases prédéfinies (aucun texte libre à modérer).

CREATE TABLE friend_gifts (
    sender       TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    recipient    TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    gift_date    DATE NOT NULL,
    reward_spins INTEGER NOT NULL CHECK (reward_spins > 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (sender, recipient, gift_date),
    CHECK (sender <> recipient)
);
CREATE INDEX friend_gifts_sender_day ON friend_gifts(sender, gift_date);

CREATE TABLE team_quick_messages (
    message_id TEXT PRIMARY KEY,
    team_id    TEXT NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    address    TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    phrase_id  TEXT NOT NULL CHECK (char_length(phrase_id) BETWEEN 1 AND 32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX team_quick_messages_feed ON team_quick_messages(team_id, created_at DESC);

CREATE TABLE team_help_requests (
    help_id         TEXT PRIMARY KEY,
    team_id         TEXT NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    requester       TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    requested_spins INTEGER NOT NULL CHECK (requested_spins > 0),
    donated_spins   INTEGER NOT NULL DEFAULT 0 CHECK (donated_spins >= 0 AND donated_spins <= requested_spins),
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','fulfilled','expired')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL CHECK (expires_at > created_at)
);
CREATE UNIQUE INDEX team_help_one_open_request
    ON team_help_requests(requester) WHERE status='open';
CREATE INDEX team_help_feed ON team_help_requests(team_id, created_at DESC);

CREATE TABLE team_help_donations (
    help_id    TEXT NOT NULL REFERENCES team_help_requests(help_id) ON DELETE CASCADE,
    donor      TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    spins      INTEGER NOT NULL CHECK (spins > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (help_id, donor)
);
