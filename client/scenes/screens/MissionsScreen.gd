extends Control
## Centre de rétention : daily, missions, événement, saison et accessibilité.

signal navigate_requested(tab: String)

var _content: VBoxContainer
var _busy := false

func _ready() -> void:
	var body := Ui.screen_body()
	body.add_child(Ui.hero_card("res://assets/generated/api_gpt/heroes/missions_hero.webp", "DAILY REWARDS", "Missions", "Play, progress and stack your rewards.", Ui.NEON_CYAN))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.style_scroll(scroll, Ui.NEON_CYAN)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	body.add_child(scroll)
	add_child(body)
	Store.state_changed.connect(_refresh)
	_refresh()
	_load_fresh_state.call_deferred()

func _load_fresh_state() -> void:
	var response := await Net.protected_request("GET", "/state")
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		Store.apply_state(response.data)

func _refresh() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(Ui.section_title("DAILY SIGNAL", Ui.GOLD))
	var daily := Ui.panel()
	var daily_box := VBoxContainer.new()
	daily_box.add_child(Ui.label("CURRENT STREAK  %d DAYS" % int(Store.state.get("dailyStreak", 0)), 18, Ui.TEXT))
	var daily_btn := Ui.button("CLAIM BONUS", Ui.GOLD)
	daily_btn.disabled = _busy or not bool(Store.state.get("dailyAvailable", true))
	daily_btn.pressed.connect(_claim_daily)
	daily_box.add_child(daily_btn)
	daily.add_child(daily_box)
	_content.add_child(daily)
	var bonus: Dictionary = Store.state.get("dailyBonus", {})
	var bonus_panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_CYAN)
	var bonus_box := VBoxContainer.new()
	bonus_box.add_child(Ui.label(str(bonus.get("name", "SIGNAL CACHE")).to_upper(), 18, Ui.NEON_CYAN))
	bonus_box.add_child(Ui.label("One free signal per day • reward drawn server-side", 12, Ui.TEXT_DIM))
	var bonus_btn := Ui.button("OPEN SIGNAL CACHE", Ui.NEON_CYAN)
	bonus_btn.disabled = _busy or not bool(bonus.get("available", false))
	bonus_btn.pressed.connect(_claim_daily_bonus)
	bonus_box.add_child(bonus_btn)
	bonus_panel.add_child(bonus_box)
	_content.add_child(bonus_panel)

	_content.add_child(Ui.section_title("DAILY MISSIONS", Ui.NEON_CYAN))
	var reveal_index := 0
	for mission in Store.state.get("missions", []):
		if typeof(mission) == TYPE_DICTIONARY:
			var card := _mission_card(mission)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.05)
			reveal_index += 1

	_content.add_child(Ui.section_title("STANDING CONTRACTS", Ui.GOLD))
	for achievement in Store.state.get("achievements", []):
		if typeof(achievement) == TYPE_DICTIONARY:
			var card := _achievement_card(achievement)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.04)
			reveal_index += 1

	var reward_pool: Dictionary = Store.state.get("rewardPool", {})
	if bool(reward_pool.get("enabled", false)):
		_content.add_child(Ui.section_title("SEASON REWARD POOL", Ui.GOLD))
		for pool in reward_pool.get("pools", []):
			if typeof(pool) == TYPE_DICTIONARY:
				var pool_panel := Ui.panel()
				var pool_box := VBoxContainer.new()
				pool_box.add_child(Ui.label(str(pool.get("poolId", "POOL")).to_upper(), 17, Ui.GOLD))
				pool_box.add_child(Ui.label("Pending %s • minimum %s" % [Ui.compact(int(pool.get("pendingU64", 0))), Ui.compact(int(pool.get("minClaimU64", 0)))], 13, Ui.TEXT_DIM))
				pool_box.add_child(Ui.label("Provider required" if not bool(pool.get("claimable", false)) else "Claim available", 12, Ui.TEXT_DIM))
				pool_panel.add_child(pool_box)
				_content.add_child(pool_panel)

	_content.add_child(Ui.section_title("LIVE EVENT", Ui.NEON_MAGENTA))
	for event in Store.state.get("events", []):
		if typeof(event) == TYPE_DICTIONARY:
			var card := _event_card(event)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.05)
			reveal_index += 1

	var team_events: Array = Store.state.get("teamEvents", [])
	if not team_events.is_empty():
		_content.add_child(Ui.section_title("CREW EVENT", Ui.NEON_CYAN))
		for event in team_events:
			if typeof(event) == TYPE_DICTIONARY:
				var card := _team_event_card(event)
				_content.add_child(card)
				Ui.reveal(card, reveal_index * 0.05)
				reveal_index += 1

	_content.add_child(Ui.section_title("SEASON PASS", Ui.GOLD))
	for season in Store.state.get("seasons", []):
		if typeof(season) == TYPE_DICTIONARY:
			var card := _season_card(season)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.05)
			reveal_index += 1

	_content.add_child(Ui.section_title("ACCESSIBILITY", Ui.TEXT_DIM))
	_content.add_child(_settings_card())

