-- R24 — invariants de stockage économique et intégrité référentielle.

ALTER TABLE player_state
    ADD CONSTRAINT player_state_nonnegative CHECK (
        spins >= 0 AND credits >= 0 AND district_index >= 0
        AND daily_streak >= 0 AND ads_watched_today >= 0
    ) NOT VALID;

ALTER TABLE district_progress
    ADD CONSTRAINT district_progress_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID,
    ADD CONSTRAINT district_progress_level_nonnegative CHECK (level >= 0) NOT VALID;

ALTER TABLE player_cards
    ADD CONSTRAINT player_cards_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID,
    ADD CONSTRAINT player_cards_qty_nonnegative CHECK (qty >= 0) NOT VALID;

ALTER TABLE set_completion
    ADD CONSTRAINT set_completion_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID;

ALTER TABLE player_chests
    ADD CONSTRAINT player_chests_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID,
    ADD CONSTRAINT player_chests_qty_nonnegative CHECK (qty >= 0) NOT VALID;

ALTER TABLE event_scores
    ADD CONSTRAINT event_scores_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID,
    ADD CONSTRAINT event_scores_points_nonnegative CHECK (points >= 0) NOT VALID;

ALTER TABLE purchases
    ADD CONSTRAINT purchases_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID,
    ADD CONSTRAINT purchases_amount_nonnegative CHECK (amount_u64 >= 0) NOT VALID,
    ADD CONSTRAINT purchases_status_valid CHECK (status IN ('pending','credited','rejected')) NOT VALID;

ALTER TABLE economy_audit
    ADD CONSTRAINT economy_audit_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID;

ALTER TABLE analytics_events
    ADD CONSTRAINT analytics_events_player_fk
        FOREIGN KEY (address) REFERENCES players(address) ON DELETE CASCADE NOT VALID;

ALTER TABLE player_state VALIDATE CONSTRAINT player_state_nonnegative;
ALTER TABLE district_progress VALIDATE CONSTRAINT district_progress_player_fk;
ALTER TABLE district_progress VALIDATE CONSTRAINT district_progress_level_nonnegative;
ALTER TABLE player_cards VALIDATE CONSTRAINT player_cards_player_fk;
ALTER TABLE player_cards VALIDATE CONSTRAINT player_cards_qty_nonnegative;
ALTER TABLE set_completion VALIDATE CONSTRAINT set_completion_player_fk;
ALTER TABLE player_chests VALIDATE CONSTRAINT player_chests_player_fk;
ALTER TABLE player_chests VALIDATE CONSTRAINT player_chests_qty_nonnegative;
ALTER TABLE event_scores VALIDATE CONSTRAINT event_scores_player_fk;
ALTER TABLE event_scores VALIDATE CONSTRAINT event_scores_points_nonnegative;
ALTER TABLE purchases VALIDATE CONSTRAINT purchases_player_fk;
ALTER TABLE purchases VALIDATE CONSTRAINT purchases_amount_nonnegative;
ALTER TABLE purchases VALIDATE CONSTRAINT purchases_status_valid;
ALTER TABLE economy_audit VALIDATE CONSTRAINT economy_audit_player_fk;
ALTER TABLE analytics_events VALIDATE CONSTRAINT analytics_events_player_fk;
