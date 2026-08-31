extends RefCounted
## Télémétrie du résultat de spin. Ce composant transforme la réponse déjà
## autoritaire en événements analytics sans connaître le rendu des rouleaux.

static func track_result(
	tier: String,
	result_type: String,
	multiplier: int,
	base_credits: int,
	credits: int,
	progress: Dictionary
) -> void:
	Events.track("spin_completed", {
		"tier": tier,
		"type": result_type,
		"multiplier": multiplier,
		"spinsSpent": multiplier,
		"baseCredits": base_credits,
		"credits": credits,
	})
	if credits > 0:
		Events.track("currency_earned", {
			"currency": "credits",
			"amount": credits,
			"source": "spin",
			"multiplier": multiplier,
		})
	for event_progress in progress.get("events", []):
		if typeof(event_progress) != TYPE_DICTIONARY:
			continue
		var event_id := str(event_progress.get("eventId", ""))
		Events.track("event_progress", {
			"eventId": event_id,
			"pointsAdded": int(event_progress.get("pointsAdded", 0)),
			"points": int(event_progress.get("points", 0)),
			"cohortId": int(event_progress.get("cohortId", 1)),
			"source": "spin",
		})
		for milestone_index in event_progress.get("autoMilestonesClaimed", []):
			Events.track("milestone_claim", {
				"eventId": event_id,
				"milestoneIndex": int(milestone_index),
				"claimMode": "auto",
			})
	for team_progress in progress.get("teamEvents", []):
		if typeof(team_progress) != TYPE_DICTIONARY:
			continue
		Events.track("team_event_progress", {
			"eventId": str(team_progress.get("eventId", "")),
			"teamId": str(team_progress.get("teamId", "")),
			"pointsAdded": int(team_progress.get("pointsAdded", 0)),
			"teamPoints": int(team_progress.get("teamPoints", 0)),
			"contributionPoints": int(team_progress.get("contributionPoints", 0)),
			"source": "spin",
		})
	for achievement_progress in progress.get("achievements", []):
		if typeof(achievement_progress) != TYPE_DICTIONARY:
			continue
		Events.track("achievement_progress", {
			"achievementId": str(achievement_progress.get("achievementId", "")),
			"action": str(achievement_progress.get("action", "spin")),
			"progress": int(achievement_progress.get("progress", 0)),
			"target": int(achievement_progress.get("target", 0)),
		})