func _mission_card(mission: Dictionary) -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var title := Ui.label(str(mission.get("name", "Mission")), 17, Ui.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var progress := int(mission.get("progress", 0))
	var target := int(mission.get("target", 1))
	row.add_child(Ui.label("%d / %d" % [mini(progress, target), target], 14, Ui.NEON_CYAN))
	box.add_child(row)
	var bar := Ui.progress_bar(Ui.NEON_CYAN)
	bar.value = clampf(float(progress) / float(maxi(1, target)) * 100.0, 0.0, 100.0)
	box.add_child(bar)
	var reward: Dictionary = mission.get("reward", {})
	var claim := Ui.button("CLAIM  " + Ui.reward_text(reward), Ui.NEON_CYAN, progress < target)
	claim.disabled = _busy or progress < target or bool(mission.get("claimed", false))
	claim.pressed.connect(_claim_mission.bind(str(mission.get("missionId", ""))))
	box.add_child(claim)
	panel.add_child(box)
	return panel

func _achievement_card(achievement: Dictionary) -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var title := Ui.label(str(achievement.get("name", "Contrat")), 17, Ui.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var progress := int(achievement.get("progress", 0))
	var target := int(achievement.get("target", 1))
	row.add_child(Ui.label("%s / %s" % [Ui.compact(mini(progress, target)), Ui.compact(target)], 14, Ui.TEXT))
	box.add_child(row)
	box.add_child(Ui.label(str(achievement.get("description", "")), 12, Ui.TEXT_DIM))
	var bar := Ui.progress_bar(Ui.GOLD)
	bar.value = clampf(float(progress) / float(maxi(1, target)) * 100.0, 0.0, 100.0)
	box.add_child(bar)
	var reward: Dictionary = achievement.get("reward", {})
	var reward_text := Ui.reward_text(reward)
	var claimed := bool(achievement.get("claimed", false))
	var claim := Ui.button("CLAIMED" if claimed else "CLAIM  " + reward_text, Ui.GOLD, true)
	claim.disabled = _busy or claimed or progress < target
	claim.pressed.connect(_claim_achievement.bind(str(achievement.get("achievementId", ""))))
	box.add_child(claim)
	panel.add_child(box)
	return panel

func _event_card(event: Dictionary) -> PanelContainer:
	var panel := Ui.panel(Ui.PANEL, Ui.NEON_MAGENTA)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := str(event.get("name", "Event"))
	if bool(event.get("recurring", false)):
		title += "  •  WAVE %d" % (int(event.get("occurrence", 0)) + 1)
	box.add_child(Ui.label(title, 21, Ui.NEON_MAGENTA))
	var now := Store.now_ms()
	var starts := int(event.get("startsAtMs", 0))
	var remain := int(event.get("endsAtMs", 0)) - now
	var points := int(event.get("points", 0))
	var upcoming := starts > now
	if upcoming:
		box.add_child(Ui.label("NEXT WAVE IN %s" % Ui.mmss_long(starts - now), 14, Ui.TEXT_DIM))
	elif remain > 0:
		box.add_child(Ui.label("%s LEFT  •  %s POINTS" % [Ui.mmss_long(remain), Ui.compact(points)], 14, Ui.TEXT_DIM))
	else:
		box.add_child(Ui.label("WAVE COMPLETE  •  %s POINTS" % Ui.compact(points), 14, Ui.TEXT_DIM))
	for milestone in event.get("milestones", []):
		if typeof(milestone) != TYPE_DICTIONARY:
			continue
		var target := int(milestone.get("points", 0))
		var reward: Dictionary = milestone.get("reward", {})
		var claimed := bool(milestone.get("claimed", false))
		var auto_claim := bool(milestone.get("autoClaim", false))
		var progress := Ui.progress_bar(Ui.GOLD, 8)
		progress.value = clampf(float(points) / float(maxi(1, target)) * 100.0, 0.0, 100.0)
		box.add_child(progress)
		var reward_text := Ui.reward_text(reward)
		var claim_text := "TIER %s  •  %s" % [Ui.compact(target), reward_text]
		if claimed:
			claim_text = "CLAIMED  •  " + reward_text
		elif auto_claim:
			claim_text = "AUTO  •  " + claim_text
		var claim := Ui.button(claim_text, Ui.GOLD, true)
		claim.disabled = _busy or claimed or auto_claim or upcoming or points < target
		claim.pressed.connect(_claim_event_milestone.bind(
			str(event.get("eventId", "")), int(milestone.get("index", 0))
		))
		box.add_child(claim)
	if not upcoming:
		var leaderboard := Ui.button("VIEW LEADERBOARD", Ui.NEON_MAGENTA, true)
		leaderboard.pressed.connect(_show_leaderboard.bind(str(event.get("eventId", ""))))
		box.add_child(leaderboard)
	# Récompense de rang : matérialisée par le serveur à la fin de la vague,
	# réclamable pendant une fenêtre bornée. Avant distribution, on l'annonce.
	var rank_reward: Variant = event.get("rankReward")
	if typeof(rank_reward) == TYPE_DICTIONARY and not bool(rank_reward.get("claimed", false)):
		var claim_remain := int(rank_reward.get("claimUntilMs", 0)) - now
		if claim_remain > 0:
			var rank_prize: Dictionary = rank_reward.get("reward", {})
			var finish := Ui.button("RANG #%d  •  %s  •  EXPIRE %s" % [
				int(rank_reward.get("rank", 0)),
				Ui.reward_text(rank_prize),
				Ui.mmss_long(claim_remain),
			], Ui.GOLD)
			finish.disabled = _busy
			finish.pressed.connect(_claim_event_finish.bind(str(event.get("eventId", ""))))
			box.add_child(finish)
	elif remain <= 0 and not upcoming and points > 0 and not bool(event.get("rewardClaimed", false)):
		box.add_child(Ui.label("RANKING IN PROGRESS…", 13, Ui.TEXT_DIM))
	panel.add_child(box)
	return panel

func _team_event_card(event: Dictionary) -> PanelContainer:
	var panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_CYAN)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Ui.label(str(event.get("name", "Crew Event")), 21, Ui.NEON_CYAN))
	box.add_child(Ui.label(str(event.get("teamName", "CREW")).to_upper(), 13, Ui.TEXT_DIM))
	var remain := int(event.get("endsAtMs", 0)) - Store.now_ms()
	var team_points := int(event.get("teamPoints", 0))
	var contribution := int(event.get("contributionPoints", 0))
	var minimum := int(event.get("minContributionPoints", 0))
	box.add_child(Ui.label(
		"%s LEFT  •  CREW %s  •  YOU %s/%s" % [
			Ui.mmss_long(remain), Ui.compact(team_points), Ui.compact(contribution), Ui.compact(minimum)
		], 13, Ui.TEXT_DIM
	))
	for milestone in event.get("milestones", []):
		if typeof(milestone) != TYPE_DICTIONARY:
			continue
		var target := int(milestone.get("points", 0))
		var reward: Dictionary = milestone.get("reward", {})
		var claimed := bool(milestone.get("claimed", false))
		var progress := Ui.progress_bar(Ui.NEON_CYAN, 8)
		progress.value = clampf(float(team_points) / float(maxi(1, target)) * 100.0, 0.0, 100.0)
		box.add_child(progress)
		var reward_text := Ui.reward_text(reward)
		var claim_text := "CREW %s  •  %s" % [Ui.compact(target), reward_text]
		if contribution < minimum:
			claim_text = "CONTRIBUTE %s  •  %s" % [Ui.compact(minimum), reward_text]
		elif claimed:
			claim_text = "CLAIMED  •  " + reward_text
		var claim := Ui.button(claim_text, Ui.NEON_CYAN, true)
		claim.disabled = _busy or claimed or team_points < target or contribution < minimum
		claim.pressed.connect(_claim_team_event_milestone.bind(
			str(event.get("eventId", "")), int(milestone.get("index", 0))
		))
		box.add_child(claim)
	panel.add_child(box)
	return panel

