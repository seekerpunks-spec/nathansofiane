-- R41 — la FK créée dans le schéma initial était la seule relation joueur
-- encore en RESTRICT implicite. Toutes les autres données de compte utilisent
-- déjà ON DELETE CASCADE.

ALTER TABLE player_state
    DROP CONSTRAINT IF EXISTS player_state_address_fkey;

ALTER TABLE player_state
    ADD CONSTRAINT player_state_address_fkey
    FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE;
