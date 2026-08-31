extends Control
## District 1 — construction data-driven, mutation autoritaire.

signal navigate_requested(tab: String)

## Décor de secours quand un district n'a pas encore son art propre.
const FALLBACK_BACKGROUND := "res://assets/generated/districts/stages/neon_slums.webp"
const HERO_ART := "res://assets/generated/api_gpt/heroes/district_hero.webp"
const STAR_ART := "res://assets/generated/ui/star.webp"
const HAMMER_ART := "res://assets/generated/ui/hammer.webp"
const WRENCH_ART := "res://assets/generated/ui/wrench.webp"
const ASSET_ROOT := "res://assets/generated/"
## WebP runtime, PNG accepté si un art n'est pas encore converti.
const ASSET_EXTENSIONS: Array[String] = [".webp", ".png"]

const IVORY := Color("#FFF0C0")
const INK := Color("#11225A")
const PAD_SIZE := Vector2(250, 360)
const ART_SIZE := Vector2(250, 270)
const HAMMER := 68

var _credits: Label
var _progress: ProgressBar
var _progress_label: Label
var _list: Control
var _background: TextureRect
var _hero_holder: VBoxContainer
var _busy := false
var _district: Dictionary = {}
var _layout_busy := false
var _armed_element := -1

func _ready() -> void:
	_district = _active_district()
	_build_background()
	_build()
	Store.state_changed.connect(_refresh)
	_refresh()

## Résout un nom d'asset de config en texture. Les configs stockent des noms
## relatifs sans extension ; un asset absent renvoie null plutôt que d'échouer,
## donc un district peut être livré par config avant son art.
##
## Le nom vient d'une config distante mise en cache sur l'appareil, donc il est
## traité comme une donnée non fiable : il reste confiné sous ASSET_ROOT et le
## résultat doit être une texture, jamais un script ou une scène.
func _asset_texture(name: String) -> Texture2D:
	var trimmed := name.strip_edges()
	if trimmed.is_empty() or trimmed.contains("..") or trimmed.contains(":") or trimmed.begins_with("/"):
		return null
	for extension in ASSET_EXTENSIONS:
		var path := ASSET_ROOT + trimmed + extension
		if not ResourceLoader.exists(path):
			continue
		var resource := load(path)
		if resource is Texture2D:
			return resource
	return null

func _build_background() -> void:
	_background = TextureRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sky := ColorRect.new()
	sky.color = Color("#071A4A")
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	Ui.soften_tex(_background)
	_background.modulate = Color.WHITE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_apply_background()

func _apply_background() -> void:
	if _background == null:
		return
	var texture := _asset_texture(str(_district.get("background", "")))
	if texture == null:
		texture = load(FALLBACK_BACKGROUND)
	_background.texture = texture

func _build() -> void:
	var districts := Config.districts()
	if districts.is_empty():
		add_child(Ui.label("NO DISTRICT CONFIGURED", 20, Ui.DANGER))
		return
	var safe := Ui.safe_insets()
	_list = Control.new()
	_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	_list.offset_top = 118.0 + safe.y
	_list.offset_bottom = -(Ui.NAV_HEIGHT + 8.0 + safe.w)
	_list.clip_contents = false
	_list.resized.connect(_layout_pads)
	add_child(_list)

	var credits_chip := _ivory_chip(Ui.GOLD)
	credits_chip.position = Vector2(14 + safe.x, 12 + safe.y)
	credits_chip.size = Vector2(200, 56)
	_credits = Ui.label("0 CR", 20, INK)
	credits_chip.add_child(_credits)
	add_child(credits_chip)

	_hero_holder = VBoxContainer.new()
	_hero_holder.position = Vector2(224 + safe.x, 12 + safe.y)
	_hero_holder.size = Vector2(302 - safe.z, 56)
	add_child(_hero_holder)
	_rebuild_hero()

	_progress = Ui.progress_bar(Ui.GOLD, 14)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_progress.offset_left = 18 + safe.x
	_progress.offset_right = -(18 + safe.z)
	_progress.offset_top = 76.0 + safe.y
	_progress.offset_bottom = 92.0 + safe.y
	add_child(_progress)
	_progress_label = Ui.label("", 12, Ui.TEXT)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_progress_label.offset_left = 18 + safe.x
	_progress_label.offset_right = -(18 + safe.z)
	_progress_label.offset_top = 94.0 + safe.y
	_progress_label.offset_bottom = 114.0 + safe.y
	add_child(_progress_label)

	var bay := _round_tool(Ui.GOLD, false)
	bay.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bay.offset_left = 16.0 + safe.x
	bay.offset_top = -(Ui.NAV_HEIGHT + 84.0 + safe.w)
	bay.offset_right = 16.0 + safe.x + HAMMER
	bay.offset_bottom = -(Ui.NAV_HEIGHT + 16.0 + safe.w)
	bay.pressed.connect(_open_build_bay)
	add_child(bay)