func _season_card(season: Dictionary) -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Ui.label(str(season.get("name", "Season")), 20, Ui.GOLD))
	var points := int(season.get("points", 0))
	var premium := bool(season.get("premium", false))
	var remain := int(season.get("endsAtMs", 0)) - Store.now_ms()
	var status := "PREMIUM" if premium else "FREE"
	if remain > 0:
		box.add_child(Ui.label("%s POINTS  •  %s  •  ENDS IN %s" % [Ui.compact(points), status, Ui.mmss_long(remain)], 13, Ui.TEXT_DIM))
	else:
		box.add_child(Ui.label("%s POINTS  •  %s  •  SEASON OVER" % [Ui.compact(points), status], 13, Ui.TEXT_DIM))
	# Paliers envoyés par /state (source serveur) ; la config embarquée reste
	# le repli hors-ligne.
	var tiers: Array = season.get("tiers", [])
	if tiers.is_empty():
		tiers = _season_config(str(season.get("seasonId", ""))).get("tiers", [])
	var free_claimed: Array = season.get("freeClaimed", [])
	var paid_claimed: Array = season.get("paidClaimed", [])
	var season_id := str(season.get("seasonId", ""))
	for i in tiers.size():
		if typeof(tiers[i]) != TYPE_DICTIONARY:
			continue
		var tier: Dictionary = tiers[i]
		var tier_points := int(tier.get("points", 0))
		var reached := points >= tier_points
		var free_reward: Dictionary = tier.get("freeReward", {})
		var free_btn := Ui.button("TIER %s  •  %s" % [Ui.compact(tier_points), Ui.reward_text(free_reward)], Ui.GOLD, true)
		free_btn.disabled = _busy or not reached or free_claimed.has(i)
		free_btn.pressed.connect(_claim_season.bind(season_id, i, false))
		box.add_child(free_btn)
		var premium_reward: Variant = tier.get("premiumReward")
		if typeof(premium_reward) == TYPE_DICTIONARY:
			var premium_text := "PREMIUM %s  •  %s" % [Ui.compact(tier_points), Ui.reward_text(premium_reward)]
			if not premium:
				premium_text = "PREMIUM LOCKED  •  " + Ui.reward_text(premium_reward)
			var premium_btn := Ui.button(premium_text, Ui.NEON_MAGENTA, true)
			premium_btn.disabled = _busy or not premium or not reached or paid_claimed.has(i)
			premium_btn.pressed.connect(_claim_season.bind(season_id, i, true))
			box.add_child(premium_btn)
	panel.add_child(box)
	return panel

