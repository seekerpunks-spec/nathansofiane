extends Control
const Neon := preload("res://scripts/components/NeonSkin.gd")
## SpinScreen R42 — vue Punk City indépendante, logique serveur préservée.
##
## Le serveur choisit toujours le résultat économique. Les symboles constituent
## uniquement une représentation animée de la réponse autoritaire.

signal navigate_requested(tab: String)

const SpinHomeView := preload("res://scripts/components/SpinHomeView.gd")
const SpinVisuals := preload("res://scripts/components/SpinVisuals.gd")
const SpinJuice := preload("res://scripts/components/SpinJuice.gd")
const SpinNetworkView := preload("res://scripts/components/SpinNetworkView.gd")
const SpinEncounterView := preload("res://scripts/components/SpinEncounterView.gd")
const SpinNetworkActions := preload("res://scripts/components/SpinNetworkActions.gd")
const SpinTelemetry := preload("res://scripts/components/SpinTelemetry.gd")
const SYMBOLS := ["credits", "shield", "hack", "vault", "energy", "glitch", "chest", "card"]

var _home_view: RefCounted
var _spins_value: Label
var _credits_value: Label
var _district_label: Label
var _event_label: Label
var _event_timer: Label
var _status_label: Label
var _result_banner: Label
var _spin_btn: Button
var _multiplier_btn: Button
var _regen_bar: ProgressBar
var _regen_label: Label
var _no_spins: Control
var _no_spins_label: Label
var _flash: ColorRect
var _tick_timer: Timer
var _cabinet_root: Control
var _cabinet: Control
var _particles: Control
var _reels: Array = []
var _reel_tweens: Array = []
var _hud_spins := -1
var _hud_credits := -1
var _mascot: Control

var _busy := false
var _revealed := false
var _skip_enabled := false
var _pending_outcome: Dictionary = {}
var _pending_credits := 0
var _pending_base_credits := 0
var _pending_multiplier := 1
var _pending_progress: Dictionary = {}
var _final_symbols: Array[String] = []
var _anticipation := false
var _landed_count := 0
var _selected_multiplier := 1
var _social_overlay: ColorRect
var _social_busy := false
var _tracked_social_starts: Dictionary = {}
var _network_snapshot: Dictionary = {}
var _network_leaderboard: Dictionary = {}
var _network_results: Array = []
var _team_snapshot: Dictionary = {}
var _team_leaderboard: Dictionary = {}
var _team_results: Array = []
var _trades_snapshot: Dictionary = {}
var _network_message := ""
var _network_view: RefCounted
var _encounter_view: RefCounted
var _network_actions: RefCounted


func _ready() -> void:
	_network_view = SpinNetworkView.new(self)
	_encounter_view = SpinEncounterView.new(self)
	_network_actions = SpinNetworkActions.new(self)
	_build()
	_refresh_hud()
	_start_idle_animation()
	Store.state_changed.connect(_refresh_hud)
	Store.no_spins.connect(_show_no_spins)
	_resume_pending_encounter.call_deferred()


func handle_back() -> bool:
	if is_instance_valid(_social_overlay):
		_clear_social_overlay()
		return true
	if is_instance_valid(_no_spins) and _no_spins.visible:
		_no_spins.visible = false
		return true
	return false


func _build() -> void:
	_home_view = SpinHomeView.new(self)
	_home_view.build()

	_no_spins = _build_no_spins()
	add_child(_no_spins)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_particles = SpinVisuals.ParticleBurst.new()
	_particles.set_anchors_preset(Control.PRESET_FULL_RECT)
	_particles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_particles)

	_tick_timer = Timer.new()
	_tick_timer.wait_time = 0.055
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)


