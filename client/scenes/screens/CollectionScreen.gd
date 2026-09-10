extends Control
## Coffres et collections — inventaire serveur, doublons visibles.

const CardView := preload("res://scripts/components/CryptoCardView.gd")
const Neon := preload("res://scripts/components/NeonSkin.gd")

signal navigate_requested(tab: String)

var _content: VBoxContainer
var _credits: Label
var _busy := false
var _selected_set := 0
var _show_caches := false
var _album_button: Button
var _cache_button: Button
var _selector: OptionButton
var _scroll: ScrollContainer
var _feedback: Label

func _ready() -> void:
	add_child(Ui.illustrated_stage("res://assets/generated/punk_city/city.webp"))
	var body := Ui.screen_body()
	# Le kicker est volontairement long. En HBox avec le chip crédits, sa taille
	# minimale poussait le chip hors écran à 540 px et 360 px. Une pile verticale
	# garde les deux blocs visibles quelle que soit la largeur du téléphone.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title := Neon.header("CRYPTO ARCHIVES • 45 CARDS", "Collection", 7, Ui.NEON_MAGENTA)
	head.add_child(title)
	var credits_chip := Ui.hud_chip(Ui.GOLD)
	credits_chip.name = "CreditsChip"
	credits_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_chip.custom_minimum_size.y = 48
	credits_chip.add_to_group("horizontal_bounds_check")
	_credits = Ui.label("0 CR", 18, Ui.TEXT)
	credits_chip.add_child(_credits)
	head.add_child(credits_chip)
	body.add_child(head)
	_feedback = Ui.label("", 13, Ui.GOLD)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.visible = false
	body.add_child(_feedback)
	var tabs := HBoxContainer.new()
	_album_button = Ui.button("ALBUMS", Ui.NEON_CYAN, true)
	_cache_button = Ui.button("CHESTS", Ui.NEON_MAGENTA, true)
	for button in [_album_button, _cache_button]:
		button.toggle_mode = true
		var accent := Ui.NEON_CYAN if button == _album_button else Ui.NEON_MAGENTA
		button.add_theme_stylebox_override("pressed", Ui.style_box(accent.darkened(0.30), accent, 24, 3))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
	_album_button.pressed.connect(_switch_mode.bind(false))
	_cache_button.pressed.connect(_switch_mode.bind(true))
	body.add_child(tabs)
	_selector = OptionButton.new()
	_selector.custom_minimum_size.y = 48
	_selector.add_theme_font_size_override("font_size", 19)
	_selector.fit_to_longest_item = false
	_selector.item_selected.connect(_select_set)
	body.add_child(_selector)
	var scroll := ScrollContainer.new()
	_scroll = scroll
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
	if not get_meta("qa_skip_sync", false) and Net.has_token():
		_sync_state.call_deferred()

func _switch_mode(caches: bool) -> void:
	_show_caches = caches
	_scroll.scroll_vertical = 0
	_refresh()

func _select_set(index: int) -> void:
	_selected_set = index
	_scroll.scroll_vertical = 0
	_refresh()