func _settings_card() -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	for data in [["SOUND", "sound_enabled"], ["HAPTICS", "haptics_enabled"], ["REDUCE MOTION", "reduced_motion"]]:
		var toggle := CheckButton.new()
		toggle.custom_minimum_size.y = 52
		toggle.text = data[0]
		toggle.button_pressed = bool(Preferences.get(data[1]))
		toggle.toggled.connect(_set_preference.bind(data[1]))
		box.add_child(toggle)
	panel.add_child(box)
	return panel

func _set_preference(enabled: bool, property: String) -> void:
	Preferences.set(property, enabled)
	Preferences.save()

func _season_config(id: String) -> Dictionary:
	for season in Config.seasons():
		if typeof(season) == TYPE_DICTIONARY and str(season.get("seasonId", "")) == id:
			return season
	return {}

func _claim_daily() -> void:
	await _mutate("/daily/claim", {}, "daily_claim")

func _claim_daily_bonus() -> void:
	await _mutate("/daily/bonus/claim", {}, "daily_bonus_claim")

func _claim_mission(mission_id: String) -> void:
	await _mutate("/mission/claim", {"missionId": mission_id}, "mission_claim")

func _claim_achievement(achievement_id: String) -> void:
	await _mutate(
		"/achievements/%s/claim" % achievement_id,
		{"achievementId": achievement_id},
		"achievement_claim"
	)