func _build_no_spins() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false

	var dim := ColorRect.new()
	dim.color = Color("#020614", 0.98)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var box := Ui.screen_body()
	box.add_child(Neon.header("PUNK CITY / ENERGY", "Recharge", 4, Ui.NEON_CYAN))
	box.add_child(Neon.feature("ENERGY EMPTY", "Grab rewards or wait for your next free spin.", 4, Ui.NEON_MAGENTA))
	_no_spins_label = Ui.label("Network recharging…", 16, Ui.TEXT_DIM)
	_no_spins_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_no_spins_label)

	var store := Ui.button("RECHARGE OPTIONS", Ui.NEON_CYAN)
	store.pressed.connect(func() -> void:
		overlay.visible = false
		navigate_requested.emit("store")
	)
	box.add_child(store)

	var missions := Ui.button("COLLECT REWARDS", Ui.GOLD, true)
	missions.pressed.connect(func() -> void:
		overlay.visible = false
		navigate_requested.emit("missions")
	)
	box.add_child(missions)
	var close := Ui.button("BACK TO SPIN", Ui.NEON_CYAN, true)
	close.pressed.connect(func() -> void: overlay.hide())
	box.add_child(close)
	overlay.add_child(box)
	return overlay


func _process(_delta: float) -> void:
	_update_regen()
	_update_event()
	if _no_spins.visible:
		var next: Variant = Store.state.get("nextSpinAtMs", null)
		if next != null:
			_no_spins_label.text = "Next signal in " + Ui.mmss(Store.regen_remaining_ms())


func _update_regen() -> void:
	var max_spins := int(Config.economy().get("maxFreeSpins", 25))
	var next: Variant = Store.state.get("nextSpinAtMs", null)
	if next == null or Store.spins() >= max_spins:
		_regen_label.text = "%d SPINS  •  BANK FULL" % Store.spins()
		_regen_bar.value = 100.0
		return
	var remain := Store.regen_remaining_ms()
	_regen_label.text = "%d / %d  •  +1 IN %s" % [Store.spins(), max_spins, Ui.mmss(remain)]
	_regen_bar.value = clampf(float(Store.spins()) / float(maxi(1, max_spins)), 0.0, 1.0) * 100.0


func _update_event() -> void:
	_home_view.update_event()


func _refresh_hud() -> void:
	var spins := Store.spins()
	var credits := Store.credits()
	if _hud_spins < 0:
		_spins_value.text = str(spins)
		_credits_value.text = Ui.compact(credits)
	else:
		if spins != _hud_spins:
			Juice.count(_spins_value, _hud_spins, spins, 0.28, func(n: int) -> String: return str(n))
		if credits != _hud_credits:
			Juice.count(_credits_value, _hud_credits, credits, 0.42, func(n: int) -> String: return Ui.compact(n))
			if credits > _hud_credits and not Juice.reduced():
				Sfx.coin()
	_hud_spins = spins
	_hud_credits = credits
	_normalize_multiplier()
	_home_view.refresh()


func _affordable_multipliers() -> Array[int]:
	var values: Array[int] = []
	for raw in Config.spin_multipliers():
		var value := int(raw)
		if value > 0 and value <= Store.spins():
			values.append(value)
	if values.is_empty():
		values.append(1)
	return values


func _normalize_multiplier() -> void:
	var affordable := _affordable_multipliers()
	if not affordable.has(_selected_multiplier):
		_selected_multiplier = 1
	if _multiplier_btn != null:
		_multiplier_btn.text = "BET  ×" + Ui.compact(_selected_multiplier)
		_multiplier_btn.disabled = _busy or affordable.size() <= 1


func _cycle_multiplier() -> void:
	if _busy:
		return
	var affordable := _affordable_multipliers()
	var index := affordable.find(_selected_multiplier)
	_selected_multiplier = affordable[(index + 1) % affordable.size()]
	_multiplier_btn.text = "BET  ×" + Ui.compact(_selected_multiplier)
	Events.track("multiplier_changed", {"multiplier": _selected_multiplier})
	Sfx.click()


func _on_spin_pressed() -> void:
	if _busy:
		if _skip_enabled:
			_skip_slots()
		return
	Sfx.click()
	_do_spin()


