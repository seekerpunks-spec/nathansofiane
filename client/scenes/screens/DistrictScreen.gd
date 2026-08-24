extends Control
## District 1 — construction data-driven, mutation autoritaire.

signal navigate_requested(tab: String)

var _credits: Label
var _progress: ProgressBar
var _progress_label: Label
var _list: VBoxContainer
var _busy := false
var _district: Dictionary = {}

func _ready() -> void:
	_build_background()
	_build()
	Store.state_changed.connect(_refresh)
	_refresh()

func _build_background() -> void:
	var texture := TextureRect.new()
	texture.texture = load("res://assets/generated/districts/neon_slums_bg.png")
	texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture.modulate = Color(0.38, 0.42, 0.58, 0.56)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture)
	var veil := ColorRect.new()
	veil.color = Color(0.025, 0.035, 0.08, 0.54)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

func _build() -> void:
	var districts := Config.districts()
	if districts.is_empty():
		add_child(Ui.label("AUCUN DISTRICT CONFIGURÉ", 20, Ui.DANGER))
		return
	_district = _active_district()
	var body := Ui.screen_body()
	body.add_child(Ui.hero_card("res://assets/generated/api_gpt/heroes/district_hero.png", "DISTRICT 01  •  REBUILD", str(_district.get("name", "Neon Slums")), "Améliore chaque bâtiment et rallume la ville.", Ui.NEON_CYAN))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	var credits_panel := Ui.panel(Color(Ui.PANEL, 0.94), Ui.NEON_MAGENTA)
	_credits = Ui.label("0 CR", 22, Ui.TEXT)
	credits_panel.add_child(_credits)
	credits_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(credits_panel)
	var spin_button := Ui.button("RETOUR SPIN", Ui.NEON_CYAN, true)
	spin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_button.pressed.connect(func() -> void: navigate_requested.emit("spin"))
	stats.add_child(spin_button)
	body.add_child(stats)

	_progress_label = Ui.label("", 13, Ui.TEXT_DIM)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.add_child(_progress_label)
	_progress = Ui.progress_bar(Ui.NEON_CYAN, 12)
	body.add_child(_progress)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.style_scroll(scroll, Ui.NEON_CYAN)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	body.add_child(scroll)
	add_child(body)

func _refresh() -> void:
	var active := _active_district()
	if not active.is_empty() and int(active.get("id", 0)) != int(_district.get("id", 0)):
		_district = active
	if _district.is_empty() or _list == null:
		return
	_credits.text = Ui.compact(Store.credits()) + " CR"
	for child in _list.get_children():
		child.queue_free()
	var total_levels := 0
	var earned_levels := 0
	var reveal_index := 0
	for element in _district.get("elements", []):
		if typeof(element) != TYPE_DICTIONARY:
			continue
		var max_level := maxi(0, element.get("levels", []).size() - 1)
		var current := Store.district_level(int(_district.get("id", 1)), int(element.get("id", 0)))
		total_levels += max_level
		earned_levels += mini(current, max_level)
		var card := _element_card(element, current, max_level)
		_list.add_child(card)
		Ui.reveal(card, reveal_index * 0.045)
		reveal_index += 1
	var percent := 100.0 if total_levels == 0 else float(earned_levels) / float(total_levels) * 100.0
	_progress.value = percent
	_progress_label.text = "%s  •  %d / %d UPGRADES" % [str(_district.get("name", "DISTRICT")).to_upper(), earned_levels, total_levels]


func _active_district() -> Dictionary:
	var completed := int(Store.state.get("districtIndex", 0))
	var fallback: Dictionary = {}
	for candidate in Config.districts():
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		fallback = candidate
		if int(candidate.get("id", 0)) > completed:
			return candidate
	return fallback

