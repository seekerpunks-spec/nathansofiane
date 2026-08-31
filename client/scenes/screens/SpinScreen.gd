extends Control
## SpinScreen R23 — scène premium GPT Image, logique Godot interactive.
##
## Le serveur choisit toujours le résultat économique. Les symboles constituent
## uniquement une représentation animée de la réponse autoritaire.

signal navigate_requested(tab: String)

const SYMBOL_ATLAS := preload("res://assets/generated/api_gpt/slot_symbols_atlas.webp")
const SPIN_BG := preload("res://assets/generated/api_gpt/spin_background.webp")
const SLOT_FRAME := preload("res://assets/generated/api_gpt/slot_machine.webp")
const BYTE_MASCOT := preload("res://assets/generated/api_gpt/byte.webp")
const SPIN_BUTTON_ART := preload("res://assets/generated/api_gpt/spin_button.webp")
const SpinVisuals := preload("res://scripts/components/SpinVisuals.gd")
const SpinNetworkView := preload("res://scripts/components/SpinNetworkView.gd")
const SpinEncounterView := preload("res://scripts/components/SpinEncounterView.gd")
const SpinNetworkActions := preload("res://scripts/components/SpinNetworkActions.gd")
const SpinTelemetry := preload("res://scripts/components/SpinTelemetry.gd")
const SYMBOLS := ["credits", "shield", "hack", "vault", "energy", "glitch"]

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
var _idle_tween: Tween

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
	var bg := TextureRect.new()
	bg.texture = SPIN_BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var atmosphere := SpinVisuals.AnimatedBackdrop.new()
	atmosphere.set_anchors_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(atmosphere)

	_build_header()
	_build_event_banner()
	_build_cabinet()
	_build_lower_controls()

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


func _build_header() -> void:
	var credits_chip := _stat_chip(Vector2(14, 12), Vector2(238, 56), Ui.GOLD)
	var credits_row := HBoxContainer.new()
	credits_row.alignment = BoxContainer.ALIGNMENT_CENTER
	credits_row.add_theme_constant_override("separation", 9)
	credits_row.add_child(Ui.label("●", 24, Ui.GOLD))
	_credits_value = Ui.label("0", 21, Color("#2A2551"))
	credits_row.add_child(_credits_value)
	credits_chip.add_child(credits_row)
	add_child(credits_chip)

	var spins_chip := _stat_chip(Vector2(284, 12), Vector2(158, 56), Ui.NEON_CYAN)
	_spins_value = Ui.label("⚡ 0", 21, Color("#11225A"))
	_spins_value.position = Vector2(0, 0)
	_spins_value.size = Vector2(146, 50)
	spins_chip.add_child(_spins_value)
	add_child(spins_chip)

	var menu := _promo_button("NET", Ui.NEON_MAGENTA)
	menu.position = Vector2(458, 12)
	menu.size = Vector2(68, 56)
	menu.add_theme_font_size_override("font_size", 25)
	menu.pressed.connect(_open_network)
	add_child(menu)


func _stat_chip(pos: Vector2, chip_size: Vector2, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = chip_size
	panel.add_theme_stylebox_override(
		"panel", _game_box(Color("#FFF0C0"), Color(accent, 0.98), 22, 4, 7)
	)
	return panel


func _game_box(bg: Color, border: Color, radius: int, width: int, shadow: int = 6) -> StyleBoxFlat:
	var box := Ui.style_box(bg, border, radius, width)
	box.set_content_margin_all(8)
	box.shadow_color = Color("#182356", 0.48)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0, 5)
	return box


func _promo_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color("#121A4A"))
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _game_box(accent, Color.WHITE, 18, 3, 7))
	button.add_theme_stylebox_override("hover", _game_box(accent.lightened(0.08), Color.WHITE, 18, 4, 9))
	button.add_theme_stylebox_override("pressed", _game_box(accent.darkened(0.16), Ui.GOLD, 18, 4, 4))
	return button


