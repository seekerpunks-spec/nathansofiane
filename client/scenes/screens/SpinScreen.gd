extends Control
## SpinScreen R23 — scène premium GPT Image, logique Godot interactive.
##
## Le serveur choisit toujours le résultat économique. Les symboles constituent
## uniquement une représentation animée de la réponse autoritaire.

signal navigate_requested(tab: String)

const SYMBOL_ATLAS := preload("res://assets/generated/api_gpt/slot_symbols_atlas.png")
const SPIN_BG := preload("res://assets/generated/api_gpt/spin_background.png")
const SLOT_FRAME := preload("res://assets/generated/api_gpt/slot_machine.png")
const BYTE_MASCOT := preload("res://assets/generated/api_gpt/byte.png")
const SPIN_BUTTON_ART := preload("res://assets/generated/api_gpt/spin_button.png")
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
var _cabinet: SlotCabinet
var _particles: ParticleBurst
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
var _network_message := ""


func _ready() -> void:
	_build()
	_refresh_hud()
	_start_idle_animation()
	Store.state_changed.connect(_refresh_hud)
	Store.no_spins.connect(_show_no_spins)
	_resume_pending_encounter.call_deferred()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = SPIN_BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var atmosphere := AnimatedBackdrop.new()
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

	_particles = ParticleBurst.new()
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
	_cabinet = SlotCabinet.new()
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
		var reel := SlotReel.new()
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
	_no_spins_label = Ui.label("Recharge réseau en cours…", 16, Ui.TEXT_DIM)
	_no_spins_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_no_spins_label)

	var store := Ui.button("OPTIONS DE RECHARGE", Ui.NEON_CYAN)
	store.pressed.connect(func() -> void:
		overlay.visible = false
		navigate_requested.emit("store")
	)
	box.add_child(store)

	var missions := Ui.button("RÉCUPÉRER DES RÉCOMPENSES", Ui.GOLD, true)
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
			_no_spins_label.text = "Prochain signal dans " + Ui.mmss(Store.regen_remaining_ms())


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
		_final_symbols = _symbols_for_result(_pending_outcome)
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
		_result_banner.text = "ERREUR RÉSEAU · RÉESSAIE"
		_result_banner.add_theme_color_override("font_color", Ui.NEON_MAGENTA)
		_reset_idle_state(false)


func _symbols_for_result(outcome: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var result_type := str(outcome.get("type", "credits")).to_lower()
	var tier := str(outcome.get("tier", "common")).to_lower()
	if result_type in ["none", "glitch"]:
		result.assign(["glitch", "credits", "energy"])
		return result
	var symbol := "credits"
	match result_type:
		"attack":
			symbol = "hack"
		"raid":
			symbol = "vault"
		"shield":
			symbol = "shield"
		"chest":
			symbol = "energy"
		"card":
			symbol = "hack"
	if result_type != "credits":
		result.assign([symbol, symbol, symbol])
		return result
	match tier:
		"uncommon":
			symbol = "energy"
		"rare":
			symbol = "shield"
		"epic":
			symbol = "hack"
		"legendary":
			symbol = "vault"
	result.assign([symbol, symbol, symbol])
	return result


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
		var reel: SlotReel = _reels[i]
		reel.start_spin()
		var duration := 0.24 + i * 0.08 if Preferences.reduced_motion else 0.92 + i * 0.30
		if i == 2 and _anticipation and not Preferences.reduced_motion:
			duration += 0.34
		var travel := SlotReel.CELL_HEIGHT * float(12 + i * 4)
		var tween := create_tween()
		if Preferences.reduced_motion:
			tween.tween_property(reel, "roll_offset", travel, duration) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(reel, "roll_offset", SlotReel.CELL_HEIGHT * 2.0, 0.14) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_property(reel, "roll_offset", travel - SlotReel.CELL_HEIGHT * 3.0, duration - 0.44) \
				.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(reel, "roll_offset", travel, 0.30) \
				.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_land_reel.bind(i, finals[i]))
		_reel_tweens.append(tween)


