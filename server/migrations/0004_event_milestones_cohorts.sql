-- R24 — milestones d'événement et classements par cohortes.

ALTER TABLE event_scores
    ADD COLUMN cohort_id INTEGER NOT NULL DEFAULT 1,
    ADD CONSTRAINT event_scores_cohort_positive CHECK (cohort_id >= 1);

CREATE INDEX idx_event_score_cohort_rank
    ON event_scores(event_id, cohort_id, points DESC, address);

CREATE TABLE event_milestone_claims (
    event_id        TEXT NOT NULL,
    address         TEXT NOT NULL REFERENCES players(address) ON DELETE CASCADE,
    milestone_index INTEGER NOT NULL CHECK (milestone_index >= 0),
    auto_claimed    BOOLEAN NOT NULL DEFAULT false,
    claimed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, address, milestone_index)
);

CREATE INDEX idx_event_milestone_player
    ON event_milestone_claims(address, event_id);