func _claim_season(season_id: String, tier: int, premium: bool) -> void:
	await _mutate("/season/claim", {"seasonId": season_id, "tier": tier, "premium": premium}, "season_claim")

func _claim_event_milestone(event_id: String, milestone_index: int) -> void:
	await _mutate(
		"/events/%s/milestones/%d/claim" % [event_id, milestone_index],
		{"eventId": event_id, "milestoneIndex": milestone_index, "claimMode": "manual"},
		"milestone_claim"
	)

func _claim_team_event_milestone(event_id: String, milestone_index: int) -> void:
	await _mutate(
		"/team-events/%s/milestones/%d/claim" % [event_id, milestone_index],
		{"eventId": event_id, "milestoneIndex": milestone_index},
		"team_event_milestone_claim"
	)

func _claim_event_finish(event_id: String) -> void:
	await _mutate("/events/%s/claim" % event_id, {"eventId": event_id}, "leaderboard_finish")

func _mutate(path: String, body: Dictionary, event_name: String) -> void:
	if _busy:
		return
	_busy = true
	var rid := Net.request_id()
	body["requestId"] = rid
	var response := await Net.protected_request("POST", path, body, rid)
	if response.ok:
		Store.apply_mutation(response.data)
		var props := body.duplicate()
		props.erase("requestId")
		if typeof(response.data) == TYPE_DICTIONARY:
			for key in ["rank", "cohortId", "milestoneIndex", "points", "teamId", "teamPoints", "contributionPoints", "achievementId", "progress", "target", "day", "streak", "entitlementBonusSpins", "missionId", "seasonId", "tier", "premium", "eventKey"]:
				if response.data.has(key):
					props[key] = response.data[key]
		Events.track(event_name, props)
		_track_reward_pool(response.data.get("rewardPoolAllocations", []))
		_track_reward_currency(response.data, event_name)
		Sfx.result("rare")
		await _sync_state()
	else:
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()

func _track_reward_pool(allocations: Variant) -> void:
	if typeof(allocations) != TYPE_ARRAY:
		return
	for allocation in allocations:
		if typeof(allocation) == TYPE_DICTIONARY and int(allocation.get("amountU64", 0)) > 0:
			Events.track("reward_pool_progress", allocation)

func _sync_state() -> void:
	var response := await Net.protected_request("GET", "/state")
	if response.ok:
		Store.apply_state(response.data)

func _track_reward_currency(data: Dictionary, source: String) -> void:
	var reward: Variant = data.get("reward", {})
	if typeof(reward) != TYPE_DICTIONARY:
		return
	var credits := int(reward.get("credits", 0))
	if credits > 0:
		Events.track("currency_earned", {"currency": "credits", "amount": credits, "source": source})

func _show_leaderboard(event_id: String) -> void:
	var response := await Net.protected_request("GET", "/events/" + event_id + "/leaderboard")
	if not response.ok:
		Sfx.error()
		return
	var player: Dictionary = response.data.get("player", {})
	Events.track("leaderboard_join", {
		"eventId": event_id,
		"cohortId": int(response.data.get("cohortId", 1)),
		"rank": int(player.get("rank", 0)),
		"points": int(player.get("points", 0)),
	})
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.08, 0.96)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 0
	box.add_theme_constant_override("separation", 8)
	box.add_child(Ui.label("NEON LEADERBOARD  •  GROUP %d" % int(response.data.get("cohortId", 1)), 24, Ui.NEON_MAGENTA))
	var leaders: Array = response.data.get("leaders", [])
	for row in leaders.slice(0, mini(10, leaders.size())):
		box.add_child(Ui.label("#%d   %s   %s" % [int(row.get("rank", 0)), str(row.get("displayName", "Runner")), Ui.compact(int(row.get("points", 0)))], 14, Ui.TEXT))
	var me: Dictionary = response.data.get("player", {})
	var my_rank := int(me.get("rank", 0))
	box.add_child(Ui.label("YOUR RANK  %s  •  %s PTS" % ["#%d" % my_rank if my_rank > 0 else "--", Ui.compact(int(me.get("points", 0)))], 16, Ui.GOLD))
	var close := Ui.button("CLOSE", Ui.NEON_MAGENTA)
	close.pressed.connect(overlay.queue_free)
	box.add_child(close)
	center.add_child(box)
	overlay.add_child(center)
	add_child(overlay)
