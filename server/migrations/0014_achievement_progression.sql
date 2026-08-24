-- Les achievements réclamés contribuent au score global Network Power.

ALTER TABLE progression_scores
    ADD COLUMN achievement_score BIGINT NOT NULL DEFAULT 0,
    ADD CONSTRAINT progression_achievement_score_nonnegative CHECK (achievement_score >= 0);
