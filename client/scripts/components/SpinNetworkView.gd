extends RefCounted
## Vue du Seeker Network. Le contrôleur SpinScreen conserve les mutations et
## snapshots ; cette classe ne fait qu'assembler la modale et câbler ses actions.

var host

func _init(owner: Control) -> void:
	host = owner

func render() -> void:
	host._clear_social_overlay()
	host._social_overlay = ColorRect.new()
	host._social_overlay.color = Color(0.015, 0.02, 0.07, 0.97)
	host._social_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	host._social_overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_CYAN)
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	var title_row := HBoxContainer.new()
	var title := Ui.label("SEEKER NETWORK", 28, Ui.NEON_CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close := Ui.button("✕", Ui.NEON_MAGENTA, true)
	close.pressed.connect(host._clear_social_overlay)
	title_row.add_child(close)
	shell.add_child(title_row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Ui.style_scroll(scroll, Ui.NEON_CYAN)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_build_profile(content)
	_build_search(content)
	_build_requests(content)
	_build_friends(content)
	_build_revenge(content)
	_build_team(content)
	_build_trades(content)
	_build_leaderboard(content)
	scroll.add_child(content)
	shell.add_child(scroll)
	panel.add_child(shell)
	center.add_child(panel)
	host._social_overlay.add_child(center)
	host.add_child(host._social_overlay)

func _section(parent: VBoxContainer, title: String) -> void:
	var label := Ui.label(title, 17, Ui.GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(label)

func _build_profile(parent: VBoxContainer) -> void:
	_section(parent, "PROFILE")
	var profile: Dictionary = Store.state.get("profile", {})
	var progression: Dictionary = Store.state.get("progression", {})
	parent.add_child(Ui.label("%s  •  %s" % [str(profile.get("playerId", "NO CODE")), str(progression.get("name", "NETWORK POWER")).to_upper()], 13, Ui.TEXT_DIM))
	parent.add_child(Ui.label("%s PWR  •  DISTRICT %d" % [Ui.compact(int(progression.get("score", 0))), int(profile.get("districtIndex", 0)) + 1], 19, Ui.TEXT))
	var edit_row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = str(profile.get("displayName", "Runner"))
	name_edit.max_length = 24
	name_edit.custom_minimum_size.y = 52
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_row.add_child(name_edit)
	var save := Ui.button("SAVE", Ui.NEON_CYAN)
	save.pressed.connect(host._network_update_profile.bind(name_edit))
	edit_row.add_child(save)
	parent.add_child(edit_row)
	if host._network_message != "":
		parent.add_child(Ui.label(host._network_message, 13, Ui.NEON_MAGENTA))

func _build_search(parent: VBoxContainer) -> void:
	_section(parent, "FIND A PLAYER")
	var row := HBoxContainer.new()
	var query := LineEdit.new()
	query.placeholder_text = "Friend code or name"
	query.max_length = 24
	query.custom_minimum_size.y = 52
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(query)
	var search := Ui.button("SEARCH", Ui.NEON_CYAN)
	search.pressed.connect(host._network_search.bind(query))
	row.add_child(search)
	parent.add_child(row)
	for result in host._network_results:
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
			action.pressed.connect(host._network_friend_action.bind("/friends/request", str(result.get("playerId", "")), "friend_request_sent"))
		result_row.add_child(action)
		parent.add_child(result_row)

func _build_requests(parent: VBoxContainer) -> void:
	var incoming: Array = host._network_snapshot.get("incoming", [])
	if incoming.is_empty():
		return
	_section(parent, "REQUESTS")
	for request in incoming:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		var row := HBoxContainer.new()
		var label := Ui.label(str(request.get("displayName", "Runner")), 13, Ui.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var accept := Ui.button("ACCEPT", Ui.GREEN)
		accept.pressed.connect(host._network_friend_action.bind("/friends/accept", str(request.get("playerId", "")), "friend_request_accepted"))
		row.add_child(accept)
		var decline := Ui.button("DECLINE", Ui.NEON_MAGENTA, true)
		decline.pressed.connect(host._network_friend_action.bind("/friends/decline", str(request.get("playerId", "")), "friend_request_declined"))
		row.add_child(decline)
		parent.add_child(row)

func _build_friends(parent: VBoxContainer) -> void:
	var friends: Array = host._network_snapshot.get("friends", [])
	_section(parent, "FRIENDS  •  %d" % friends.size())
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
		target.pressed.connect(host._network_select_target.bind(str(friend.get("playerId", "")), "friend"))
		row.add_child(target)
		parent.add_child(row)

func _build_revenge(parent: VBoxContainer) -> void:
	var attacks: Array = host._network_snapshot.get("recentAttacks", [])
	if attacks.is_empty():
		return
	_section(parent, "RECENT SIGNAL JAMS")
	for attack in attacks.slice(0, mini(5, attacks.size())):
		if typeof(attack) != TYPE_DICTIONARY:
			continue
		var row := HBoxContainer.new()
		var status := "BLOCKED" if bool(attack.get("blocked", false)) else "JAMMED"
		var label := Ui.label("%s  •  %s" % [str(attack.get("displayName", "Runner")), status], 13, Ui.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var revenge := Ui.button("REVENGE", Ui.NEON_MAGENTA)
		revenge.disabled = not bool(attack.get("canRevenge", false))
		revenge.pressed.connect(host._network_select_target.bind(str(attack.get("playerId", "")), "revenge"))
		row.add_child(revenge)
		parent.add_child(row)

func _build_team(parent: VBoxContainer) -> void:
	_section(parent, "CREW")
	var team_rules: Dictionary = Config.social().get("teams", {})
	var max_members := int(team_rules.get("maxMembers", 50))
	var create_cost := int(team_rules.get("createCostCredits", 0))
	var own: Variant = host._team_snapshot.get("ownTeam", null)
	if typeof(own) == TYPE_DICTIONARY:
		var team: Dictionary = own
		parent.add_child(Ui.label("%s  •  %s" % [str(team.get("name", "Crew")), str(team.get("teamCode", ""))], 16, Ui.NEON_CYAN))
		parent.add_child(Ui.label("%d MEMBERS  •  %s PWR" % [team.get("members", []).size(), Ui.compact(int(team.get("score", 0)))], 13, Ui.TEXT_DIM))
		var is_owner := str(team.get("role", "member")) == "owner"
		for member in team.get("members", []):
			if typeof(member) != TYPE_DICTIONARY:
				continue
			var member_row := HBoxContainer.new()
			var role_suffix := "  •  OWNER" if str(member.get("role", "member")) == "owner" else ""
			var member_label := Ui.label("%s  •  %s PWR%s" % [str(member.get("displayName", "Runner")), Ui.compact(int(member.get("score", 0))), role_suffix], 12, Ui.TEXT)
			member_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			member_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			member_row.add_child(member_label)
			if is_owner and str(member.get("role", "member")) != "owner":
				var transfer := Ui.button("LEAD", Ui.NEON_CYAN, true)
				transfer.pressed.connect(host._network_team_member_action.bind("/teams/transfer", str(member.get("playerId", "")), "team_owner_transferred"))
				member_row.add_child(transfer)
				var kick := Ui.button("KICK", Ui.NEON_MAGENTA, true)
				kick.pressed.connect(host._network_team_member_action.bind("/teams/kick", str(member.get("playerId", "")), "team_member_kicked"))
				member_row.add_child(kick)
			parent.add_child(member_row)
		var leave := Ui.button("DISBAND" if is_owner and team.get("members", []).size() == 1 else "LEAVE CREW", Ui.NEON_MAGENTA, true)
		leave.disabled = is_owner and team.get("members", []).size() > 1
		leave.pressed.connect(host._network_team_leave)
		parent.add_child(leave)
	else:
		var create_row := HBoxContainer.new()
		var team_name := LineEdit.new()
		team_name.placeholder_text = "Crew name (%s CR)" % Ui.compact(create_cost)
		team_name.max_length = 24
		team_name.custom_minimum_size.y = 52
		team_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		create_row.add_child(team_name)
		var create := Ui.button("CREATE", Ui.NEON_CYAN)
		create.pressed.connect(host._network_team_create.bind(team_name))
		create_row.add_child(create)
		parent.add_child(create_row)
		var search_row := HBoxContainer.new()
		var team_query := LineEdit.new()
		team_query.placeholder_text = "Crew name or NET-code"
		team_query.max_length = 24
		team_query.custom_minimum_size.y = 52
		team_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		search_row.add_child(team_query)
		var search := Ui.button("FIND", Ui.NEON_CYAN)
		search.pressed.connect(host._network_team_search.bind(team_query))
		search_row.add_child(search)
		parent.add_child(search_row)
		for result in host._team_results.slice(0, mini(10, host._team_results.size())):
			if typeof(result) != TYPE_DICTIONARY:
				continue
			var result_row := HBoxContainer.new()
			var result_label := Ui.label("%s  •  %d/%d  •  %s PWR" % [str(result.get("name", "Crew")), int(result.get("memberCount", 0)), max_members, Ui.compact(int(result.get("score", 0)))], 12, Ui.TEXT)
			result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			result_row.add_child(result_label)
			var join := Ui.button("JOIN", Ui.GREEN)
			join.disabled = bool(result.get("full", false))
			join.pressed.connect(host._network_team_join.bind(str(result.get("teamCode", ""))))
			result_row.add_child(join)
			parent.add_child(result_row)
	var team_entries: Array = host._team_leaderboard.get("entries", [])
	if not team_entries.is_empty():
		parent.add_child(Ui.label("TOP CREWS", 13, Ui.GOLD))
		for entry in team_entries.slice(0, mini(5, team_entries.size())):
			if typeof(entry) == TYPE_DICTIONARY:
				parent.add_child(Ui.label("#%d  %s  •  %s PWR" % [int(entry.get("rank", 0)), str(entry.get("name", "Crew")), Ui.compact(int(entry.get("score", 0)))], 12, Ui.TEXT_DIM))

func _build_trades(parent: VBoxContainer) -> void:
	_section(parent, "CARD SWAPS")
	var incoming: Array = host._trades_snapshot.get("incoming", [])
	var outgoing: Array = host._trades_snapshot.get("outgoing", [])
	for trade in incoming:
		if typeof(trade) != TYPE_DICTIONARY or str(trade.get("status", "")) != "pending":
			continue
		var row := VBoxContainer.new()
		row.add_child(Ui.label("%s OFFERS %s  •  WANTS %s" % [str(trade.get("counterpartyDisplayName", "Runner")), str(trade.get("offeredCardName", "Card")), str(trade.get("requestedCardName", "Card"))], 12, Ui.TEXT))
		var actions := HBoxContainer.new()
		var accept := Ui.button("ACCEPT", Ui.GREEN)
		accept.pressed.connect(host._network_trade_action.bind("/trades/accept", str(trade.get("tradeId", "")), "trade_accepted", true))
		actions.add_child(accept)
		var decline := Ui.button("DECLINE", Ui.NEON_MAGENTA, true)
		decline.pressed.connect(host._network_trade_action.bind("/trades/decline", str(trade.get("tradeId", "")), "trade_declined", false))
		actions.add_child(decline)
		row.add_child(actions)
		parent.add_child(row)
	for trade in outgoing:
		if typeof(trade) != TYPE_DICTIONARY or str(trade.get("status", "")) != "pending":
			continue
		var row := HBoxContainer.new()
		var label := Ui.label("TO %s  •  %s → %s" % [str(trade.get("counterpartyDisplayName", "Runner")), str(trade.get("offeredCardName", "Card")), str(trade.get("requestedCardName", "Card"))], 12, Ui.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var cancel := Ui.button("CANCEL", Ui.NEON_MAGENTA, true)
		cancel.pressed.connect(host._network_trade_action.bind("/trades/cancel", str(trade.get("tradeId", "")), "trade_cancelled", false))
		row.add_child(cancel)
		parent.add_child(row)
	var friends: Array = host._network_snapshot.get("friends", [])
	var rules: Dictionary = host._trades_snapshot.get("rules", {})
	var minimum := int(rules.get("minQuantity", 2))
	var tradeable: Array = rules.get("tradeableRarities", [])
	var duplicates: Array = []
	for owned in Store.state.get("cards", []):
		if typeof(owned) == TYPE_DICTIONARY and int(owned.get("qty", 0)) >= minimum:
			for card in Config.cards():
				if typeof(card) == TYPE_DICTIONARY and str(card.get("cardId", "")) == str(owned.get("cardId", "")) and tradeable.has(str(card.get("rarity", ""))):
					duplicates.append(card)
					break
	if friends.is_empty() or duplicates.is_empty():
		parent.add_child(Ui.label("Ajoute un ami et garde au moins un doublon échangeable.", 12, Ui.TEXT_DIM))
		return
	var friend_menu := OptionButton.new()
	friend_menu.custom_minimum_size.y = 52
	for friend in friends:
		if typeof(friend) == TYPE_DICTIONARY:
			friend_menu.add_item(str(friend.get("displayName", "Runner")))
			friend_menu.set_item_metadata(friend_menu.item_count - 1, str(friend.get("playerId", "")))
	parent.add_child(friend_menu)
	var offered_menu := OptionButton.new()
	offered_menu.custom_minimum_size.y = 52
	for card in duplicates:
		offered_menu.add_item("GIVE  •  " + str(card.get("name", "Card")))
		offered_menu.set_item_metadata(offered_menu.item_count - 1, str(card.get("cardId", "")))
	parent.add_child(offered_menu)
	var requested_menu := OptionButton.new()
	requested_menu.custom_minimum_size.y = 52
	for card in Config.cards():
		if typeof(card) == TYPE_DICTIONARY and tradeable.has(str(card.get("rarity", ""))):
			requested_menu.add_item("GET  •  " + str(card.get("name", "Card")))
			requested_menu.set_item_metadata(requested_menu.item_count - 1, str(card.get("cardId", "")))
	parent.add_child(requested_menu)
	var propose := Ui.button("PROPOSE 1-FOR-1 SWAP", Ui.NEON_CYAN)
	propose.pressed.connect(host._network_trade_create.bind(friend_menu, offered_menu, requested_menu))
	parent.add_child(propose)

func _build_leaderboard(parent: VBoxContainer) -> void:
	_section(parent, "GLOBAL NETWORK")
	parent.add_child(Ui.label("YOUR RANK  •  #%d" % int(host._network_leaderboard.get("playerRank", 0)), 14, Ui.NEON_CYAN))
	var entries: Array = host._network_leaderboard.get("entries", [])
	for entry in entries.slice(0, mini(10, entries.size())):
		if typeof(entry) == TYPE_DICTIONARY:
			var line := Ui.label("#%d  %s  •  %s PWR" % [int(entry.get("rank", 0)), str(entry.get("displayName", "Runner")), Ui.compact(int(entry.get("score", 0)))], 13, Ui.TEXT_DIM)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			parent.add_child(line)