func _land_reel(index: int, symbol: String) -> void:
	if _revealed:
		return
	var reel: SlotReel = _reels[index]
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
		var reel: SlotReel = _reels[i]
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
	Events.track("spin_completed", {
		"tier": tier,
		"type": result_type,
		"multiplier": _pending_multiplier,
		"spinsSpent": _pending_multiplier,
		"baseCredits": _pending_base_credits,
		"credits": _pending_credits,
	})
	if _pending_credits > 0:
		Events.track("currency_earned", {
			"currency": "credits",
			"amount": _pending_credits,
			"source": "spin",
			"multiplier": _pending_multiplier,
		})
	for event_progress in _pending_progress.get("events", []):
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
	_no_spins_label.text = "Recharge réseau en cours…"
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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(Ui.label("SYNCING NETWORK…", 24, Ui.NEON_CYAN))
	_social_overlay.add_child(center)
	add_child(_social_overlay)


func _fetch_network_data() -> void:
	var friends_response := await Net.protected_request("GET", "/friends")
	var leaderboard_response := await Net.protected_request("GET", "/progression/leaderboard")
	_network_snapshot = friends_response.data if friends_response.ok and typeof(friends_response.data) == TYPE_DICTIONARY else {}
	_network_leaderboard = leaderboard_response.data if leaderboard_response.ok and typeof(leaderboard_response.data) == TYPE_DICTIONARY else {}


