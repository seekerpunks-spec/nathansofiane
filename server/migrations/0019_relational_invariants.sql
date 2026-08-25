-- R24 — invariants relationnels que le runtime applique déjà, désormais
-- protégés aussi contre une écriture administrative ou un futur worker fautif.

ALTER TABLE district_progress
    ADD CONSTRAINT district_progress_ids_positive
        CHECK (district_id > 0 AND element_id > 0) NOT VALID;

ALTER TABLE district_damage
    ADD CONSTRAINT district_damage_not_self_inflicted
        CHECK (attacked_by IS NULL OR attacked_by <> address) NOT VALID;

ALTER TABLE social_encounters
    ADD CONSTRAINT social_encounter_not_self_targeted
        CHECK (target IS NULL OR target <> attacker) NOT VALID,
    ADD CONSTRAINT social_encounter_time_order
        CHECK (expires_at > created_at) NOT VALID,
    ADD CONSTRAINT social_encounter_resolution_consistent
        CHECK (
            (status = 'pending' AND resolved_at IS NULL)
            OR (status <> 'pending' AND resolved_at IS NOT NULL)
        ) NOT VALID;

ALTER TABLE card_trade_offers
    ADD CONSTRAINT card_trade_time_order
        CHECK (expires_at > created_at) NOT VALID,
    ADD CONSTRAINT card_trade_resolution_consistent
        CHECK (
            (status = 'pending' AND resolved_at IS NULL)
            OR (status <> 'pending' AND resolved_at IS NOT NULL)
        ) NOT VALID;

ALTER TABLE auth_nonces
    ADD CONSTRAINT auth_nonce_time_order
        CHECK (expires_at > created_at) NOT VALID;

ALTER TABLE refresh_sessions
    ADD CONSTRAINT refresh_session_time_order
        CHECK (expires_at > created_at) NOT VALID,
    ADD CONSTRAINT refresh_session_replacement_distinct
        CHECK (replaced_by_hash IS NULL OR replaced_by_hash <> jti_hash) NOT VALID;

-- Une équipe peut transitoirement ne pas avoir d'owner pendant les deux UPDATE
-- d'un transfert, mais ne peut jamais en avoir deux à la fin d'une instruction.
CREATE UNIQUE INDEX team_members_one_owner
    ON team_members(team_id) WHERE role = 'owner';

ALTER TABLE district_progress VALIDATE CONSTRAINT district_progress_ids_positive;
ALTER TABLE district_damage VALIDATE CONSTRAINT district_damage_not_self_inflicted;
ALTER TABLE social_encounters VALIDATE CONSTRAINT social_encounter_not_self_targeted;
ALTER TABLE social_encounters VALIDATE CONSTRAINT social_encounter_time_order;
ALTER TABLE social_encounters VALIDATE CONSTRAINT social_encounter_resolution_consistent;
ALTER TABLE card_trade_offers VALIDATE CONSTRAINT card_trade_time_order;
ALTER TABLE card_trade_offers VALIDATE CONSTRAINT card_trade_resolution_consistent;
ALTER TABLE auth_nonces VALIDATE CONSTRAINT auth_nonce_time_order;
ALTER TABLE refresh_sessions VALIDATE CONSTRAINT refresh_session_time_order;
ALTER TABLE refresh_sessions VALIDATE CONSTRAINT refresh_session_replacement_distinct;