func _ivory_chip(accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var box := Ui.style_box(IVORY, Color(accent, 0.98), 22, 4)
	box.set_content_margin_all(8)
	box.shadow_color = Color("#182356", 0.48)
	box.shadow_size = 7
	box.shadow_offset = Vector2(0, 5)
	chip.add_theme_stylebox_override("panel", box)
	return chip

## Bandeau compact : le diorama a besoin du viewport, pas d'une carte héros 172 px.
func _rebuild_hero() -> void:
	if _hero_holder == null:
		return
	for child in _hero_holder.get_children():
		child.queue_free()
	var total := Config.districts().size()
	var index := int(_district.get("id", 1))
	var kicker := "NODE %02d" % index
	if total > 1:
		kicker = "NODE %02d / %02d" % [index, total]
	var chip := _ivory_chip(Ui.NEON_CYAN)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	var k := Ui.label(kicker, 10, Ui.NEON_CYAN)
	copy.add_child(k)
	var title := Ui.label(str(_district.get("name", "Neon Slums")), 20, INK)
	copy.add_child(title)
	chip.add_child(copy)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_holder.add_child(chip)

func _refresh() -> void:
	var active := _active_district()
	if not active.is_empty() and int(active.get("id", 0)) != int(_district.get("id", 0)):
		_district = active
		_armed_element = -1
		_apply_background()
		_rebuild_hero()
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
	call_deferred("_layout_pads")
	var percent := 100.0 if total_levels == 0 else float(earned_levels) / float(total_levels) * 100.0
	_progress.value = percent
	_progress_label.text = "%s  •  %d / %d STARS" % [str(_district.get("name", "DISTRICT")).to_upper(), earned_levels, total_levels]


func _layout_pads() -> void:
	if _list == null or _layout_busy:
		return
	_layout_busy = true
	var live: Array[Control] = []
	for child in _list.get_children():
		if child is Control and not child.is_queued_for_deletion():
			live.append(child)
	var count := live.size()
	var area := _list.size
	if area.x < 8.0:
		area.x = 500.0
	if area.y < 8.0:
		area.y = 640.0
	var screen := size
	if screen.x < 8.0:
		screen.x = 540.0
	if screen.y < 8.0:
		screen.y = 1170.0
	var bottom := 0.0
	for i in count:
		var pad: Control = live[i]
		var slot := _pad_slot(i, count)
		pad.size = PAD_SIZE
		if count <= 5:
			var foot := Vector2(screen.x * slot.x, screen.y * slot.y) - _list.position
			pad.position = foot - Vector2(PAD_SIZE.x * 0.5, PAD_SIZE.y * 0.86)
			Juice.arm(pad)
			pad.offset_transform_scale = Vector2(slot.z, slot.z)
		else:
			pad.position = Vector2(8.0 + float(i % 2) * (area.x * 0.5), 8.0 + float(int(i / 2.0)) * (PAD_SIZE.y + 8.0))
			pad.offset_transform_scale = Vector2.ONE
		pad.z_index = int(pad.position.y * 0.2)
		bottom = maxf(bottom, pad.position.y + PAD_SIZE.y)
	var next_height := maxf(area.y, bottom + 12.0)
	if not is_equal_approx(_list.custom_minimum_size.y, next_height):
		_list.custom_minimum_size = Vector2(0, next_height)
	_layout_busy = false


func _pad_slot(index: int, _count: int) -> Vector3:
	# Pied du bâtiment, fraction de l'écran : croix 2.5D sur l'île, avant plus gros.
	var village: Array[Vector3] = [
		Vector3(0.30, 0.38, 0.72),
		Vector3(0.70, 0.38, 0.72),
		Vector3(0.50, 0.50, 0.88),
		Vector3(0.24, 0.66, 1.04),
		Vector3(0.76, 0.68, 1.06),
	]
	if index < village.size():
		return village[index]
	return Vector3(0.50, 0.20 + float(index) * 0.12, 0.85)


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

func _element_card(element: Dictionary, current: int, max_level: int) -> Control:
	var element_id := int(element.get("id", 0))
	var damaged := Store.district_damaged(int(_district.get("id", 1)), element_id)
	var wrap := Control.new()
	wrap.custom_minimum_size = PAD_SIZE
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := Button.new()
	pad.flat = true
	pad.focus_mode = Control.FOCUS_NONE
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		pad.add_theme_stylebox_override(style_name, empty)
	Juice.arm(pad, true)
	var art := _element_visual(element, current)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_TOP_WIDE)
	art.offset_bottom = ART_SIZE.y
	pad.add_child(art)
	var stars := _star_row(current, 5)
	stars.position = Vector2(12, ART_SIZE.y - 4)
	stars.size = Vector2(PAD_SIZE.x - 24, 18)
	pad.add_child(stars)
	var is_max := current >= max_level and not damaged
	if not is_max:
		var tool := _round_tool(Color("#FF8A3A") if damaged else Ui.GOLD, damaged)
		tool.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tool.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		tool.offset_left = -float(HAMMER) * 0.5
		tool.offset_right = float(HAMMER) * 0.5
		tool.offset_top = -float(HAMMER) - 6.0
		tool.offset_bottom = -6.0
		pad.add_child(tool)
		if _armed_element == element_id:
			var quote := _tool_quote(element, current, max_level, damaged)
			var bubble := _ivory_chip(quote.get("accent", Ui.GOLD))
			bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bubble.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			bubble.offset_left = -86
			bubble.offset_right = 86
			bubble.offset_top = -float(HAMMER) - 58.0
			bubble.offset_bottom = -float(HAMMER) - 10.0
			var cost_label := Ui.label(str(quote.get("text", "")), 15, INK)
			cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bubble.add_child(cost_label)
			pad.add_child(bubble)
	pad.pressed.connect(_on_tool.bind(element_id, damaged, is_max))
	wrap.add_child(pad)
	wrap.set_meta("element_id", element_id)
	return wrap