func _render_network() -> void:
	_clear_social_overlay()
	_social_overlay = ColorRect.new()
	_social_overlay.color = Color(0.015, 0.02, 0.07, 0.97)
	_social_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_CYAN)
	panel.custom_minimum_size = Vector2(500, 820)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	var title_row := HBoxContainer.new()
	var title := Ui.label("SEEKER NETWORK", 28, Ui.NEON_CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close := Ui.button("✕", Ui.NEON_MAGENTA, true)
	close.pressed.connect(_clear_social_overlay)
	title_row.add_child(close)
	shell.add_child(title_row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 720)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.style_scroll(scroll, Ui.NEON_CYAN)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_build_network_profile(content)
	_build_network_search(content)
	_build_network_requests(content)
	_build_network_friends(content)
	_build_network_revenge(content)
	_build_network_leaderboard(content)
	scroll.add_child(content)
	shell.add_child(scroll)
	panel.add_child(shell)
	center.add_child(panel)
	_social_overlay.add_child(center)
	add_child(_social_overlay)


func _network_section(parent: VBoxContainer, title: String) -> void:
	var label := Ui.label(title, 17, Ui.GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(label)


func _build_network_profile(parent: VBoxContainer) -> void:
	_network_section(parent, "PROFILE")
	var profile: Dictionary = Store.state.get("profile", {})
	var progression: Dictionary = Store.state.get("progression", {})
	parent.add_child(Ui.label("%s  •  %s" % [str(profile.get("playerId", "NO CODE")), str(progression.get("name", "NETWORK POWER")).to_upper()], 13, Ui.TEXT_DIM))
	parent.add_child(Ui.label("%s PWR  •  DISTRICT %d" % [Ui.compact(int(progression.get("score", 0))), int(profile.get("districtIndex", 0)) + 1], 19, Ui.TEXT))
	var edit_row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = str(profile.get("displayName", "Runner"))
	name_edit.max_length = 24
	name_edit.custom_minimum_size.x = 300
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_row.add_child(name_edit)
	var save := Ui.button("SAVE", Ui.NEON_CYAN)
	save.pressed.connect(_network_update_profile.bind(name_edit))
	edit_row.add_child(save)
	parent.add_child(edit_row)
	if _network_message != "":
		parent.add_child(Ui.label(_network_message, 13, Ui.NEON_MAGENTA))


func _build_network_search(parent: VBoxContainer) -> void:
	_network_section(parent, "FIND A PLAYER")
	var row := HBoxContainer.new()
	var query := LineEdit.new()
	query.placeholder_text = "Friend code or name"
	query.max_length = 24
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(query)
	var search := Ui.button("SEARCH", Ui.NEON_CYAN)
	search.pressed.connect(_network_search.bind(query))
	row.add_child(search)
	parent.add_child(row)
	for result in _network_results:
		if typeof(result) != TYPE_DICTIONARY:
			continue
		var result_row := HBoxContainer.new()
		var result_label := Ui.label("%s  •  %s PWR" % [str(result.get("displayName", "Runner")), Ui.compact(int(result.get("score", 0)))], 13, Ui.TEXT)
		result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_row.add_child(result_label)
		var relationship := str(result.get("relationship", "none"))
		var action := Ui.button("ADD" if relationship == "none" else relationship.to_upper(), Ui.NEON_MAGENTA, relationship != "none")
		action.disabled = relationship != "none"
		if relationship == "none":
			action.pressed.connect(_network_friend_action.bind("/friends/request", str(result.get("playerId", "")), "friend_request_sent"))
		result_row.add_child(action)
		parent.add_child(result_row)


func _build_network_requests(parent: VBoxContainer) -> void:
	var incoming: Array = _network_snapshot.get("incoming", [])
	if incoming.is_empty():
		return
	_network_section(parent, "REQUESTS")
	for request in incoming:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		var row := HBoxContainer.new()
		var label := Ui.label(str(request.get("displayName", "Runner")), 13, Ui.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var accept := Ui.button("ACCEPT", Ui.GREEN)
		accept.pressed.connect(_network_friend_action.bind("/friends/accept", str(request.get("playerId", "")), "friend_request_accepted"))
		row.add_child(accept)
		var decline := Ui.button("DECLINE", Ui.NEON_MAGENTA, true)
		decline.pressed.connect(_network_friend_action.bind("/friends/decline", str(request.get("playerId", "")), "friend_request_declined"))
		row.add_child(decline)
		parent.add_child(row)


func _build_network_friends(parent: VBoxContainer) -> void:
	var friends: Array = _network_snapshot.get("friends", [])
	_network_section(parent, "FRIENDS  •  %d" % friends.size())
	if friends.is_empty():
		parent.add_child(Ui.label("Ajoute un joueur avec son code ami.", 13, Ui.TEXT_DIM))
		return
	for friend in friends:
		if typeof(friend) != TYPE_DICTIONARY:
			continue
		var row := HBoxContainer.new()
		var label := Ui.label("%s  •  %s PWR" % [str(friend.get("displayName", "Runner")), Ui.compact(int(friend.get("score", 0)))], 13, Ui.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var target := Ui.button("TARGET", Ui.NEON_MAGENTA)
		target.pressed.connect(_network_select_target.bind(str(friend.get("playerId", "")), "friend"))
		row.add_child(target)
		parent.add_child(row)


func _build_network_revenge(parent: VBoxContainer) -> void:
	var attacks: Array = _network_snapshot.get("recentAttacks", [])
	if attacks.is_empty():
		return
	_network_section(parent, "RECENT SIGNAL JAMS")
	for attack in attacks.slice(0, mini(5, attacks.size())):
		if typeof(attack) != TYPE_DICTIONARY:
			continue
		var row := HBoxContainer.new()
		var label := Ui.label("%s  •  %s" % [str(attack.get("displayName", "Runner")), "BLOCKED" if bool(attack.get("blocked", false)) else "JAMMED"], 13, Ui.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var revenge := Ui.button("REVENGE", Ui.NEON_MAGENTA)
		revenge.disabled = not bool(attack.get("canRevenge", false))
		revenge.pressed.connect(_network_select_target.bind(str(attack.get("playerId", "")), "revenge"))
		row.add_child(revenge)
		parent.add_child(row)


func _build_network_leaderboard(parent: VBoxContainer) -> void:
	_network_section(parent, "GLOBAL NETWORK")
	parent.add_child(Ui.label("YOUR RANK  •  #%d" % int(_network_leaderboard.get("playerRank", 0)), 14, Ui.NEON_CYAN))
	var entries: Array = _network_leaderboard.get("entries", [])
	for entry in entries.slice(0, mini(10, entries.size())):
		if typeof(entry) == TYPE_DICTIONARY:
			var line := Ui.label("#%d  %s  •  %s PWR" % [int(entry.get("rank", 0)), str(entry.get("displayName", "Runner")), Ui.compact(int(entry.get("score", 0)))], 13, Ui.TEXT_DIM)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			parent.add_child(line)


func _network_search(query: LineEdit) -> void:
	if _social_busy or query.text.strip_edges().length() < 2:
		return
	_social_busy = true
	var response := await Net.protected_request("GET", "/players/search?q=" + query.text.strip_edges().uri_encode())
	_network_results = response.data.get("results", []) if response.ok and typeof(response.data) == TYPE_DICTIONARY else []
	_network_message = "" if response.ok else "SEARCH FAILED"
	_social_busy = false
	_render_network()


func _network_update_profile(input: LineEdit) -> void:
	if _social_busy:
		return
	_social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/profile", {"displayName": input.text, "requestId": rid}, rid)
	if response.ok:
		Events.track("profile_updated")
		var state_response := await Net.protected_request("GET", "/state")
		if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
			Store.apply_state(state_response.data)
	_network_message = "PROFILE UPDATED" if response.ok else "INVALID PROFILE NAME"
	await _fetch_network_data()
	_social_busy = false
	_render_network()


func _network_friend_action(path: String, player_id: String, event_name: String) -> void:
	if _social_busy:
		return
	_social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", path, {"friendCode": player_id, "requestId": rid}, rid)
	if response.ok:
		Events.track(event_name, {"playerId": player_id})
	_network_message = "NETWORK UPDATED" if response.ok else "ACTION REFUSED"
	_network_results.clear()
	await _fetch_network_data()
	_social_busy = false
	_render_network()


func _network_select_target(player_id: String, source: String) -> void:
	if _social_busy:
		return
	_social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/social/target", {"friendCode": player_id, "source": source, "requestId": rid}, rid)
	if response.ok:
		Events.track("social_target_selected", {"playerId": player_id, "source": source})
	_network_message = "TARGET ARMED FOR NEXT SIGNAL JAM" if response.ok else "TARGET NOT AVAILABLE"
	await _fetch_network_data()
	_social_busy = false
	_render_network()


func _clear_social_overlay() -> void:
	if is_instance_valid(_social_overlay):
		remove_child(_social_overlay)
		_social_overlay.queue_free()
	_social_overlay = null


func _show_social_encounter(encounter: Dictionary, banner: String = "") -> void:
	_clear_social_overlay()
	_social_busy = false
	_social_overlay = ColorRect.new()
	_social_overlay.color = Color(0.015, 0.02, 0.07, 0.97)
	_social_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_MAGENTA)
	panel.custom_minimum_size = Vector2(440, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var kind := str(encounter.get("kind", ""))
	var encounter_id := str(encounter.get("encounterId", ""))
	box.add_child(Ui.label("SIGNAL JAM" if kind == "attack" else "GHOST VAULT", 31, Ui.NEON_MAGENTA if kind == "attack" else Ui.GOLD))
	box.add_child(Ui.label("TARGET  •  " + str(encounter.get("target", "NEON CORP")), 14, Ui.TEXT_DIM))
	if banner != "":
		box.add_child(Ui.label(banner, 18, Ui.NEON_CYAN))
	if kind == "attack":
		box.add_child(Ui.label("Choisis le nœud à brouiller. Un Firewall adverse peut absorber l'impulsion.", 14, Ui.TEXT))
		var choices: Array = encounter.get("choices", [])
		for element_id in choices:
			var attack := Ui.button("JAM NODE %d" % int(element_id), Ui.NEON_MAGENTA)
			attack.pressed.connect(_resolve_attack.bind(encounter, int(element_id), box))
			box.add_child(attack)
		if not _tracked_social_starts.has(encounter_id):
			_tracked_social_starts[encounter_id] = true
			Events.track("attack_started", {"encounterId": encounter_id, "multiplier": encounter.get("multiplier", 1), "corporate": encounter.get("corporate", false)})
	else:
		var unbanked := int(encounter.get("unbankedCredits", 0))
		box.add_child(Ui.label("UNBANKED  •  %s CR" % Ui.compact(unbanked), 19, Ui.GOLD))
		box.add_child(Ui.label("Chaque cache augmente le butin. Une TRACE détruit tout le non-encaissé.", 14, Ui.TEXT))
		var grid := GridContainer.new()
		grid.columns = 3
		var picked: Array = encounter.get("picked", [])
		for node_index in int(encounter.get("nodeCount", 6)):
			var node := Ui.button("NODE %d" % (node_index + 1), Ui.NEON_CYAN, true)
			node.disabled = picked.has(node_index)
			node.pressed.connect(_raid_pick.bind(encounter, node_index))
			grid.add_child(node)
		box.add_child(grid)
		if bool(encounter.get("canCashout", false)):
			var cashout := Ui.button("CASH OUT  %s CR" % Ui.compact(unbanked), Ui.GOLD)
			cashout.pressed.connect(_raid_cashout.bind(encounter, box))
			box.add_child(cashout)
		if not _tracked_social_starts.has(encounter_id):
			_tracked_social_starts[encounter_id] = true
			Events.track("raid_started", {"encounterId": encounter_id, "multiplier": encounter.get("multiplier", 1), "corporate": encounter.get("corporate", false)})
	var later := Ui.button("REVENIR PLUS TARD", Ui.TEXT_DIM, true)
	later.pressed.connect(_clear_social_overlay)
	box.add_child(later)
	panel.add_child(box)
	center.add_child(panel)
	_social_overlay.add_child(center)
	add_child(_social_overlay)


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
		box.add_child(Ui.label("SIGNAL LOST — RÉESSAIE", 15, Ui.NEON_MAGENTA))


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
	_clear_social_overlay()
	_social_busy = false
	_social_overlay = ColorRect.new()
	_social_overlay.color = Color(0.015, 0.02, 0.07, 0.97)
	_social_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 410
	box.add_theme_constant_override("separation", 16)
	box.add_child(Ui.label(message, 25, Ui.NEON_MAGENTA if failed else Ui.GOLD))
	var close := Ui.button("CONTINUE", Ui.NEON_CYAN)
	close.pressed.connect(_clear_social_overlay)
	box.add_child(close)
	center.add_child(box)
	_social_overlay.add_child(center)
	add_child(_social_overlay)


func _sync_social_state() -> void:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
		Store.apply_state(state_response.data)


class SlotCabinet extends Control:
	var accent := Ui.NEON_CYAN
	var win_mode := false
	var _time := 0.0

	func _ready() -> void:
		set_process(true)

	func set_mode(color: Color, winning: bool) -> void:
		accent = color
		win_mode = winning
		queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _box(color: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
		return Ui.style_box(color, border, radius, width)

	func _draw() -> void:
		var breathe := 0.60 + sin(_time * (4.0 if win_mode else 1.8)) * 0.18
		var outer := _box(Color("#080D1D"), Color(accent, breathe), 34, 4)
		outer.shadow_color = Color(accent, 0.35 + breathe * 0.20)
		outer.shadow_size = 24 if not win_mode else 34
		draw_style_box(outer, Rect2(4, 4, size.x - 8, size.y - 8))

		draw_style_box(
			_box(Color("#151E3D"), Color(accent, 0.88), 22, 2),
			Rect2(30, 22, size.x - 60, 58)
		)
		draw_style_box(
			_box(Color("#050712"), Color("#35446E"), 26, 2),
			Rect2(24, 96, size.x - 48, 342)
		)

		draw_rect(Rect2(30, 265, size.x - 60, 3), Color(accent, 0.92))
		draw_line(Vector2(30, 266), Vector2(size.x - 30, 266), Color(accent, 0.9), 3.0)

		for i in 7:
			var energy := 0.16 + 0.10 * sin(_time * 3.0 + i)
			draw_rect(Rect2(18 + i * 72, 92, 34, 3), Color(accent, energy))

		var corner := 18.0
		var corners := [
			Vector2(18, 18), Vector2(size.x - 18, 18),
			Vector2(18, size.y - 18), Vector2(size.x - 18, size.y - 18),
		]
		for point in corners:
			draw_circle(point, 4.0 + sin(_time * 2.0) * 1.2, Color(accent, 0.85))
			draw_arc(point, corner, 0, TAU, 20, Color(accent, 0.20), 2.0)


class SlotReel extends Control:
	const CELL_HEIGHT := 58.0

	var atlas: Texture2D
	var symbols: Array = []
	var reel_index := 0
	var spinning := false
	var final_symbol := "credits"
	var roll_offset := 0.0:
		set(value):
			roll_offset = value
			queue_redraw()
	var tick_flash := 0.0
	var _time := 0.0

	func _ready() -> void:
		set_process(true)

	func start_spin() -> void:
		spinning = true
		roll_offset = 0.0
		queue_redraw()

	func land(symbol: String) -> void:
		spinning = false
		final_symbol = symbol
		roll_offset = 0.0
		tick_flash = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		tick_flash = maxf(0.0, tick_flash - delta * 6.0)
		queue_redraw()

	func _draw() -> void:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(1, 1, 1, 0.015)
		panel.set_corner_radius_all(8)
		draw_style_box(panel, Rect2(0, 0, size.x, size.y))

		var row_height := (size.y - 16.0) / 3.0
		for row in 3:
			var cell := StyleBoxFlat.new()
			cell.bg_color = Color("#FFFDF4", 0.105) if row == 1 else Color("#FFFDF4", 0.065)
			cell.border_color = Color(Ui.GOLD, 0.32)
			cell.set_border_width_all(1)
			cell.set_corner_radius_all(7)
			draw_style_box(
				cell,
				Rect2(4, 5 + row * row_height, size.x - 8, row_height - 2)
			)

		if spinning:
			_draw_scrolling()
		else:
			_draw_resting()

		var center_y := size.y / 2.0
		draw_rect(Rect2(4, center_y - 34, size.x - 8, 68), Color(Ui.GOLD, 0.045 + tick_flash * 0.09))
		var center_box := StyleBoxFlat.new()
		center_box.bg_color = Color(1, 1, 1, 0.018)
		center_box.border_color = Color("#FFB82E", 0.90)
		center_box.set_border_width_all(2)
		center_box.set_corner_radius_all(8)
		draw_style_box(
			center_box,
			Rect2(4, center_y - 34, size.x - 8, 68)
		)

	func _draw_resting() -> void:
		var index := symbols.find(final_symbol)
		if index < 0:
			index = 0
		var top: String = symbols[posmod(index - 1, symbols.size())]
		var bottom: String = symbols[posmod(index + 1, symbols.size())]
		var bob := sin(_time * 1.7 + reel_index) * (1.8 if not Preferences.reduced_motion else 0.0)
		var center_y := size.y / 2.0
		_draw_symbol(top, Rect2(14, center_y - CELL_HEIGHT - 23 + bob, size.x - 28, 46), Color(1, 1, 1, 0.76))
		_draw_symbol(final_symbol, Rect2(9, center_y - 32 + bob, size.x - 18, 64), Color.WHITE)
		_draw_symbol(bottom, Rect2(14, center_y + CELL_HEIGHT - 23 + bob, size.x - 28, 46), Color(1, 1, 1, 0.76))

	func _draw_scrolling() -> void:
		var phase := roll_offset / CELL_HEIGHT
		var base := floori(phase)
		var fraction := phase - float(base)
		for slot in range(-2, 4):
			var symbol: String = symbols[posmod(base + slot + reel_index, symbols.size())]
			var y := size.y / 2.0 - 32.0 + (float(slot) - fraction) * CELL_HEIGHT
			var alpha := 1.0 if y > 26 and y < size.y - 58 else 0.45
			_draw_symbol(symbol, Rect2(9, y, size.x - 18, 64), Color(1, 1, 1, alpha))
		for streak in 5:
			var streak_y := 18.0 + streak * 32.0 + fmod(roll_offset * 0.42, 16.0)
			draw_rect(Rect2(14, streak_y, size.x - 28, 3), Color(Ui.GOLD, 0.14 + streak % 2 * 0.10))

	func _draw_symbol(symbol: String, destination: Rect2, tint: Color) -> void:
		if atlas == null or symbols.is_empty():
			return
		var index := symbols.find(symbol)
		if index < 0:
			index = 0
		var column := index % 3
		var row := index / 3
		var cell_width := float(atlas.get_width()) / 3.0
		var cell_height := float(atlas.get_height()) / 2.0
		var source := Rect2(column * cell_width, row * cell_height, cell_width, cell_height)
		draw_texture_rect_region(atlas, destination, source, tint, false, true)


class AnimatedBackdrop extends Control:
	var _time := 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for i in 16:
			var px := fmod(float(i * 97) + _time * (7.0 + i % 4), 570.0) - 15.0
			var py := fmod(float(i * 67) + sin(_time * 0.7 + i) * 22.0, 990.0)
			var glow := Color.WHITE if i % 3 else Ui.NEON_MAGENTA
			draw_circle(Vector2(px, py), 1.6 + i % 3, Color(glow, 0.18))
		for i in 5:
			var x := 40.0 + i * 122.0 + sin(_time * 0.45 + i) * 16.0
			var y := 170.0 + i * 178.0 + cos(_time * 0.38 + i) * 14.0
			draw_arc(Vector2(x, y), 18.0 + i * 3.0, 0, TAU, 24, Color(Ui.NEON_CYAN, 0.12), 2.0)


class ParticleBurst extends Control:
	var _particles: Array = []

	func emit_burst(origin: Vector2, color: Color, count: int) -> void:
		_particles.clear()
		for i in count:
			var angle := randf_range(-PI, 0.0)
			if i % 3 == 0:
				angle = randf_range(0.0, TAU)
			var speed := randf_range(85.0, 360.0)
			_particles.append({
				"position": origin + Vector2(randf_range(-35, 35), randf_range(-25, 25)),
				"velocity": Vector2(cos(angle), sin(angle)) * speed,
				"life": randf_range(0.55, 1.25),
				"max_life": 1.25,
				"size": randf_range(2.5, 8.0),
				"color": color.lerp(Ui.NEON_MAGENTA if i % 2 else Ui.GOLD, randf_range(0.0, 0.45)),
			})
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		for particle in _particles:
			particle.position += particle.velocity * delta
			particle.velocity.y += 420.0 * delta
			particle.velocity *= 0.985
			particle.life -= delta
		_particles = _particles.filter(func(particle: Dictionary) -> bool: return particle.life > 0.0)
		if _particles.is_empty():
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		for particle in _particles:
			var alpha := clampf(particle.life / particle.max_life, 0.0, 1.0)
			var color: Color = particle.color
			color.a = alpha
			draw_circle(particle.position, particle.size * alpha, color)
			draw_line(
				particle.position,
				particle.position - particle.velocity.normalized() * particle.size * 2.2,
				Color(color, alpha * 0.55),
				maxf(1.0, particle.size * 0.30)
			)