func _build_event_banner() -> void:
	var rush := _promo_button("RUSH\n+10", Ui.NEON_MAGENTA)
	rush.position = Vector2(18, 82)
	rush.size = Vector2(82, 66)
	rush.pressed.connect(func() -> void: navigate_requested.emit("missions"))
	add_child(rush)

	_event_label = Ui.label("CYBER SEEKER", 29, Ui.GOLD)
	_event_label.position = Vector2(105, 76)
	_event_label.size = Vector2(330, 42)
	add_child(_event_label)

	_district_label = Ui.label("NEON SLUMS  •  NODE 01", 13, Color.WHITE)
	_district_label.position = Vector2(110, 114)
	_district_label.size = Vector2(320, 26)
	add_child(_district_label)

	_event_timer = Ui.label("LIVE", 11, Color("#202151"))
	_event_timer.position = Vector2(18, 121)
	_event_timer.size = Vector2(82, 20)
	_event_timer.visible = false
	add_child(_event_timer)

	var loot := _promo_button("LOOT", Ui.NEON_BLUE)
	loot.position = Vector2(444, 82)
	loot.size = Vector2(78, 44)
	loot.pressed.connect(func() -> void: navigate_requested.emit("collection"))
	add_child(loot)


func _build_cabinet() -> void:
	_cabinet_root = Control.new()
	_cabinet_root.position = Vector2(10, 142)
	_cabinet_root.size = Vector2(520, 540)
	add_child(_cabinet_root)

	# Le contrôleur conserve l'état d'accentuation des gains, mais le contour
	# technique R18 reste masqué au profit du véritable décor illustré.
	_cabinet = SpinVisuals.SlotCabinet.new()
	_cabinet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cabinet.visible = false
	_cabinet_root.add_child(_cabinet)

	var cabinet_art := TextureRect.new()
	cabinet_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cabinet_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cabinet_art.custom_minimum_size = Vector2.ZERO
	cabinet_art.texture = SLOT_FRAME
	cabinet_art.set_position(Vector2.ZERO)
	cabinet_art.set_size(Vector2(520, 540))
	cabinet_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cabinet_root.add_child(cabinet_art)

	_status_label = Ui.label("NEON RUSH", 22, Ui.NEON_MAGENTA)
	_status_label.position = Vector2(132, 45)
	_status_label.size = Vector2(256, 40)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cabinet_root.add_child(_status_label)

	_result_banner = Ui.label("MATCH 3  •  CRACK THE VAULT", 11, Color.WHITE)
	_result_banner.position = Vector2(132, 84)
	_result_banner.size = Vector2(256, 26)
	_result_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cabinet_root.add_child(_result_banner)

	var reel_x := [116.0, 225.0, 337.0]
	for i in 3:
		var reel := SpinVisuals.SlotReel.new()
		reel.atlas = SYMBOL_ATLAS
		reel.symbols = SYMBOLS
		reel.position = Vector2(reel_x[i], 215)
		reel.size = Vector2(90 if i == 1 else 88, 186)
		reel.reel_index = i
		reel.final_symbol = SYMBOLS[(i * 2) % SYMBOLS.size()]
		reel.clip_contents = true
		_cabinet_root.add_child(reel)
		_reels.append(reel)

	_regen_bar = _make_progress()
	_regen_bar.position = Vector2(138, 438)
	_regen_bar.size = Vector2(244, 31)
	_cabinet_root.add_child(_regen_bar)

	_regen_label = Ui.label("", 11, Color.WHITE)
	_regen_label.position = Vector2(139, 438)
	_regen_label.size = Vector2(242, 30)
	_cabinet_root.add_child(_regen_label)


func _build_lower_controls() -> void:
	var mascot := TextureRect.new()
	mascot.texture = BYTE_MASCOT
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.position = Vector2(4, 714)
	mascot.size = Vector2(168, 198)
	mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mascot)

	_spin_btn = _big_button("SPIN")
	_spin_btn.position = Vector2(148, 732)
	_spin_btn.size = Vector2(246, 106)
	_spin_btn.pivot_offset = _spin_btn.size / 2.0
	_spin_btn.pressed.connect(_on_spin_pressed)
	var spin_art := TextureRect.new()
	spin_art.texture = SPIN_BUTTON_ART
	spin_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spin_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spin_art.position = Vector2(-20, -30)
	spin_art.size = Vector2(286, 201)
	spin_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spin_art.show_behind_parent = true
	_spin_btn.add_child(spin_art)
	add_child(_spin_btn)

	_multiplier_btn = _promo_button("BET  ×1", Ui.NEON_MAGENTA)
	_multiplier_btn.position = Vector2(184, 850)
	_multiplier_btn.size = Vector2(174, 58)
	_multiplier_btn.add_theme_font_size_override("font_size", 17)
	_multiplier_btn.pressed.connect(_cycle_multiplier)
	add_child(_multiplier_btn)

	var district_btn := _promo_button("CITY", Color("#1867C9"))
	district_btn.position = Vector2(430, 758)
	district_btn.size = Vector2(84, 68)
	district_btn.add_theme_font_size_override("font_size", 15)
	district_btn.pressed.connect(func() -> void: navigate_requested.emit("district"))
	add_child(district_btn)