func _refresh() -> void:
	if _content == null:
		return
	_credits.text = Ui.compact(Store.credits()) + " CR"
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_selector.visible = not _show_caches
	_album_button.set_pressed_no_signal(not _show_caches)
	_cache_button.set_pressed_no_signal(_show_caches)
	if _show_caches:
		_content.add_child(Ui.section_title("OPEN CHESTS • DISCOVER CARDS", Ui.NEON_MAGENTA))
		for chest in Config.chests():
			if typeof(chest) == TYPE_DICTIONARY:
				_content.add_child(_chest_card(chest))
		return
	var sets := Config.sets()
	_selector.clear()
	var owned := _owned_map()
	for set_data in sets:
		var count := 0
		for id in set_data.get("cards", []):
			if int(owned.get(str(id), 0)) > 0:
				count += 1
		_selector.add_item("%s   %d/%d" % [set_data.get("name", "Album"), count, set_data.get("cards", []).size()])
	if sets.is_empty():
		_content.add_child(Ui.label("NO COLLECTIONS AVAILABLE", 18, Ui.TEXT_DIM))
		return
	_selected_set = clampi(_selected_set, 0, sets.size() - 1)
	_selector.select(_selected_set)
	_content.add_child(_set_card(sets[_selected_set]))
	var note := Ui.label("Collectibles only • No crypto value or affiliation", 11, Ui.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(note)

func _chest_card(chest: Dictionary) -> PanelContainer:
	var accents := {"basic": Ui.NEON_CYAN, "neon": Ui.NEON_MAGENTA, "quantum": Ui.NEON_BLUE, "elite": Ui.GOLD}
	var panel := Ui.panel(Ui.PANEL, accents.get(str(chest.get("chestId", "")), Ui.NEON_CYAN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var art_path := str(chest.get("image", ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.custom_minimum_size = Vector2(148, 148)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		Ui.soften_tex(art)
		row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name := Ui.label(str(chest.get("name", "Cache")), 24, Ui.TEXT)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(name)
	var id := str(chest.get("chestId", ""))
	var qty := Store.chest_qty(id)
	var info := Ui.label("%d owned • %d cards" % [qty, int(chest.get("cardsPerOpen", 0))], 15, Ui.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(info)
	row.add_child(text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var open := Ui.button("OPEN", Ui.GOLD)
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
	var panel := Ui.panel(Color(Ui.PANEL, 0.94), accent)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var owned := _owned_map()
	var card_ids: Array = set_data.get("cards", [])
	var found := 0
	for id in card_ids:
		if int(owned.get(str(id), 0)) > 0:
			found += 1
	var title := Ui.label(str(set_data.get("name", "Set")).to_upper(), 23, accent)
	box.add_child(title)
	var progress := ProgressBar.new()
	progress.max_value = maxi(1, card_ids.size())
	progress.value = found
	progress.custom_minimum_size.y = 22
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", Ui.style_box(Color("#080e25"), Ui.BORDER, 5))
	progress.add_theme_stylebox_override("fill", Ui.style_box(Color(accent, 0.65), accent, 5))
	box.add_child(progress)
	box.add_child(Ui.label("%d / %d COLLECTED • TAP A CARD" % [found, card_ids.size()], 12, Ui.TEXT_DIM))
	if lock_reason != "":
		var lock := Ui.label(lock_reason, 12, Ui.NEON_MAGENTA)
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(lock)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	for card_id in card_ids:
		var data := _card_data(str(card_id))
		var card := CardView.new()
		card.data = data
		card.quantity = int(owned.get(str(card_id), 0))
		card.pressed.connect(_show_card.bind(data))
		grid.add_child(card)
	box.add_child(grid)
	var reward := Ui.label("COMPLETE THE ALBUM\n" + Ui.reward_text(_set_reward(set_data)), 17, Ui.GOLD)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reward)
	var claimed: Array = Store.state.get("completedSets", [])
	var is_claimed := claimed.has(set_data.get("setId", ""))
	var complete := not card_ids.is_empty() and found == card_ids.size()
	var claim := Ui.button("REWARD COLLECTED" if is_claimed else "CLAIM REWARD", Ui.GOLD, not complete or lock_reason != "")
	claim.disabled = _busy or not complete or lock_reason != "" or is_claimed
	claim.pressed.connect(_claim_set.bind(str(set_data.get("setId", ""))))
	box.add_child(claim)
	panel.add_child(box)
	return panel

func _modal(title: String) -> Dictionary:
	var dialog := Neon.modal(self, title, 7, Ui.NEON_MAGENTA, "CLOSE")
	dialog.close.grab_focus()
	return dialog

func _show_card(data: Dictionary) -> void:
	var modal := _modal(str(data.get("name", "Card")))
	var content: VBoxContainer = modal.content
	var center := CenterContainer.new()
	var card := CardView.new()
	card.data = data
	card.large = true
	card.quantity = int(_owned_map().get(str(data.get("cardId", "")), 0))
	card.preview = card.quantity == 0
	center.add_child(card)
	content.add_child(center)
	card.custom_minimum_size = Vector2(minf(size.x - Ui.SAFE_MARGIN * 2, 310), 390)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	content.add_child(Ui.label("%s • %s" % [data.get("symbol", ""), str(data.get("rarity", "common")).to_upper()], 20, Ui.tier_color(str(data.get("rarity", "common")))))
	content.add_child(Ui.label(_set_name(str(data.get("setId", ""))), 18, Ui.TEXT))
	var message := "Not collected yet. Find this card in chests." if card.quantity == 0 else ("%d owned • %d duplicates" % [card.quantity, maxi(0, card.quantity - 1)])
	var caption := Ui.label(message, 15, Ui.TEXT_DIM)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(caption)

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
		var modal := _modal("ALBUM COMPLETE")
		modal.content.add_child(Ui.label(_set_name(set_id), 24, Ui.GOLD))
		var reward := Ui.label(Ui.reward_text(data.get("reward", {}), "\n"), 25, Ui.GOLD)
		reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		modal.content.add_child(reward)

func _mutate(path: String, body: Dictionary, event_name: String) -> Dictionary:
	if _busy:
		return {}
	_busy = true
	_feedback.visible = false
	_refresh()
	var rid := Net.request_id()
	body["requestId"] = rid
	var response := await Net.protected_request("POST", path, body, rid)
	var data: Dictionary = response.data if response.ok and typeof(response.data) == TYPE_DICTIONARY else {}
	if response.ok:
		Store.apply_collection_mutation(path, data)
		Events.track(event_name, body)
		await _sync_state()
	else:
		Sfx.error()
		Haptics.error()
		_feedback.text = "Action unavailable. Check your connection and try again."
		_feedback.visible = true
	_busy = false
	_refresh()
	return data

func _chest_cost(chest_id: String) -> int:
	for chest in Config.chests():
		if typeof(chest) == TYPE_DICTIONARY and str(chest.get("chestId", "")) == chest_id:
			return int(chest.get("priceCredits", 0))
	return 0

func _sync_state() -> bool:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok:
		Store.apply_state(state_response.data)
		return true
	_feedback.text = "Inventory refresh unavailable. Your progress remains saved on the server."
	_feedback.visible = true
	return false

func _show_drops(cards: Array) -> void:
	var modal := _modal("CACHE DECRYPTED")
	modal.close.text = "COLLECT"
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 12)
	modal.content.add_child(grid)
	var index := 0
	for drop in cards:
		if typeof(drop) != TYPE_DICTIONARY:
			continue
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card := CardView.new()
		card.data = _card_data(str(drop.get("cardId", "")))
		card.quantity = maxi(1, int(_owned_map().get(str(drop.get("cardId", "")), 1)))
		card.pressed.connect(_show_card.bind(card.data))
		box.add_child(card)
		box.add_child(Ui.label("DUPLICATE" if drop.get("duplicate", false) else "NEW CARD!", 12, Ui.GOLD))
		grid.add_child(box)
		Ui.reveal(box, minf(index * 0.10, 1.2))
		index += 1
	Sfx.result("rare")