func _tool_quote(element: Dictionary, current: int, max_level: int, damaged: bool) -> Dictionary:
	if damaged:
		var current_cost := int(element.get("levels", [])[current].get("cost", 0))
		var repair_bps := int(Config.social().get("attack", {}).get("repairCostBps", 2500))
		var repair_cost := current_cost * repair_bps / 10000
		return {"text": "FIX " + Ui.compact(repair_cost), "accent": Ui.NEON_MAGENTA}
	if current >= max_level:
		return {"text": "MAX", "accent": Ui.GREEN}
	var next: Dictionary = element.get("levels", [])[current + 1]
	return {"text": Ui.compact(int(next.get("cost", 0))) + " CR", "accent": Color("#FF4F46")}


func _star_row(filled: int, total: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star: Texture2D = load(STAR_ART) if ResourceLoader.exists(STAR_ART) else null
	for i in total:
		if star != null:
			var pip := TextureRect.new()
			pip.texture = star
			pip.custom_minimum_size = Vector2(16, 16)
			pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pip.modulate = Color.WHITE if i < filled else Color(0.22, 0.28, 0.46, 0.55)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			Ui.soften_tex(pip)
			row.add_child(pip)
		else:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(14, 14)
			pip.color = Ui.GOLD if i < filled else Color("#1A2A5A")
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pip)
	return row


