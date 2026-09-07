-- R40 — preuve d'effacement idempotente sans conserver l'adresse wallet.
-- Seul son hash irréversible et le request-id sont gardés afin qu'un retry
-- réseau de POST /account/delete reçoive la même conclusion.

CREATE TABLE account_deletion_tombstones (
    address_hash TEXT NOT NULL CHECK (char_length(address_hash) = 64),
    request_id   TEXT NOT NULL CHECK (char_length(request_id) BETWEEN 1 AND 128),
    deleted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (address_hash, request_id)
);
CREATE INDEX account_deletion_tombstones_expiry
    ON account_deletion_tombstones(deleted_at);

-- Les nettoyages globaux de rétention ne peuvent pas exploiter les index
-- historiques commençant par `address`.
CREATE INDEX economy_audit_retention ON economy_audit(ts);
CREATE INDEX event_scores_archive_retention ON event_scores_archive(archived_at);
CREATE INDEX team_event_contributions_archive_retention
    ON team_event_contributions_archive(archived_at);
CREATE INDEX event_milestone_claims_archive_retention
    ON event_milestone_claims_archive(archived_at);
CREATE INDEX team_event_claims_archive_retention
    ON team_event_claims_archive(archived_at);