func _do_spin() -> void:
	_busy = true
	_revealed = false
	_skip_enabled = false
	_no_spins.visible = false
	_result_banner.text = "ROLLING FOR LOOT…"
	_result_banner.add_theme_color_override("font_color", Ui.TEXT_DIM)
	_status_label.text = "GOOD LUCK!"
	_status_label.add_theme_color_override("font_color", Ui.NEON_BLUE)
	_cabinet.set_mode(Ui.NEON_BLUE, false)
	_spin_btn.text = "ROLLING…"
	_spin_btn.disabled = true
	_stop_idle_animation()
	Events.track("spin_started", {
		"multiplier": _selected_multiplier,
		"spinsAvailable": Store.spins(),
	})
	Sfx.reel_start()
	Haptics.vibrate(0.28, 22)

	var request_id := Net.request_id()
	var response := await Net.protected_request(
		"POST", "/spin", {
			"requestId": request_id,
			"multiplier": _selected_multiplier,
		}, request_id
	)

	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		var data: Dictionary = response.data
		Store.apply_spin(data)
		var outcome: Variant = data.get("outcome", {})
		_pending_outcome = outcome if typeof(outcome) == TYPE_DICTIONARY else {}
		_pending_credits = int(data.get("creditsGained", 0))
		_pending_base_credits = int(data.get("baseCreditsGained", _pending_credits))
		_pending_multiplier = int(data.get("multiplier", 1))
		_pending_progress = data.get("progress", {}) if typeof(data.get("progress", {})) == TYPE_DICTIONARY else {}
		_final_symbols = SpinVisuals.symbols_for_result(_pending_outcome)
		_animate_slots(_final_symbols)
	elif response.code == 403:
		var details := _parse_spin_error_details(response.data)
		var next_ms := int(details.get("nextSpinAtMs", 0))
		var available := int(details.get("availableSpins", 0))
		Store.apply_insufficient_spins(available, next_ms)
		_selected_multiplier = 1
		_reset_idle_state()
		if available > 0:
			_status_label.text = "BET RESET TO ×1"
			_result_banner.text = "%d SPINS AVAILABLE" % available
			_refresh_hud()
	elif response.code == 401:
		Store.session_expired.emit()
		_reset_idle_state()
	else:
		Sfx.error()
		Haptics.error()
		_status_label.text = "SIGNAL LOST"
		_status_label.add_theme_color_override("font_color", Ui.NEON_MAGENTA)
		_result_banner.text = "NETWORK ERROR · TRY AGAIN"
		_result_banner.add_theme_color_override("font_color", Ui.NEON_MAGENTA)
		_reset_idle_state(false)


func _animate_slots(finals: Array[String]) -> void:
	if finals.is_empty():
		return
	_landed_count = 0
	var tier := str(_pending_outcome.get("tier", "common")).to_lower()
	_anticipation = tier in ["rare", "epic", "legendary"]
	_skip_enabled = true
	_spin_btn.disabled = false
	_spin_btn.text = "STOP NOW"
	_status_label.text = "GOOD LUCK!"
	_tick_timer.start()
	_reel_tweens = SpinJuice.spin_reels(self, _reels, _anticipation, _land_reel)


func _land_reel(index: int) -> void:
	if _revealed:
		return
	var symbol: String = _final_symbols[index]
	var reel: Control = _reels[index]
	reel.land(symbol)
	SpinJuice.land_bounce(reel)
	Sfx.reel_stop(index)
	Haptics.vibrate(0.25 + index * 0.16, 20 + index * 8)
	_landed_count += 1

	if index == 1 and _anticipation:
		_status_label.text = "ALMOST!"
		_status_label.add_theme_color_override("font_color", Ui.NEON_MAGENTA)
		_cabinet.set_mode(Ui.NEON_MAGENTA, false)
		Sfx.anticipation()
		SpinJuice.anticipation_pulse(_cabinet_root)
	if _landed_count >= 3:
		_on_landed()


func _skip_slots() -> void:
	if not _busy or _revealed:
		return
	_skip_enabled = false
	for tween in _reel_tweens:
		if tween != null and tween is Tween and (tween as Tween).is_valid():
			(tween as Tween).kill()
	for i in 3:
		var reel: Control = _reels[i]
		if reel.spinning:
			reel.land(_final_symbols[i])
			Sfx.reel_stop(i)
	_landed_count = 3
	_on_landed()


func _unhandled_input(event: InputEvent) -> void:
	if not _busy or not _skip_enabled:
		return
	var tapped: bool = (
		event is InputEventScreenTouch and event.pressed
	) or (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	)
	if tapped:
		_skip_slots()
		get_viewport().set_input_as_handled()