func _big_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 36)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color("#342047"))
	button.add_theme_constant_override("outline_size", 7)
	button.add_theme_color_override("font_disabled_color", Color.WHITE)
	return button


func _make_progress() -> ProgressBar:
	var bar := Ui.progress_bar(Ui.NEON_CYAN, 32)
	bar.add_theme_stylebox_override("background", _game_box(Color("#17244E"), Color("#D8E7FF"), 15, 4, 4))
	bar.add_theme_stylebox_override("fill", _game_box(Ui.NEON_CYAN, Color("#B9FFFF"), 15, 2, 3))
	bar.value = 0
	return bar


func _build_no_spins() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false

	var dim := ColorRect.new()
	dim.color = Color("#030B26", 0.90)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(390, 0)
	box.add_theme_constant_override("separation", 18)
	box.add_child(Ui.label("ENERGY EMPTY!", 32, Ui.NEON_MAGENTA))
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
	center.add_child(box)
	overlay.add_child(center)
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
	var events := Config.events()
	if events.is_empty() or typeof(events[0]) != TYPE_DICTIONARY:
		_event_timer.text = "LIVE"
		return
	var event: Dictionary = events[0]
	var ends_at := int(event.get("endsAtMs", 0))
	var points := 0
	var sources: Variant = event.get("pointSources", [])
	if typeof(sources) == TYPE_ARRAY:
		for source in sources:
			if typeof(source) == TYPE_DICTIONARY and str(source.get("action", "")) == "spin":
				points = int(source.get("points", 0))
				break
	var remaining := maxi(0, ends_at - Store.now_ms())
	_event_timer.text = "+%d" % points if points > 0 else Ui.mmss_long(remaining)


func _refresh_hud() -> void:
	_spins_value.text = "⚡ " + str(Store.spins())
	_credits_value.text = Ui.compact(Store.credits())
	_normalize_multiplier()
	var districts := Config.districts()
	var active_district: Dictionary = {}
	var completed := int(Store.state.get("districtIndex", 0))
	for candidate in districts:
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		active_district = candidate
		if int(candidate.get("id", 0)) > completed:
			break
	if not active_district.is_empty():
		var network_power := int(Store.state.get("progression", {}).get("score", 0))
		_district_label.text = (
			str(active_district.get("name", "NEON SLUMS")).to_upper()
			+ " · NODE %02d" % int(active_district.get("id", 1))
			+ " · FW %d/%d" % [int(Store.state.get("firewallCharges", 0)), int(Store.state.get("firewallMax", 3))]
			+ " · PWR %s" % Ui.compact(network_power)
		)


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
	_reel_tweens.clear()
	_landed_count = 0
	var tier := str(_pending_outcome.get("tier", "common")).to_lower()
	_anticipation = tier in ["rare", "epic", "legendary"]
	_skip_enabled = true
	_spin_btn.disabled = false
	_spin_btn.text = "STOP NOW"
	_status_label.text = "GOOD LUCK!"
	_tick_timer.start()

	for i in 3:
		var reel: Control = _reels[i]
		reel.start_spin()
		var duration := 0.24 + i * 0.08 if Preferences.reduced_motion else 0.92 + i * 0.30
		if i == 2 and _anticipation and not Preferences.reduced_motion:
			duration += 0.34
		var travel := SpinVisuals.SlotReel.CELL_HEIGHT * float(12 + i * 4)
		var tween := create_tween()
		if Preferences.reduced_motion:
			tween.tween_property(reel, "roll_offset", travel, duration) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(reel, "roll_offset", SpinVisuals.SlotReel.CELL_HEIGHT * 2.0, 0.14) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_property(reel, "roll_offset", travel - SpinVisuals.SlotReel.CELL_HEIGHT * 3.0, duration - 0.44) \
				.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(reel, "roll_offset", travel, 0.30) \
				.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_land_reel.bind(i, finals[i]))
		_reel_tweens.append(tween)


