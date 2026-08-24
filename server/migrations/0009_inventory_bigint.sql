-- R24 — quantités compatibles avec les récompenses jusqu'à ×100K.

ALTER TABLE player_cards ALTER COLUMN qty TYPE BIGINT USING qty::bigint;
ALTER TABLE player_chests ALTER COLUMN qty TYPE BIGINT USING qty::bigint;
