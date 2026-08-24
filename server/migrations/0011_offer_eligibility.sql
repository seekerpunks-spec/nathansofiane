-- R24 — conserve la session précédente pour les offres de retour autoritaires.

ALTER TABLE players ADD COLUMN previous_seen_at TIMESTAMPTZ;
