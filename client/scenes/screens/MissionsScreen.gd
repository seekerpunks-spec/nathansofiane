extends Control
## Centre de rétention : daily, missions, événement, saison et accessibilité.

signal navigate_requested(tab: String)

var _content: VBoxContainer
var _busy := false

func _ready() -> void:
	var body := Ui.screen_body()
	body.add_child(Ui.hero_card("res://assets/generated/api_gpt/heroes/missions_hero.png", "DAILY REWARDS", "Missions", "Joue, progresse et récupère tes récompenses.", Ui.NEON_CYAN))
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
	_content.add_child(Ui.section_title("SIGNAL QUOTIDIEN", Ui.GOLD))
	var daily := Ui.panel()
	var daily_box := VBoxContainer.new()
	daily_box.add_child(Ui.label("SÉRIE ACTUELLE  %d JOURS" % int(Store.state.get("dailyStreak", 0)), 18, Ui.TEXT))
	var daily_btn := Ui.button("RÉCLAMER LE BONUS", Ui.GOLD)
	daily_btn.disabled = _busy or not bool(Store.state.get("dailyAvailable", true))
	daily_btn.pressed.connect(_claim_daily)
	daily_box.add_child(daily_btn)
	daily.add_child(daily_box)
	_content.add_child(daily)

	_content.add_child(Ui.section_title("MISSIONS DU JOUR", Ui.NEON_CYAN))
	var reveal_index := 0
	for mission in Store.state.get("missions", []):
		if typeof(mission) == TYPE_DICTIONARY:
			var card := _mission_card(mission)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.05)
			reveal_index += 1

	_content.add_child(Ui.section_title("ÉVÉNEMENT ACTIF", Ui.NEON_MAGENTA))
	for event in Store.state.get("events", []):
		if typeof(event) == TYPE_DICTIONARY:
			var card := _event_card(event)
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

	_content.add_child(Ui.section_title("ACCESSIBILITÉ", Ui.TEXT_DIM))
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
	var claim := Ui.button("RÉCLAMER  +%s SPINS" % Ui.compact(int(reward.get("spins", 0))), Ui.NEON_CYAN, progress < target)
	claim.disabled = _busy or progress < target or bool(mission.get("claimed", false))
	claim.pressed.connect(_claim_mission.bind(str(mission.get("missionId", ""))))
	box.add_child(claim)
	panel.add_child(box)
	return panel

func _event_card(event: Dictionary) -> PanelContainer:
	var panel := Ui.panel(Ui.PANEL, Ui.NEON_MAGENTA)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Ui.label(str(event.get("name", "Event")), 21, Ui.NEON_MAGENTA))
	var remain := int(event.get("endsAtMs", 0)) - Store.now_ms()
	var points := int(event.get("points", 0))
	box.add_child(Ui.label("%s RESTANT  •  %s POINTS" % [Ui.mmss_long(remain), Ui.compact(points)], 14, Ui.TEXT_DIM))
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
		var reward_text := "+%s SPINS" % Ui.compact(int(reward.get("spins", 0)))
		if int(reward.get("credits", 0)) > 0:
			reward_text += "  +%s CR" % Ui.compact(int(reward.get("credits", 0)))
		var claim_text := "PALIER %s  •  %s" % [Ui.compact(target), reward_text]
		if claimed:
			claim_text = "RÉCUPÉRÉ  •  " + reward_text
		elif auto_claim:
			claim_text = "AUTO  •  " + claim_text
		var claim := Ui.button(claim_text, Ui.GOLD, true)
		claim.disabled = _busy or claimed or auto_claim or points < target
		claim.pressed.connect(_claim_event_milestone.bind(
			str(event.get("eventId", "")), int(milestone.get("index", 0))
		))
		box.add_child(claim)
	var leaderboard := Ui.button("VOIR LE CLASSEMENT", Ui.NEON_MAGENTA, true)
	leaderboard.pressed.connect(_show_leaderboard.bind(str(event.get("eventId", ""))))
	box.add_child(leaderboard)
	panel.add_child(box)
	return panel