func _round_tool(_accent: Color, repair: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(HAMMER, HAMMER)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	var empty := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(style_name, empty)
	Juice.arm(button, true)
	var icon_path := WRENCH_ART if repair else HAMMER_ART
	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Ui.soften_tex(icon)
		button.add_child(icon)
	else:
		var glyph := ToolGlyph.new()
		glyph.repair = repair
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(glyph)
	return button


func _on_tool(element_id: int, damaged: bool, is_max: bool) -> void:
	if _busy or is_max:
		return
	if _armed_element == element_id:
		_armed_element = -1
		if damaged:
			_repair(element_id)
		else:
			_upgrade(element_id)
	else:
		_armed_element = element_id
		Sfx.click()
		_refresh()


func _open_build_bay() -> void:
	if _busy or _district.is_empty():
		return
	Sfx.click()
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.08, 0.9)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 460
	box.add_theme_constant_override("separation", 12)
	box.add_child(Ui.label("BUILD BAY", 28, Ui.GOLD))
	for element in _district.get("elements", []):
		if typeof(element) != TYPE_DICTIONARY:
			continue
		var element_id := int(element.get("id", 0))
		var max_level := maxi(0, element.get("levels", []).size() - 1)
		var current := Store.district_level(int(_district.get("id", 1)), element_id)
		var damaged := Store.district_damaged(int(_district.get("id", 1)), element_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var thumb := _element_visual(element, current)
		thumb.custom_minimum_size = Vector2(64, 64)
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(thumb)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := Ui.label(str(element.get("name", "Pad")), 16, Ui.TEXT)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		copy.add_child(name)
		copy.add_child(_star_row(current, 5))
		row.add_child(copy)
		var quote := _tool_quote(element, current, max_level, damaged)
		var action: Button
		if current >= max_level and not damaged:
			action = Ui.button("MAX", Ui.GREEN, true)
			action.disabled = true
		elif damaged:
			action = Ui.button(str(quote.get("text", "FIX")), Ui.NEON_MAGENTA)
			action.pressed.connect(_bay_act.bind(overlay, element_id, true))
		else:
			action = Ui.button(str(quote.get("text", "BUY")), Color("#FF4F46"))
			action.pressed.connect(_bay_act.bind(overlay, element_id, false))
		action.custom_minimum_size = Vector2(128, 52)
		row.add_child(action)
		box.add_child(row)
	var close := Ui.button("CLOSE", Ui.NEON_CYAN, true)
	close.pressed.connect(func() -> void:
		overlay.queue_free()
	)
	box.add_child(close)
	center.add_child(box)
	overlay.add_child(center)
	add_child(overlay)
	Juice.modal(box)


func _bay_act(overlay: Control, element_id: int, damaged: bool) -> void:
	overlay.queue_free()
	if damaged:
		_repair(element_id)
	else:
		_upgrade(element_id)

## Visuel d'un élément au niveau courant : le PNG du niveau s'il a été livré,
## sinon le glyphe procédural. Les deux chemins gardent la même taille, donc la
## carte ne bouge pas selon la présence de l'art.
func _element_visual(element: Dictionary, current: int) -> Control:
	var levels: Array = element.get("levels", [])
	if current >= 0 and current < levels.size() and typeof(levels[current]) == TYPE_DICTIONARY:
		var texture := _asset_texture(str(levels[current].get("asset", "")))
		if texture != null:
			var art := TextureRect.new()
			art.texture = texture
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			Ui.soften_tex(art)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.custom_minimum_size = ART_SIZE
			art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			return art
	var glyph := StructureGlyph.new()
	glyph.kind = int(element.get("id", 1))
	glyph.variant = int(_district.get("id", 1))
	glyph.level = current
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.custom_minimum_size = ART_SIZE
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return glyph

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
		_track_reward_pool(response.data.get("rewardPoolAllocations", []))
		Haptics.vibrate(0.55, 45)
		Sfx.upgrade()
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
	if response.ok:
		call_deferred("_pulse_element", element_id)

func _pulse_element(element_id: int) -> void:
	var target: Control = null
	for child in _list.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.has_meta("element_id") and int(child.get_meta("element_id")) == element_id:
			target = child
	if target != null:
		var bounce: Control = target
		for child in target.get_children():
			if child is BaseButton:
				bounce = child
				break
		Juice.pop(bounce, 1.08, 0.24)

func _track_reward_pool(allocations: Variant) -> void:
	if typeof(allocations) != TYPE_ARRAY:
		return
	for allocation in allocations:
		if typeof(allocation) == TYPE_DICTIONARY and int(allocation.get("amountU64", 0)) > 0:
			Events.track("reward_pool_progress", allocation)

func _show_complete(reward: Dictionary, district_id: int, next_district_id: int, all_complete: bool) -> void:
	Events.track("village_completed", {"districtId": district_id, "nextDistrictId": next_district_id, "allDistrictsComplete": all_complete})
	if int(reward.get("credits", 0)) > 0:
		Events.track("currency_earned", {"currency": "credits", "amount": int(reward.get("credits", 0)), "source": "village_completed", "districtId": district_id})
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.08, 0.94)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 0
	box.add_theme_constant_override("separation", 18)
	box.add_child(Ui.label("DISTRICT COMPLETE", 34, Ui.GOLD))
	box.add_child(Ui.label(Ui.reward_text(reward), 20, Ui.TEXT))
	var close := Ui.button("CITY SECURED" if all_complete else "NEXT DISTRICT", Ui.GOLD)
	close.pressed.connect(func() -> void:
		overlay.queue_free()
		navigate_requested.emit("spin")
	)
	box.add_child(close)
	center.add_child(box)
	overlay.add_child(center)
	add_child(overlay)
	Juice.modal(box)
	Sfx.result("legendary")
	Haptics.win("legendary")

class ToolGlyph extends Control:
	var repair := false

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var ink := Color("#11225A")
		draw_circle(center + Vector2(-7, 9), 8, ink)
		draw_line(center + Vector2(-5, 6), center + Vector2(13, -11), ink, 7.0)
		var head := Color("#FF8A3A") if repair else Color("#FFD34E")
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(6, -16),
			center + Vector2(18, -8),
			center + Vector2(12, -2),
			center + Vector2(2, -10),
		]), head)