func _land_reel(index: int, symbol: String) -> void:
	if _revealed:
		return
	var reel: Control = _reels[index]
	reel.land(symbol)
	reel.pivot_offset = reel.size / 2.0
	reel.scale = Vector2(1.07, 0.94)
	var bounce := create_tween()
	bounce.tween_property(reel, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.reel_stop(index)
	Haptics.vibrate(0.25 + index * 0.16, 20 + index * 8)
	_landed_count += 1

	if index == 1 and _anticipation:
		_status_label.text = "ALMOST!"
		_status_label.add_theme_color_override("font_color", Ui.NEON_MAGENTA)
		_cabinet.set_mode(Ui.NEON_MAGENTA, false)
		Sfx.anticipation()
		_anticipation_pulse()
	if _landed_count >= 3:
		_on_landed()


func _skip_slots() -> void:
	if not _busy or _revealed:
		return
	_skip_enabled = false
	for tween in _reel_tweens:
		if tween != null and tween.is_running():
			tween.kill()
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

	_impact_result(tier, accent)
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


func _impact_result(tier: String, accent: Color) -> void:
	_result_banner.pivot_offset = _result_banner.size / 2.0
	_result_banner.scale = Vector2(1.38, 1.38)
	var pop := create_tween()
	pop.tween_property(_result_banner, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var count := 18
	var flash_alpha := 0.12
	match tier:
		"rare":
			count = 34
			flash_alpha = 0.20
		"epic":
			count = 58
			flash_alpha = 0.32
		"legendary":
			count = 90
			flash_alpha = 0.52
	_particles.emit_burst(Vector2(270, 500), accent, count)

	_flash.color = Color(accent, flash_alpha)
	var flash_tween := create_tween()
	flash_tween.tween_property(_flash, "color", Color(accent, 0), 0.46)

	if not Preferences.reduced_motion:
		var shake := create_tween()
		shake.tween_property(_cabinet_root, "position", Vector2(3, 145), 0.035)
		shake.tween_property(_cabinet_root, "position", Vector2(17, 139), 0.035)
		shake.tween_property(_cabinet_root, "position", Vector2(6, 144), 0.035)
		shake.tween_property(_cabinet_root, "position", Vector2(13, 141), 0.035)
		shake.tween_property(_cabinet_root, "position", Vector2(10, 142), 0.06) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _anticipation_pulse() -> void:
	if Preferences.reduced_motion:
		return
	_cabinet_root.pivot_offset = _cabinet_root.size / 2.0
	var pulse := create_tween()
	pulse.tween_property(_cabinet_root, "scale", Vector2(1.025, 1.025), 0.18)
	pulse.tween_property(_cabinet_root, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
		_result_banner.add_theme_color_override("font_color", Color("#272554"))
		_cabinet.set_mode(Ui.NEON_CYAN, false)
	_start_idle_animation()


func _start_idle_animation() -> void:
	if Preferences.reduced_motion or _spin_btn == null:
		return
	_stop_idle_animation()
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_spin_btn, "scale", Vector2(1.025, 1.025), 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_spin_btn, "scale", Vector2.ONE, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_idle_animation() -> void:
	if _idle_tween != null and _idle_tween.is_running():
		_idle_tween.kill()
	if _spin_btn != null:
		_spin_btn.scale = Vector2.ONE


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
	await _fetch_network_data()
	_social_busy = false
	_render_network()


func _show_network_loading() -> void:
	_clear_social_overlay()
	_social_busy = true
	_social_overlay = ColorRect.new()
	_social_overlay.color = Color(0.015, 0.02, 0.07, 0.97)
	_social_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_social_overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(Ui.label("SYNCING NETWORK…", 24, Ui.NEON_CYAN))
	_social_overlay.add_child(center)
	add_child(_social_overlay)


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
		box.add_child(Ui.label("BLOCKED BY FIREWALL" if blocked else "NODE JAMMED", 22, Ui.GOLD if blocked else Ui.NEON_MAGENTA))
		box.add_child(Ui.label("+%s CR" % Ui.compact(int(response.data.get("rewardCredits", 0))), 20, Ui.GOLD))
		var close := Ui.button("CONTINUE", Ui.NEON_CYAN)
		close.pressed.connect(_clear_social_overlay)
		box.add_child(close)
	else:
		_social_busy = false
		Sfx.error()
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
		box.add_child(Ui.label("CASH OUT IMPOSSIBLE", 15, Ui.NEON_MAGENTA))


func _show_social_result(message: String, failed: bool) -> void:
	_encounter_view.show_result(message, failed)


func _sync_social_state() -> void:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
		Store.apply_state(state_response.data)
