extends Control
## Coffres et collections — inventaire serveur, doublons visibles.

signal navigate_requested(tab: String)

var _content: VBoxContainer
var _credits: Label
var _busy := false

func _ready() -> void:
	var body := Ui.screen_body()
	body.add_child(Ui.hero_card("res://assets/generated/api_gpt/heroes/collection_hero.png", "OPEN  •  REVEAL  •  COLLECT", "Collections", "Ouvre les caches et complète tes sets.", Ui.NEON_MAGENTA))
	_credits = Ui.label("", 18, Ui.GOLD)
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.add_child(_credits)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.style_scroll(scroll, Ui.NEON_MAGENTA)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	body.add_child(scroll)
	add_child(body)
	Store.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if _content == null:
		return
	_credits.text = "SOLDE  " + Ui.compact(Store.credits()) + " CR"
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(Ui.section_title("CACHES DISPONIBLES", Ui.NEON_MAGENTA))
	var reveal_index := 0
	for chest in Config.chests():
		if typeof(chest) == TYPE_DICTIONARY:
			var card := _chest_card(chest)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.04)
			reveal_index += 1
	_content.add_child(Ui.separator())
	_content.add_child(Ui.section_title("SETS DE CARTES", Ui.NEON_CYAN))
	for set_data in Config.sets():
		if typeof(set_data) == TYPE_DICTIONARY:
			var card := _set_card(set_data)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.04)
			reveal_index += 1

