extends Control
## Coffres et collections — inventaire serveur, doublons visibles.

signal navigate_requested(tab: String)

var _content: VBoxContainer
var _credits: Label
var _busy := false

func _ready() -> void:
	add_child(Ui.illustrated_stage("res://assets/generated/api_gpt/heroes/collection_hero.webp"))
	var body := Ui.screen_body()
	# Le kicker est volontairement long. En HBox avec le chip crédits, sa taille
	# minimale poussait le chip hors écran à 540 px et 360 px. Une pile verticale
	# garde les deux blocs visibles quelle que soit la largeur du téléphone.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title := Ui.kicker_block("OPEN  •  REVEAL  •  COLLECT", "Cards", Ui.NEON_MAGENTA)
	head.add_child(title)
	var credits_chip := Ui.hud_chip(Ui.GOLD)
	credits_chip.name = "CreditsChip"
	credits_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_chip.custom_minimum_size.y = 48
	credits_chip.add_to_group("horizontal_bounds_check")
	_credits = Ui.label("0 CR", 18, Color("#11225A"))
	credits_chip.add_child(_credits)
	head.add_child(credits_chip)
	body.add_child(head)
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
	_credits.text = Ui.compact(Store.credits()) + " CR"
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(Ui.section_title("AVAILABLE CACHES", Ui.NEON_MAGENTA))
	var reveal_index := 0
	for chest in Config.chests():
		if typeof(chest) == TYPE_DICTIONARY:
			var card := _chest_card(chest)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.04)
			reveal_index += 1
	_content.add_child(Ui.separator())
	_content.add_child(Ui.section_title("CARD SETS", Ui.NEON_CYAN))
	for set_data in Config.sets():
		if typeof(set_data) == TYPE_DICTIONARY:
			var card := _set_card(set_data)
			_content.add_child(card)
			Ui.reveal(card, reveal_index * 0.04)
			reveal_index += 1