func _on_landed() -> void:
	if _revealed:
		return
	_revealed = true
	_skip_enabled = false
	_tick_timer.stop()
	Sfx.reel_finish()

	var tier := str(_pending_outcome.get("tier", "common")).to_lower()
	var result_type := str(_pending_outcome.get("type", "credits")).to_lower()
	var accent := Ui.tier_color(tier)
	if result_type in ["none", "glitch"]:
		accent = Ui.NEON_MAGENTA
		_status_label.text = "GLITCH!"
		_result_banner.text = "NO LOOT  •  TRY AGAIN"
	elif result_type == "attack":
		_status_label.text = "SIGNAL JAM!"
		_result_banner.text = "CHOOSE A NETWORK NODE"
	elif result_type == "raid":
		_status_label.text = "GHOST VAULT!"
		_result_banner.text = "BREACH OR CASH OUT"
	elif result_type == "shield":
		_status_label.text = "FIREWALL!"
		_result_banner.text = "DEFENSE CHARGE SECURED"
	elif result_type == "chest":
		_status_label.text = "CACHE DROP!"
		_result_banner.text = "CHEST ADDED TO CARDS"
	elif result_type == "card":
		_status_label.text = "CARD SIGNAL!"
		_result_banner.text = "NEW DATA FRAGMENT"
	else:
		_status_label.text = "MEGA JACKPOT!" if tier == "legendary" else "YOU WIN!"
		_result_banner.text = "+" + Ui.compact(_pending_credits) + " CR"
		if _pending_multiplier > 1:
			_result_banner.text += "  ·  ×" + Ui.compact(_pending_multiplier)
	_result_banner.add_theme_color_override("font_color", accent)
	_status_label.add_theme_color_override("font_color", accent)
	_cabinet.set_mode(accent, tier in ["epic", "legendary"])

	SpinJuice.impact(_result_banner, _cabinet_root, _flash, _particles, tier, accent)
	Sfx.result(tier if result_type != "none" else "glitch")
	if tier == "legendary":
		Sfx.jackpot()
	Haptics.win(tier)
	SpinTelemetry.track_result(
		tier,
		result_type,
		_pending_multiplier,
		_pending_base_credits,
		_pending_credits,
		_pending_progress,
	)
	_refresh_hud()
	_reset_idle_state(false)
	var pending: Variant = Store.state.get("pendingEncounter", null)
	if typeof(pending) == TYPE_DICTIONARY:
		_show_social_encounter(pending)


func _on_tick() -> void:
	if _busy and not Preferences.reduced_motion:
		Sfx.tick()
		for reel in _reels:
			if reel.spinning:
				reel.tick_flash = 1.0


func _reset_idle_state(reset_message: bool = true) -> void:
	_busy = false
	_skip_enabled = false
	_spin_btn.disabled = false
	_spin_btn.text = "SPIN"
	_normalize_multiplier()
	if reset_message:
		_status_label.text = "NEON RUSH"
		_status_label.add_theme_color_override("font_color", Ui.NEON_MAGENTA)
		_result_banner.text = "MATCH 3  •  CRACK THE VAULT"
		_result_banner.add_theme_color_override("font_color", Ui.NEON_CYAN)
		_cabinet.set_mode(Ui.NEON_CYAN, false)
	_start_idle_animation()


func _start_idle_animation() -> void:
	if _spin_btn == null:
		return
	Juice.breathe(_spin_btn, 0.028, 0.85)
	if _mascot != null:
		Juice.breathe(_mascot, 0.018, 1.15)


func _stop_idle_animation() -> void:
	if _spin_btn != null:
		Juice.stop(_spin_btn)


func _parse_spin_error_details(data: Variant) -> Dictionary:
	if typeof(data) == TYPE_DICTIONARY and data.has("error"):
		var error: Variant = data["error"]
		if typeof(error) == TYPE_DICTIONARY and error.has("details"):
			var details: Variant = error["details"]
			if typeof(details) == TYPE_DICTIONARY:
				return details
	return {}


func _show_no_spins(_next_ms: int) -> void:
	_no_spins.visible = true
	_no_spins_label.text = "Network recharging…"
	Events.track("spins_empty")


func _resume_pending_encounter() -> void:
	var pending: Variant = Store.state.get("pendingEncounter", null)
	if typeof(pending) == TYPE_DICTIONARY:
		_show_social_encounter(pending)