func _chest_card(chest: Dictionary) -> PanelContainer:
	var panel := Ui.panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var art_path := str(chest.get("image", ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.custom_minimum_size = Vector2(86, 86)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Ui.label(str(chest.get("name", "Cache")), 18, Ui.TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(name)
	var id := str(chest.get("chestId", ""))
	var qty := Store.chest_qty(id)
	var info := Ui.label("%d possédé(s) • %d cartes" % [qty, int(chest.get("cardsPerOpen", 0))], 12, Ui.TEXT_DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(info)
	row.add_child(text)
	var actions := VBoxContainer.new()
	var open := Ui.button("OUVRIR", Ui.NEON_CYAN, true)
	open.disabled = _busy or qty < 1
	open.pressed.connect(_open_chest.bind(id))
	actions.add_child(open)
	var cost := int(chest.get("priceCredits", 0))
	var buy := Ui.button(Ui.compact(cost) + " CR", Ui.NEON_MAGENTA, true)
	buy.disabled = _busy or Store.credits() < cost
	buy.pressed.connect(_buy_chest.bind(id))
	actions.add_child(buy)
	row.add_child(actions)
	panel.add_child(row)
	return panel

func _set_card(set_data: Dictionary) -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Ui.label(str(set_data.get("name", "Set")), 19, Ui.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(title)
	var owned := _owned_map()
	var card_ids: Array = set_data.get("cards", [])
	var complete := true
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	for card_id in card_ids:
		var qty := int(owned.get(str(card_id), 0))
		complete = complete and qty > 0
		var data := _card_data(str(card_id))
		var slot := VBoxContainer.new()
		var glyph := CardGlyph.new()
		glyph.card_id = str(card_id)
		glyph.rarity = str(data.get("rarity", "common"))
		glyph.owned = qty > 0
		glyph.custom_minimum_size = Vector2(80, 94)
		slot.add_child(glyph)
		var caption := Ui.label(str(data.get("name", card_id)).left(10) + (" ×%d" % qty if qty > 1 else ""), 9, Ui.TEXT if qty > 0 else Ui.TEXT_DIM)
		caption.custom_minimum_size.x = 80
		slot.add_child(caption)
		grid.add_child(slot)
	box.add_child(grid)
	var claimed: Array = Store.state.get("completedSets", [])
	var claim := Ui.button("RÉCLAMER +%s SPINS" % Ui.compact(int(set_data.get("completionSpins", 0))), Ui.GOLD, not complete)
	claim.disabled = _busy or not complete or claimed.has(set_data.get("setId", ""))
	claim.pressed.connect(_claim_set.bind(str(set_data.get("setId", ""))))
	box.add_child(claim)
	panel.add_child(box)
	return panel

func _owned_map() -> Dictionary:
	var out := {}
	for row in Store.state.get("cards", []):
		if typeof(row) == TYPE_DICTIONARY:
			out[str(row.get("cardId", ""))] = int(row.get("qty", 0))
	return out

func _card_name(card_id: String) -> String:
	return str(_card_data(card_id).get("name", card_id))

func _card_data(card_id: String) -> Dictionary:
	for card in Config.cards():
		if typeof(card) == TYPE_DICTIONARY and str(card.get("cardId", "")) == card_id:
			return card
	return {}

func _buy_chest(chest_id: String) -> void:
	await _mutate("/chest/buy", {"chestId": chest_id}, "chest_buy")

func _open_chest(chest_id: String) -> void:
	var data := await _mutate("/chest/open", {"chestId": chest_id}, "chest_open")
	if not data.is_empty():
		_show_drops(data.get("cards", []))

func _claim_set(set_id: String) -> void:
	var data := await _mutate("/set/claim", {"setId": set_id}, "set_complete")
	if not data.is_empty():
		Sfx.result("legendary")
		Haptics.win("legendary")

func _mutate(path: String, body: Dictionary, event_name: String) -> Dictionary:
	if _busy:
		return {}
	_busy = true
	var rid := Net.request_id()
	body["requestId"] = rid
	var response := await Net.protected_request("POST", path, body, rid)
	var data: Dictionary = response.data if response.ok and typeof(response.data) == TYPE_DICTIONARY else {}
	if response.ok:
		Store.apply_mutation(data)
		Events.track(event_name, body)
		await _sync_state()
	else:
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()
	return data

func _sync_state() -> void:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok:
		Store.apply_state(state_response.data)

func _show_drops(cards: Array) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.08, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 390
	box.add_theme_constant_override("separation", 12)
	box.add_child(Ui.label("CACHE DÉCRYPTÉ", 30, Ui.NEON_CYAN))
	for card in cards:
		var rarity := str(card.get("rarity", "common"))
		box.add_child(Ui.label(str(card.get("name", "Carte")) + ("  // DOUBLON" if card.get("duplicate", false) else ""), 17, Ui.tier_color(rarity)))
	var close := Ui.button("COLLECTER", Ui.NEON_CYAN)
	close.pressed.connect(overlay.queue_free)
	box.add_child(close)
	center.add_child(box)
	overlay.add_child(center)
	add_child(overlay)
	Sfx.result("rare")

class CardGlyph extends Control:
	var card_id := ""
	var rarity := "common"
	var owned := false

	func _draw() -> void:
		var color: Color = Ui.tier_color(rarity)
		var alpha: float = 1.0 if owned else 0.28
		var frame := Rect2(3, 3, size.x - 6, size.y - 6)
		draw_style_box(Ui.style_box(Color(Ui.PANEL_HI, alpha), Color(color, alpha), 10, 2), frame)
		var center: Vector2 = frame.get_center()
		var hash_value: int = absi(card_id.hash())
		var sides: int = 3 + hash_value % 5
		var points := PackedVector2Array()
		for i in sides:
			var angle := -PI / 2.0 + TAU * float(i) / float(sides)
			points.append(center + Vector2(cos(angle), sin(angle)) * 21.0)
		draw_colored_polygon(points, Color(color, 0.18 * alpha))
		for i in sides:
			draw_line(points[i], points[(i + 1) % sides], Color(color, 0.85 * alpha), 2)
		draw_circle(center, 5, Color(Ui.GOLD if rarity == "legendary" else color, alpha))
		if not owned:
			draw_rect(frame, Color(0.01, 0.02, 0.04, 0.50), true)