func _chest_card(chest: Dictionary) -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var art_path := str(chest.get("image", ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.custom_minimum_size = Vector2(88, 88)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		Ui.soften_tex(art)
		row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Ui.label(str(chest.get("name", "Cache")), 18, Ui.TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(name)
	var id := str(chest.get("chestId", ""))
	var qty := Store.chest_qty(id)
	var info := Ui.label("%d owned • %d cards" % [qty, int(chest.get("cardsPerOpen", 0))], 12, Ui.TEXT_DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(info)
	row.add_child(text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var open := Ui.button("OPEN", Color("#FF4F46"))
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.add_to_group("horizontal_bounds_check")
	open.disabled = _busy or qty < 1
	open.pressed.connect(_open_chest.bind(id))
	actions.add_child(open)
	var cost := int(chest.get("priceCredits", 0))
	var buy := Ui.button(Ui.compact(cost) + " CR", Ui.NEON_MAGENTA, true)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.add_to_group("horizontal_bounds_check")
	buy.disabled = _busy or Store.credits() < cost
	buy.pressed.connect(_buy_chest.bind(id))
	actions.add_child(buy)
	box.add_child(row)
	box.add_child(actions)
	panel.add_child(box)
	return panel

## Couleur d'accent d'un set. Le thème vient de la config, donc un set ajouté
## sans thème connu retombe sur l'accent neutre au lieu d'être invisible.
func _theme_color(theme: String) -> Color:
	match theme:
		"cyan": return Ui.NEON_CYAN
		"magenta": return Ui.NEON_MAGENTA
		"rust": return Ui.GOLD
		"gold": return Ui.GOLD
		"void": return Ui.NEON_CYAN
		_: return Ui.NEON_CYAN

## Prérequis de déblocage lisible, vide si le set est accessible. Le serveur
## refait ce contrôle au claim : ici c'est de l'affichage.
func _set_lock_reason(set_data: Dictionary) -> String:
	var requirement: Variant = set_data.get("unlockRequirement", null)
	if typeof(requirement) != TYPE_DICTIONARY:
		return ""
	var district_id := int(requirement.get("completedDistrictId", 0))
	if district_id > 0 and int(Store.state.get("districtIndex", 0)) < district_id:
		return "LOCKED  •  CLEAR DISTRICT %02d" % district_id
	var required_set := str(requirement.get("completedSetId", ""))
	if required_set != "":
		var claimed: Array = Store.state.get("completedSets", [])
		if not claimed.has(required_set):
			return "LOCKED  •  COMPLETE %s" % _set_name(required_set).to_upper()
	return ""

func _set_name(set_id: String) -> String:
	for candidate in Config.sets():
		if typeof(candidate) == TYPE_DICTIONARY and str(candidate.get("setId", "")) == set_id:
			return str(candidate.get("name", set_id))
	return set_id

## Récompense effective d'un set : la forme objet prime, sinon les spins
## historiques. Même règle que SetConfig::effective_reward côté serveur.
func _set_reward(set_data: Dictionary) -> Dictionary:
	var reward: Variant = set_data.get("completionReward", null)
	if typeof(reward) == TYPE_DICTIONARY:
		return {
			"spins": int(reward.get("spins", 0)),
			"credits": int(reward.get("credits", 0)),
			"chest": str(reward.get("chest", "")),
		}
	return {"spins": int(set_data.get("completionSpins", 0)), "credits": 0, "chest": ""}

func _reward_label(reward: Dictionary) -> String:
	return "CLAIM  " + Ui.reward_text(reward)

func _set_card(set_data: Dictionary) -> PanelContainer:
	var accent := _theme_color(str(set_data.get("visualTheme", "")))
	var lock_reason := _set_lock_reason(set_data)
	var panel := Ui.panel(Color(Ui.PANEL, 0.94), accent if lock_reason == "" else Ui.BORDER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Ui.label(str(set_data.get("name", "Set")), 19, Ui.TEXT if lock_reason == "" else Ui.TEXT_DIM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(title)
	if lock_reason != "":
		var lock := Ui.label(lock_reason, 11, Ui.NEON_MAGENTA)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(lock)
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
	var claim := Ui.button(_reward_label(_set_reward(set_data)), Ui.GOLD, not complete or lock_reason != "")
	claim.disabled = _busy or not complete or lock_reason != "" or claimed.has(set_data.get("setId", ""))
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
	var data := await _mutate("/chest/buy", {"chestId": chest_id}, "chest_bought")
	if not data.is_empty():
		Events.track("currency_spent", {
			"currency": "credits",
			"amount": _chest_cost(chest_id),
			"sink": "chest",
			"chestId": chest_id,
		})

func _open_chest(chest_id: String) -> void:
	var data := await _mutate("/chest/open", {"chestId": chest_id}, "chest_opened")
	if not data.is_empty():
		var cards: Array = data.get("cards", [])
		for card in cards:
			if typeof(card) != TYPE_DICTIONARY:
				continue
			var props := {
				"chestId": chest_id,
				"cardId": str(card.get("cardId", "")),
				"setId": str(card.get("setId", "")),
				"rarity": str(card.get("rarity", "common")),
				"quantity": int(card.get("qty", 0)),
			}
			Events.track("card_received", props)
			Events.track("duplicate_card" if bool(card.get("duplicate", false)) else "new_card", props)
		_show_drops(cards)

func _claim_set(set_id: String) -> void:
	var data := await _mutate("/set/claim", {"setId": set_id}, "set_completed")
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

func _chest_cost(chest_id: String) -> int:
	for chest in Config.chests():
		if typeof(chest) == TYPE_DICTIONARY and str(chest.get("chestId", "")) == chest_id:
			return int(chest.get("priceCredits", 0))
	return 0

func _sync_state() -> void:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok:
		Store.apply_state(state_response.data)

func _show_drops(cards: Array) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.08, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 0
	box.add_theme_constant_override("separation", 12)
	box.add_child(Ui.label("CACHE DECRYPTED", 30, Ui.NEON_CYAN))
	for card in cards:
		var rarity := str(card.get("rarity", "common"))
		box.add_child(Ui.label(str(card.get("name", "Card")) + ("  // DUPLICATE" if card.get("duplicate", false) else ""), 17, Ui.tier_color(rarity)))
	var close := Ui.button("COLLECT", Ui.NEON_CYAN)
	close.pressed.connect(overlay.queue_free)
	box.add_child(close)
	center.add_child(box)
	overlay.add_child(center)
	add_child(overlay)
	Juice.modal(box)
	var delay := 0.06
	for child in box.get_children():
		if child is Label and child != box.get_child(0):
			Ui.reveal(child, delay)
			delay += 0.05
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
