-- R26 — live-ops automatisée : distribution idempotente des récompenses de
-- rang, fenêtre de claim bornée et archivage des occurrences terminées.

-- Une ligne par occurrence distribuée : idempotence du worker multi-instance.
CREATE TABLE event_reward_distributions (
    event_key      TEXT PRIMARY KEY,
    event_id       TEXT NOT NULL,
    distributed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    claim_until    TIMESTAMPTZ NOT NULL,
    participants   BIGINT NOT NULL CHECK (participants >= 0),
    rewarded       BIGINT NOT NULL CHECK (rewarded >= 0 AND rewarded <= participants),
    archived_at    TIMESTAMPTZ,
    CHECK (archived_at IS NULL OR archived_at >= distributed_at)
);

-- Récompenses de rang matérialisées à la fin d'une occurrence. Le rang est
-- FIGÉ à la distribution ; la ligne reste comme grand livre après claim ou
-- expiration de la fenêtre.
CREATE TABLE event_rank_rewards (
    event_key   TEXT NOT NULL,
    address     TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    cohort_id   INTEGER NOT NULL CHECK (cohort_id >= 1),
    rank        BIGINT NOT NULL CHECK (rank >= 1),
    reward      JSONB NOT NULL,
    claim_until TIMESTAMPTZ NOT NULL,
    claimed_at  TIMESTAMPTZ,
    PRIMARY KEY (event_key, address),
    CHECK (claimed_at IS NULL OR claimed_at <= claim_until)
);
CREATE INDEX idx_event_rank_rewards_pending
    ON event_rank_rewards(address) WHERE claimed_at IS NULL;

-- Archives sans FK : l'historique survit aux joueurs/équipes supprimés et les
-- tables vivantes restent bornées.
CREATE TABLE event_scores_archive (
    event_key      TEXT NOT NULL,
    address        TEXT NOT NULL,
    points         BIGINT NOT NULL,
    cohort_id      INTEGER NOT NULL,
    reward_claimed BOOLEAN NOT NULL,
    archived_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_key, address)
);

CREATE TABLE team_event_scores_archive (
    event_key   TEXT NOT NULL,
    team_id     TEXT NOT NULL,
    points      BIGINT NOT NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_key, team_id)
);

CREATE TABLE team_event_contributions_archive (
    event_key   TEXT NOT NULL,
    team_id     TEXT NOT NULL,
    address     TEXT NOT NULL,
    points      BIGINT NOT NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_key, team_id, address)
);

CREATE TABLE event_milestone_claims_archive (
    event_key       TEXT NOT NULL,
    address         TEXT NOT NULL,
    milestone_index INTEGER NOT NULL,
    auto_claimed    BOOLEAN NOT NULL,
    claimed_at      TIMESTAMPTZ NOT NULL,
    archived_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_key, address, milestone_index)
);

CREATE TABLE team_event_claims_archive (
    event_key       TEXT NOT NULL,
    milestone_index INTEGER NOT NULL,
    address         TEXT NOT NULL,
    team_id         TEXT NOT NULL,
    claimed_at      TIMESTAMPTZ NOT NULL,
    archived_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_key, milestone_index, address)
);
