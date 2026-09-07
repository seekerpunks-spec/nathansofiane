extends Control
## Store — aucune publicité forcée, preuves simulées uniquement en build debug.

signal navigate_requested(tab: String)

var _content: VBoxContainer
var _busy := false
var _ad_offer_tracked := false
var _tracked_offer_views: Dictionary = {}
var _eligible_offers: Array = []

func _ready() -> void:
	add_child(Ui.illustrated_stage("res://assets/generated/api_gpt/heroes/store_hero.webp"))
	var body := Ui.screen_body()
	body.add_child(Ui.kicker_block("FREEBIES  •  BOOSTS  •  LOOT", "Shop", Ui.NEON_MAGENTA))
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
	# Les captures QA s'exécutent sans serveur. Un meta posé avant l'entrée dans
	# l'arbre fournit alors un catalogue déterministe et évite une course entre
	# le fixture et l'appel HTTP. Aucun écran de production ne pose ce meta.
	if has_meta("qa_offers"):
		_eligible_offers = get_meta("qa_offers", [])
		_refresh()
	else:
		_refresh()
		_load_offers.call_deferred()

func _load_offers() -> void:
	var response := await Net.protected_request("GET", "/offers")
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		_eligible_offers = response.data.get("items", [])
		Store.set_clock(int(response.data.get("serverTimeMs", 0)))
	else:
		_eligible_offers = []
	_refresh()

func _refresh() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(Ui.section_title("FREEBIES", Ui.NEON_CYAN))
	var free_card := _free_card()
	_content.add_child(free_card)
	Ui.reveal(free_card)
	_content.add_child(Ui.section_title("LIMITED OFFERS", Ui.NEON_MAGENTA))
	var any_offer := false
	for offer in _eligible_offers:
		if typeof(offer) == TYPE_DICTIONARY:
			var card := _offer_card(offer)
			_content.add_child(card)
			Ui.reveal(card, 0.05 if not any_offer else 0.10)
			any_offer = true
	if not any_offer:
		_content.add_child(Ui.label("No active offers. The game stays fully playable for free.", 14, Ui.TEXT_DIM))
	_content.add_child(Ui.section_title("CREDIT CACHES", Ui.GOLD))
	var cards_button := Ui.button("OPEN COLLECTION", Ui.GOLD, true)
	cards_button.pressed.connect(func() -> void: navigate_requested.emit("collection"))
	_content.add_child(cards_button)

func _free_card() -> PanelContainer:
	var panel := Ui.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.add_child(Ui.label("OPT-IN REWARD", 19, Ui.TEXT))
	var cfg: Dictionary = Config.economy().get("adsConfig", {})
	if not _ad_offer_tracked:
		_ad_offer_tracked = true
		Events.track("rewarded_ad_offer", {
			"rewardSpins": int(cfg.get("rewardPerAd", 0)),
			"maxPerDay": int(cfg.get("maxRewardedAdsPerDay", 0)),
		})
	var watched := int(Store.state.get("adsWatchedToday", 0))
	var maximum := int(cfg.get("maxRewardedAdsPerDay", 0))
	box.add_child(Ui.label("+%d SPINS  •  %d / %d TODAY" % [int(cfg.get("rewardPerAd", 0)), watched, maximum], 14, Ui.TEXT_DIM))
	var ad := Ui.button("WATCH AN AD", Ui.NEON_CYAN)
	ad.disabled = _busy or watched >= maximum or not Wallet.is_dev()
	ad.pressed.connect(_reward_ad)
	box.add_child(ad)
	var wait := Ui.button("WAIT  " + Ui.mmss(Store.regen_remaining_ms()), Ui.TEXT_DIM, true)
	wait.disabled = true
	box.add_child(wait)
	panel.add_child(box)
	return panel

func _offer_card(offer: Dictionary) -> PanelContainer:
	var offer_id := str(offer.get("offerId", ""))
	if not _tracked_offer_views.has(offer_id):
		_tracked_offer_views[offer_id] = true
		Events.track("purchase_offer_view", {
			"offerId": offer_id,
			"priceToken": str(offer.get("priceToken", "")),
			"priceU64": int(offer.get("priceU64", 0)),
		})
	var panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_MAGENTA)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Ui.label(str(offer.get("name", "Offer")).to_upper(), 23, Ui.NEON_MAGENTA))
	box.add_child(Ui.label("%s  •  %d LEFT" % [str(offer.get("kind", "limited")).to_upper(), int(offer.get("remainingPurchases", 0))], 11, Ui.TEXT_DIM))
	var lines := ""
	for content in offer.get("contents", []):
		var typ := str(content.get("type", "reward")).to_upper()
		lines += "+%s %s\n" % [Ui.compact(int(content.get("amount", 0))), typ]
	var detail := Ui.label(lines.strip_edges(), 16, Ui.TEXT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(detail)
	box.add_child(Ui.label("EXPIRES IN  " + Ui.mmss_long(int(offer.get("endsAtMs", 0)) - Store.now_ms()), 12, Ui.TEXT_DIM))
	var buy := Ui.button("%s  %s" % [Ui.compact(int(offer.get("priceU64", 0))), str(offer.get("priceToken", "SKR"))], Ui.NEON_MAGENTA)
	buy.disabled = _busy or not Wallet.is_dev()
	buy.pressed.connect(_buy_offer.bind(offer))
	box.add_child(buy)
	var note := Ui.label("TEST MODE  •  NO REAL CHARGES", 11, Ui.TEXT_DIM)
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
	await _finish_mutation(response, "rewarded_ad_complete", {})

func _buy_offer(offer: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	var offer_props := {
		"offerId": str(offer.get("offerId", "")),
		"priceToken": str(offer.get("priceToken", "")),
		"priceU64": int(offer.get("priceU64", 0)),
	}
	Events.track("purchase_started", offer_props)
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/purchase/verify", {
		"offerId": offer.get("offerId", ""), "txSignature": "dev:" + rid,
		"tokenMint": offer.get("priceToken", ""), "amountU64": offer.get("priceU64", 0), "requestId": rid
	}, rid)
	await _finish_mutation(response, "purchase_complete", offer_props)

func _finish_mutation(response: Dictionary, event_name: String, props: Dictionary) -> void:
	if response.ok:
		Store.apply_mutation(response.data)
		var completed_props := props.duplicate()
		if typeof(response.data) == TYPE_DICTIONARY:
			for key in ["offerId", "purchaseId", "rewardSpins", "adsWatchedToday", "adsRemaining"]:
				if response.data.has(key):
					completed_props[key] = response.data[key]
		Events.track(event_name, completed_props)
		if event_name == "purchase_complete":
			for content in response.data.get("contents", []):
				if typeof(content) == TYPE_DICTIONARY and str(content.get("type", "")) == "credits":
					Events.track("currency_earned", {"currency": "credits", "amount": int(content.get("amount", 0)), "source": "purchase", "offerId": completed_props.get("offerId", "")})
		Sfx.result("epic")
		var state_response := await Net.protected_request("GET", "/state")
		if state_response.ok:
			Store.apply_state(state_response.data)
		await _load_offers()
	else:
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()