func _season_card(season: Dictionary) -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	box.add_child(Ui.label(str(season.get("name", "Season")), 20, Ui.GOLD))
	var points := int(season.get("points", 0))
	box.add_child(Ui.label("%s POINTS  •  %s" % [Ui.compact(points), "PREMIUM" if season.get("premium", false) else "FREE"], 13, Ui.TEXT_DIM))
	var config := _season_config(str(season.get("seasonId", "")))
	var free_claimed: Array = season.get("freeClaimed", [])
	for i in config.get("tiers", []).size():
		var tier: Dictionary = config.get("tiers", [])[i]
		var reward: Dictionary = tier.get("freeReward", {})
		var button := Ui.button("PALIER %s  •  +%s SPINS" % [Ui.compact(int(tier.get("points", 0))), Ui.compact(int(reward.get("spins", 0)))], Ui.GOLD, true)
		button.disabled = _busy or points < int(tier.get("points", 0)) or free_claimed.has(i)
		button.pressed.connect(_claim_season.bind(str(season.get("seasonId", "")), i, false))
		box.add_child(button)
	panel.add_child(box)
	return panel

func _settings_card() -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	for data in [["SONS", "sound_enabled"], ["VIBRATIONS", "haptics_enabled"], ["RÉDUIRE LES ANIMATIONS", "reduced_motion"]]:
		var toggle := CheckButton.new()
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

func _claim_mission(mission_id: String) -> void:
	await _mutate("/mission/claim", {"missionId": mission_id}, "mission_claim")

func _claim_season(season_id: String, tier: int, premium: bool) -> void:
	await _mutate("/season/claim", {"seasonId": season_id, "tier": tier, "premium": premium}, "season_claim")

func _claim_event_milestone(event_id: String, milestone_index: int) -> void:
	await _mutate(
		"/events/%s/milestones/%d/claim" % [event_id, milestone_index],
		{},
		"event_milestone_claimed"
	)

func _mutate(path: String, body: Dictionary, event_name: String) -> void:
	if _busy:
		return
	_busy = true
	var rid := Net.request_id()
	body["requestId"] = rid
	var response := await Net.protected_request("POST", path, body, rid)
	if response.ok:
		Store.apply_mutation(response.data)
		Events.track(event_name, body)
		Sfx.result("rare")
		await _sync_state()
	else:
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()

func _sync_state() -> void:
	var response := await Net.protected_request("GET", "/state")
	if response.ok:
		Store.apply_state(response.data)

func _show_leaderboard(event_id: String) -> void:
	var response := await Net.protected_request("GET", "/events/" + event_id + "/leaderboard")
	if not response.ok:
		Sfx.error()
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.08, 0.96)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 410
	box.add_theme_constant_override("separation", 8)
	box.add_child(Ui.label("NEON LEADERBOARD  •  GROUP %d" % int(response.data.get("cohortId", 1)), 24, Ui.NEON_MAGENTA))
	var leaders: Array = response.data.get("leaders", [])
	for row in leaders.slice(0, mini(10, leaders.size())):
		box.add_child(Ui.label("#%d   %s   %s" % [int(row.get("rank", 0)), str(row.get("address", "")).left(12), Ui.compact(int(row.get("points", 0)))], 14, Ui.TEXT))
	var me: Dictionary = response.data.get("player", {})
	var my_rank := int(me.get("rank", 0))
	box.add_child(Ui.label("TON RANG  %s  •  %s PTS" % ["#%d" % my_rank if my_rank > 0 else "--", Ui.compact(int(me.get("points", 0)))], 16, Ui.GOLD))
	var close := Ui.button("FERMER", Ui.NEON_MAGENTA)
	close.pressed.connect(overlay.queue_free)
	box.add_child(close)
	center.add_child(box)
	overlay.add_child(center)
	add_child(overlay)