func _open_network() -> void:
	if _social_busy:
		return
	_social_busy = true
	_show_network_loading()
	var loading_overlay := _social_overlay
	await _fetch_network_data()
	_social_busy = false
	if not is_instance_valid(loading_overlay) or loading_overlay.is_queued_for_deletion() or _social_overlay != loading_overlay:
		return
	_render_network()


func _show_network_loading() -> void:
	_clear_social_overlay()
	_social_busy = true
	var dialog := Neon.modal(self, "Connecting", 1, Ui.NEON_CYAN, "BACK TO SPIN")
	_social_overlay = dialog.overlay
	dialog.content.add_child(Neon.feature("SYNCING NETWORK", "Connecting to your crew, friends and trading channels…", 1, Ui.NEON_CYAN))


func _fetch_network_data() -> void:
	var friends_response := await Net.protected_request("GET", "/friends")
	var leaderboard_response := await Net.protected_request("GET", "/progression/leaderboard")
	var teams_response := await Net.protected_request("GET", "/teams")
	var team_leaderboard_response := await Net.protected_request("GET", "/teams/leaderboard")
	var trades_response := await Net.protected_request("GET", "/trades")
	_network_snapshot = friends_response.data if friends_response.ok and typeof(friends_response.data) == TYPE_DICTIONARY else {}
	_network_leaderboard = leaderboard_response.data if leaderboard_response.ok and typeof(leaderboard_response.data) == TYPE_DICTIONARY else {}
	_team_snapshot = teams_response.data if teams_response.ok and typeof(teams_response.data) == TYPE_DICTIONARY else {}
	_team_results = _team_snapshot.get("results", [])
	_team_leaderboard = team_leaderboard_response.data if team_leaderboard_response.ok and typeof(team_leaderboard_response.data) == TYPE_DICTIONARY else {}
	_trades_snapshot = trades_response.data if trades_response.ok and typeof(trades_response.data) == TYPE_DICTIONARY else {}


func _render_network() -> void:
	_network_view.render()


func _network_team_create(input: LineEdit) -> void:
	await _network_actions.team_create(input)


func _network_team_search(input: LineEdit) -> void:
	await _network_actions.team_search(input)


func _network_team_join(team_code: String) -> void:
	await _network_actions.team_join(team_code)


func _network_team_leave() -> void:
	await _network_actions.team_leave()


func _network_team_member_action(path: String, player_id: String, event_name: String) -> void:
	await _network_actions.team_member_action(path, player_id, event_name)


func _network_trade_create(friend_menu: OptionButton, offered_menu: OptionButton, requested_menu: OptionButton) -> void:
	await _network_actions.trade_create(friend_menu, offered_menu, requested_menu)


func _network_trade_action(path: String, trade_id: String, event_name: String, sync_state: bool) -> void:
	await _network_actions.trade_action(path, trade_id, event_name, sync_state)


func _network_search(query: LineEdit) -> void:
	await _network_actions.search(query)


func _network_update_profile(input: LineEdit) -> void:
	await _network_actions.update_profile(input)


func _network_friend_action(path: String, player_id: String, event_name: String) -> void:
	await _network_actions.friend_action(path, player_id, event_name)


func _network_friend_gift(player_id: String) -> void:
	await _network_actions.friend_gift(player_id)


func _network_team_quick_message(phrase_id: String) -> void:
	await _network_actions.team_quick_message(phrase_id)


func _network_team_help_request() -> void:
	await _network_actions.team_help_request()


func _network_team_help_donate(help_id: String) -> void:
	await _network_actions.team_help_donate(help_id)


func _network_select_target(player_id: String, source: String) -> void:
	await _network_actions.select_target(player_id, source)


func _clear_social_overlay() -> void:
	if is_instance_valid(_social_overlay):
		remove_child(_social_overlay)
		_social_overlay.queue_free()
	_social_overlay = null


func _show_social_encounter(encounter: Dictionary, banner: String = "") -> void:
	var kind := str(encounter.get("kind", ""))
	var encounter_id := str(encounter.get("encounterId", ""))
	if kind == "attack":
		if not _tracked_social_starts.has(encounter_id):
			_tracked_social_starts[encounter_id] = true
			Events.track("attack_started", {"encounterId": encounter_id, "multiplier": encounter.get("multiplier", 1), "corporate": encounter.get("corporate", false)})
	elif kind == "raid":
		if not _tracked_social_starts.has(encounter_id):
			_tracked_social_starts[encounter_id] = true
			Events.track("raid_started", {"encounterId": encounter_id, "multiplier": encounter.get("multiplier", 1), "corporate": encounter.get("corporate", false)})
	_encounter_view.show_encounter(encounter, banner)


