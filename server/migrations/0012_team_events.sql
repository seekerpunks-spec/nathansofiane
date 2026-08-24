-- Événements coopératifs d'équipe : score partagé, contribution et claims personnels.

CREATE TABLE team_event_scores (
    event_id TEXT NOT NULL,
    team_id  TEXT NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    points   BIGINT NOT NULL DEFAULT 0 CHECK (points >= 0),
    PRIMARY KEY (event_id, team_id)
);

CREATE TABLE team_event_contributions (
    event_id TEXT NOT NULL,
    team_id  TEXT NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    address  TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    points   BIGINT NOT NULL DEFAULT 0 CHECK (points >= 0),
    PRIMARY KEY (event_id, team_id, address)
);
CREATE INDEX team_event_contributions_player
    ON team_event_contributions(address, event_id);

-- team_id est conservé comme trace d'audit sans FK : quitter/supprimer une équipe
-- ne doit jamais permettre de réclamer une seconde fois le même palier.
CREATE TABLE team_event_claims (
    event_id        TEXT NOT NULL,
    milestone_index INTEGER NOT NULL CHECK (milestone_index >= 0),
    address         TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    team_id         TEXT NOT NULL,
    claimed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, milestone_index, address)
);
CREATE INDEX team_event_claims_player
    ON team_event_claims(address, event_id);
