extends Control
## Store — aucune publicité forcée, preuves simulées uniquement en build debug.

signal navigate_requested(tab: String)

var _content: VBoxContainer
var _busy := false

func _ready() -> void:
	var body := Ui.screen_body()
	body.add_child(Ui.hero_card("res://assets/generated/api_gpt/heroes/store_hero.png", "FREEBIES  •  BOOSTS  •  LOOT", "Neon Store", "Bonus gratuits et offres optionnelles.", Ui.NEON_MAGENTA))
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
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(Ui.section_title("OPTIONS GRATUITES", Ui.NEON_CYAN))
	var free_card := _free_card()
	_content.add_child(free_card)
	Ui.reveal(free_card)
	_content.add_child(Ui.section_title("OFFRES LIMITÉES", Ui.NEON_MAGENTA))
	var any_offer := false
	for offer in Config.offers():
		if typeof(offer) == TYPE_DICTIONARY and Store.now_ms() >= int(offer.get("startsAtMs", 0)) and Store.now_ms() < int(offer.get("endsAtMs", 0)):
			var card := _offer_card(offer)
			_content.add_child(card)
			Ui.reveal(card, 0.05 if not any_offer else 0.10)
			any_offer = true
	if not any_offer:
		_content.add_child(Ui.label("Aucune offre active. Le jeu reste entièrement jouable gratuitement.", 14, Ui.TEXT_DIM))
	_content.add_child(Ui.section_title("COFFRES EN CRÉDITS", Ui.GOLD))
	var cards_button := Ui.button("OUVRIR LA COLLECTION", Ui.GOLD, true)
	cards_button.pressed.connect(func() -> void: navigate_requested.emit("collection"))
	_content.add_child(cards_button)

func _free_card() -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.add_child(Ui.label("RÉCOMPENSE VOLONTAIRE", 19, Ui.TEXT))
	var cfg: Dictionary = Config.economy().get("adsConfig", {})
	var watched := int(Store.state.get("adsWatchedToday", 0))
	var maximum := int(cfg.get("maxRewardedAdsPerDay", 0))
	box.add_child(Ui.label("+%d SPINS  •  %d / %d AUJOURD'HUI" % [int(cfg.get("rewardPerAd", 0)), watched, maximum], 14, Ui.TEXT_DIM))
	var ad := Ui.button("REGARDER UNE PUB", Ui.NEON_CYAN)
	ad.disabled = _busy or watched >= maximum or not Wallet.is_dev()
	ad.pressed.connect(_reward_ad)
	box.add_child(ad)
	var wait := Ui.button("ATTENDRE  " + Ui.mmss(Store.regen_remaining_ms()), Ui.TEXT_DIM, true)
	wait.disabled = true
	box.add_child(wait)
	panel.add_child(box)
	return panel

func _offer_card(offer: Dictionary) -> PanelContainer:
	var panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_MAGENTA)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Ui.label(str(offer.get("name", "Offer")).to_upper(), 23, Ui.NEON_MAGENTA))
	var lines := ""
	for content in offer.get("contents", []):
		var typ := str(content.get("type", "reward")).to_upper()
		lines += "+%s %s\n" % [Ui.compact(int(content.get("amount", 0))), typ]
	var detail := Ui.label(lines.strip_edges(), 16, Ui.TEXT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(detail)
	box.add_child(Ui.label("EXPIRE DANS  " + Ui.mmss_long(int(offer.get("endsAtMs", 0)) - Store.now_ms()), 12, Ui.TEXT_DIM))
	var buy := Ui.button("%s  %s" % [Ui.compact(int(offer.get("priceU64", 0))), str(offer.get("priceToken", "SKR"))], Ui.NEON_MAGENTA)
	buy.disabled = _busy or not Wallet.is_dev()
	buy.pressed.connect(_buy_offer.bind(offer))
	box.add_child(buy)
	var note := Ui.label("MODE TEST  •  AUCUN DÉBIT RÉEL", 11, Ui.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	panel.add_child(box)
	return panel

func _reward_ad() -> void:
	if _busy:
		return
	_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/ad/reward", {"receipt": "dev:" + rid, "requestId": rid}, rid)
	await _finish_mutation(response, "ad_reward")

func _buy_offer(offer: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/purchase/verify", {
		"offerId": offer.get("offerId", ""), "txSignature": "dev:" + rid,
		"tokenMint": offer.get("priceToken", ""), "amountU64": offer.get("priceU64", 0), "requestId": rid
	}, rid)
	await _finish_mutation(response, "purchase")

func _finish_mutation(response: Dictionary, event_name: String) -> void:
	if response.ok:
		Store.apply_mutation(response.data)
		Events.track(event_name)
		Sfx.result("epic")
		var state_response := await Net.protected_request("GET", "/state")
		if state_response.ok:
			Store.apply_state(state_response.data)
	else:
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()