func _element_card(element: Dictionary, current: int, max_level: int) -> PanelContainer:
	var damaged := Store.district_damaged(int(_district.get("id", 1)), int(element.get("id", 0)))
	var card := Ui.panel(Color(Ui.PANEL, 0.94), Ui.BORDER if current < max_level else Ui.GREEN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var glyph := StructureGlyph.new()
	glyph.kind = int(element.get("id", 1))
	glyph.level = current
	glyph.custom_minimum_size = Vector2(76, 76)
	row.add_child(glyph)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Ui.label(str(element.get("name", "Structure")), 18, Ui.TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(name)
	var levels := Ui.label("NIVEAU %d / %d   %s" % [current, max_level, "◆".repeat(current) + "◇".repeat(maxi(0, max_level-current))], 12, Ui.NEON_CYAN)
	levels.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(levels)
	if damaged:
		var jammed := Ui.label("SIGNAL JAMMED  •  REPAIR REQUIRED", 11, Ui.NEON_MAGENTA)
		jammed.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(jammed)
	row.add_child(text)
	var button: Button
	if damaged:
		var current_cost := int(element.get("levels", [])[current].get("cost", 0))
		var repair_bps := int(Config.social().get("attack", {}).get("repairCostBps", 2500))
		var repair_cost := current_cost * repair_bps / 10000
		button = Ui.button("REPAIR " + Ui.compact(repair_cost) + " CR", Ui.NEON_MAGENTA, Store.credits() < repair_cost)
		button.disabled = _busy or Store.credits() < repair_cost
		button.pressed.connect(_repair.bind(int(element.get("id", 0))))
	elif current >= max_level:
		button = Ui.button("MAX", Ui.GREEN, true)
		button.disabled = true
	else:
		var next: Dictionary = element.get("levels", [])[current + 1]
		var cost := int(next.get("cost", 0))
		button = Ui.button(Ui.compact(cost) + " CR", Ui.NEON_MAGENTA, Store.credits() < cost)
		button.disabled = _busy or Store.credits() < cost
		button.pressed.connect(_upgrade.bind(int(element.get("id", 0))))
	button.custom_minimum_size.x = 132
	row.add_child(button)
	card.add_child(row)
	return card

func _repair(element_id: int) -> void:
	if _busy:
		return
	_busy = true
	var district_id := int(_district.get("id", 1))
	Events.track("repair_started", {"districtId": district_id, "elementId": element_id})
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/district/repair", {"districtId": district_id, "elementId": element_id, "requestId": rid}, rid)
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		Store.apply_mutation(response.data)
		var cost := int(response.data.get("cost", 0))
		Events.track("repair_completed", {"districtId": district_id, "elementId": element_id, "cost": cost})
		Events.track("currency_spent", {"currency": "credits", "amount": cost, "sink": "repair", "districtId": district_id, "elementId": element_id})
		await _sync_state()
	else:
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()

func _sync_state() -> void:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
		Store.apply_state(state_response.data)

func _upgrade(element_id: int) -> void:
	if _busy:
		return
	_busy = true
	var upgraded_district_id := int(_district.get("id", 1))
	var current_level := Store.district_level(upgraded_district_id, element_id)
	var expected_cost := 0
	for element in _district.get("elements", []):
		if typeof(element) == TYPE_DICTIONARY and int(element.get("id", 0)) == element_id:
			var levels: Array = element.get("levels", [])
			if current_level + 1 < levels.size():
				expected_cost = int(levels[current_level + 1].get("cost", 0))
			break
	Events.track("upgrade_started", {
		"districtId": upgraded_district_id,
		"elementId": element_id,
		"fromLevel": current_level,
		"expectedCost": expected_cost,
	})
	Sfx.click()
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/district/upgrade", {"districtId": int(_district.get("id", 1)), "elementId": element_id, "requestId": rid}, rid)
	if response.ok:
		Store.apply_mutation(response.data)
		var paid := int(response.data.get("cost", expected_cost))
		Events.track("upgrade_completed", {"districtId": upgraded_district_id, "elementId": element_id, "level": response.data.get("level", 0), "cost": paid})
		Events.track("currency_spent", {"currency": "credits", "amount": paid, "sink": "upgrade", "districtId": upgraded_district_id, "elementId": element_id})
		Haptics.vibrate(0.55, 45)
		if response.data.get("districtComplete", false):
			_show_complete(
				response.data.get("completionReward", {}),
				upgraded_district_id,
				int(response.data.get("nextDistrictId", 0)),
				bool(response.data.get("allDistrictsComplete", false))
			)
	elif response.code == 401:
		Store.session_expired.emit()
	else:
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()

func _show_complete(reward: Dictionary, district_id: int, next_district_id: int, all_complete: bool) -> void:
	Events.track("village_completed", {"districtId": district_id, "nextDistrictId": next_district_id, "allDistrictsComplete": all_complete})
	if int(reward.get("credits", 0)) > 0:
		Events.track("currency_earned", {"currency": "credits", "amount": int(reward.get("credits", 0)), "source": "village_completed", "districtId": district_id})
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.08, 0.94)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 390
	box.add_theme_constant_override("separation", 18)
	box.add_child(Ui.label("DISTRICT COMPLETE", 34, Ui.GOLD))
	box.add_child(Ui.label("+%s CR   +%s SPINS" % [Ui.compact(int(reward.get("credits", 0))), Ui.compact(int(reward.get("spins", 0)))], 20, Ui.TEXT))
	var close := Ui.button("CITY SECURED" if all_complete else "NEXT DISTRICT", Ui.GOLD)
	close.pressed.connect(func() -> void:
		overlay.queue_free()
		navigate_requested.emit("spin")
	)
	box.add_child(close)
	center.add_child(box)
	overlay.add_child(center)
	add_child(overlay)
	Sfx.result("legendary")
	Haptics.win("legendary")

## Cinq silhouettes × six états, dessinées sans dépendance à un sprite. Chaque
## niveau ajoute énergie, néons et détails, donc l'amélioration reste visible
## même si un pack d'art distant n'est pas encore téléchargé.
class StructureGlyph extends Control:
	var kind := 1
	var level := 0

	func _draw() -> void:
		var base := Rect2(8, 50, 60, 18)
		draw_rect(base, Color(0.08, 0.10, 0.18), true)
		draw_rect(base, Ui.BORDER, false, 2.0)
		var shell := Color(0.16, 0.19, 0.30) if level > 0 else Color(0.09, 0.10, 0.14)
		match kind:
			1:
				draw_rect(Rect2(17, 16, 42, 38), shell, true)
				for y in range(23, 49, 10):
					draw_rect(Rect2(24, y, 8, 5), _light(level, y), true)
					draw_rect(Rect2(43, y, 8, 5), _light(level - 1, y), true)
			2:
				draw_rect(Rect2(12, 24, 52, 31), shell, true)
				draw_rect(Rect2(19, 30, 38, 17), Color(Ui.NEON_CYAN, 0.15 + level * 0.12), true)
				draw_line(Vector2(38, 24), Vector2(38, 11), Ui.NEON_MAGENTA if level >= 4 else Ui.BORDER, 3)
			3:
				draw_circle(Vector2(38, 35), 20, shell)
				for ring in range(1, mini(level, 3) + 1):
					draw_arc(Vector2(38, 35), 5.0 + ring * 5.0, 0, TAU, 24, Color(Ui.NEON_CYAN, 0.35 + ring * 0.15), 2)
				draw_line(Vector2(38, 15), Vector2(38, 7), Ui.GOLD if level >= 5 else Ui.BORDER, 3)
			4:
				draw_rect(Rect2(12, 27, 52, 29), shell, true)
				draw_colored_polygon(PackedVector2Array([Vector2(9,27),Vector2(67,27),Vector2(59,17),Vector2(17,17)]), Ui.NEON_MAGENTA if level >= 2 else Ui.BORDER)
				draw_rect(Rect2(21, 35, 34, 8), Color(Ui.GOLD, 0.18 + level * 0.12), true)
			5:
				draw_line(Vector2(38, 54), Vector2(38, 9), shell.lightened(0.4), 6)
				draw_line(Vector2(38, 18), Vector2(20, 30), Ui.BORDER, 3)
				draw_line(Vector2(38, 18), Vector2(56, 30), Ui.BORDER, 3)
				for ring in range(mini(level, 3)):
					draw_arc(Vector2(38, 14), 8.0 + ring * 6.0, PI + 0.3, TAU - 0.3, 18, Color(Ui.NEON_CYAN, 0.45), 2)
		if level == 0:
			draw_line(Vector2(11, 61), Vector2(64, 19), Color(Ui.DANGER, 0.45), 3)
		elif level >= 5:
			draw_arc(Vector2(38, 37), 31, 0, TAU, 36, Color(Ui.GOLD, 0.75), 2)

	func _light(required: int, seed: int) -> Color:
		return Color(Ui.NEON_CYAN, 0.85) if level >= maxi(1, required % 5) else Color(Ui.BORDER, 0.35)