## Cinq silhouettes × six états, dessinées sans dépendance à un sprite. Chaque
## niveau ajoute énergie, néons et détails, donc l'amélioration reste visible
## même si un pack d'art distant n'est pas encore téléchargé.
##
## `kind` accepte n'importe quel identifiant d'élément : les silhouettes tournent
## en boucle et un bandeau de série marque les identifiants au-delà de cinq, donc
## un district ajouté par config ne peut plus produire de plateforme nue.
## `variant` décale la palette par district pour qu'ils ne se ressemblent pas.
class StructureGlyph extends Control:
	var kind := 1
	var level := 0
	var variant := 1

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _shape() -> int:
		return posmod(maxi(kind, 1) - 1, 5) + 1

	func _series() -> int:
		return (maxi(kind, 1) - 1) / 5

	func _accent() -> Color:
		match posmod(maxi(variant, 1) - 1, 5):
			1: return Ui.NEON_MAGENTA
			2: return Ui.GREEN
			3: return Ui.GOLD
			4: return Ui.NEON_CYAN
			_: return Ui.NEON_CYAN

	func _secondary() -> Color:
		match posmod(maxi(variant, 1) - 1, 5):
			1: return Ui.GOLD
			2: return Ui.NEON_CYAN
			3: return Ui.NEON_MAGENTA
			4: return Ui.GREEN
			_: return Ui.NEON_MAGENTA

	func _draw() -> void:
		var draw_scale := size.x / 76.0 if size.x > 1.0 else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(draw_scale, draw_scale))
		var accent := _accent()
		var secondary := _secondary()
		var base := Rect2(8, 50, 60, 18)
		draw_rect(base, Color(0.08, 0.10, 0.18), true)
		draw_rect(base, Ui.BORDER, false, 2.0)
		var shell := Color(0.16, 0.19, 0.30) if level > 0 else Color(0.09, 0.10, 0.14)
		match _shape():
			1:
				draw_rect(Rect2(17, 16, 42, 38), shell, true)
				for y in range(23, 49, 10):
					draw_rect(Rect2(24, y, 8, 5), _light(level, y), true)
					draw_rect(Rect2(43, y, 8, 5), _light(level - 1, y), true)
			2:
				draw_rect(Rect2(12, 24, 52, 31), shell, true)
				draw_rect(Rect2(19, 30, 38, 17), Color(accent, 0.15 + level * 0.12), true)
				draw_line(Vector2(38, 24), Vector2(38, 11), secondary if level >= 4 else Ui.BORDER, 3)
			3:
				draw_circle(Vector2(38, 35), 20, shell)
				for ring in range(1, mini(level, 3) + 1):
					draw_arc(Vector2(38, 35), 5.0 + ring * 5.0, 0, TAU, 24, Color(accent, 0.35 + ring * 0.15), 2)
				draw_line(Vector2(38, 15), Vector2(38, 7), Ui.GOLD if level >= 5 else Ui.BORDER, 3)
			4:
				draw_rect(Rect2(12, 27, 52, 29), shell, true)
				draw_colored_polygon(PackedVector2Array([Vector2(9,27),Vector2(67,27),Vector2(59,17),Vector2(17,17)]), secondary if level >= 2 else Ui.BORDER)
				draw_rect(Rect2(21, 35, 34, 8), Color(Ui.GOLD, 0.18 + level * 0.12), true)
			5:
				draw_line(Vector2(38, 54), Vector2(38, 9), shell.lightened(0.4), 6)
				draw_line(Vector2(38, 18), Vector2(20, 30), Ui.BORDER, 3)
				draw_line(Vector2(38, 18), Vector2(56, 30), Ui.BORDER, 3)
				for ring in range(mini(level, 3)):
					draw_arc(Vector2(38, 14), 8.0 + ring * 6.0, PI + 0.3, TAU - 0.3, 18, Color(accent, 0.45), 2)
		for series in range(mini(_series(), 3)):
			draw_rect(Rect2(10 + series * 7, 46, 5, 3), Color(secondary, 0.85), true)
		if level == 0:
			draw_line(Vector2(11, 61), Vector2(64, 19), Color(Ui.DANGER, 0.45), 3)
		elif level >= 5:
			draw_arc(Vector2(38, 37), 31, 0, TAU, 36, Color(Ui.GOLD, 0.75), 2)

	func _light(required: int, seed: int) -> Color:
		return Color(_accent(), 0.85) if level >= maxi(1, required % 5) else Color(Ui.BORDER, 0.35)