func _resolve_attack(encounter: Dictionary, element_id: int, box: VBoxContainer) -> void:
	if _social_busy:
		return
	_social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/attack/resolve", {
		"encounterId": encounter.get("encounterId", ""), "elementId": element_id, "requestId": rid
	}, rid)
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		await _sync_social_state()
		var blocked := bool(response.data.get("blocked", false))
		Events.track("attack_completed", {"encounterId": encounter.get("encounterId", ""), "elementId": element_id, "blocked": blocked, "rewardCredits": response.data.get("rewardCredits", 0)})
		Events.track("currency_earned", {"currency": "credits", "amount": int(response.data.get("rewardCredits", 0)), "source": "attack"})
		_social_busy = false
		if is_instance_valid(box) and box.is_inside_tree():
			_show_social_result(("BLOCKED BY FIREWALL" if blocked else "NODE JAMMED") + "  •  +%s CR" % Ui.compact(int(response.data.get("rewardCredits", 0))), false)
	else:
		_social_busy = false
		Sfx.error()
		if is_instance_valid(box) and box.is_inside_tree():
			box.add_child(Ui.label("SIGNAL LOST — TRY AGAIN", 15, Ui.NEON_MAGENTA))


func _raid_pick(encounter: Dictionary, node_index: int) -> void:
	if _social_busy:
		return
	_social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/raid/pick", {
		"encounterId": encounter.get("encounterId", ""), "nodeIndex": node_index, "requestId": rid
	}, rid)
	if not response.ok or typeof(response.data) != TYPE_DICTIONARY:
		_social_busy = false
		Sfx.error()
		return
	var reveal: Dictionary = response.data.get("reveal", {})
	Events.track("raid_node_revealed", {"encounterId": encounter.get("encounterId", ""), "nodeIndex": node_index, "type": reveal.get("type", ""), "credits": reveal.get("credits", 0)})
	if bool(response.data.get("complete", false)):
		await _sync_social_state()
		var failed := bool(response.data.get("failed", false))
		Events.track("raid_failed" if failed else "raid_cashout", {"encounterId": encounter.get("encounterId", ""), "rewardCredits": response.data.get("rewardCredits", 0), "autoCashout": response.data.get("autoCashout", false)})
		if not failed:
			Events.track("currency_earned", {"currency": "credits", "amount": int(response.data.get("rewardCredits", 0)), "source": "raid"})
		_show_social_result("TRACE DETECTED — LOOT LOST" if failed else "VAULT SECURED  +%s CR" % Ui.compact(int(response.data.get("rewardCredits", 0))), failed)
		return
	await _sync_social_state()
	var pending: Variant = Store.state.get("pendingEncounter", null)
	if typeof(pending) == TYPE_DICTIONARY:
		_show_social_encounter(pending, "CACHE +%s CR" % Ui.compact(int(reveal.get("credits", 0))))


func _raid_cashout(encounter: Dictionary, box: VBoxContainer) -> void:
	if _social_busy:
		return
	_social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/raid/cashout", {
		"encounterId": encounter.get("encounterId", ""), "requestId": rid
	}, rid)
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		await _sync_social_state()
		Events.track("raid_cashout", {"encounterId": encounter.get("encounterId", ""), "rewardCredits": response.data.get("rewardCredits", 0), "autoCashout": false})
		Events.track("currency_earned", {"currency": "credits", "amount": int(response.data.get("rewardCredits", 0)), "source": "raid"})
		_show_social_result("CASH OUT  +%s CR" % Ui.compact(int(response.data.get("rewardCredits", 0))), false)
	else:
		_social_busy = false
		Sfx.error()
		if is_instance_valid(box) and box.is_inside_tree():
			box.add_child(Ui.label("CASH OUT IMPOSSIBLE", 15, Ui.NEON_MAGENTA))


func _show_social_result(message: String, failed: bool) -> void:
	_encounter_view.show_result(message, failed)


func _sync_social_state() -> void:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
		Store.apply_state(state_response.data)
