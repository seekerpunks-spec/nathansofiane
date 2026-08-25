extends RefCounted
## Mutations du Seeker Network. Toutes passent par les endpoints idempotents ;
## SpinScreen ne conserve que des wrappers utilisés par la vue.

var host

func _init(owner: Control) -> void:
	host = owner

func team_create(input: LineEdit) -> void:
	if host._social_busy or input.text.strip_edges().length() < 3:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/teams/create", {"name": input.text, "requestId": rid}, rid)
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		Events.track("team_created", {"teamCode": response.data.get("teamCode", "")})
		Store.apply_mutation(response.data)
	host._network_message = "CREW CREATED" if response.ok else "CREW CREATION REFUSED"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func team_search(input: LineEdit) -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var response := await Net.protected_request("GET", "/teams?q=" + input.text.strip_edges().uri_encode())
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		host._team_snapshot = response.data
		host._team_results = response.data.get("results", [])
		host._network_message = ""
	else:
		host._network_message = "CREW SEARCH FAILED"
	host._social_busy = false
	host._render_network()

func team_join(team_code: String) -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/teams/join", {"teamCode": team_code, "requestId": rid}, rid)
	if response.ok:
		Events.track("team_joined", {"teamCode": team_code})
	host._network_message = "CREW JOINED" if response.ok else "JOIN REFUSED"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func team_leave() -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/teams/leave", {"requestId": rid}, rid)
	if response.ok:
		Events.track("team_left", {"teamDeleted": response.data.get("teamDeleted", false) if typeof(response.data) == TYPE_DICTIONARY else false})
	host._network_message = "CREW LEFT" if response.ok else "TRANSFER LEADERSHIP FIRST"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func team_member_action(path: String, player_id: String, event_name: String) -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", path, {"friendCode": player_id, "requestId": rid}, rid)
	if response.ok:
		Events.track(event_name, {"playerId": player_id})
	host._network_message = "CREW UPDATED" if response.ok else "CREW ACTION REFUSED"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func trade_create(friend_menu: OptionButton, offered_menu: OptionButton, requested_menu: OptionButton) -> void:
	if host._social_busy or friend_menu.item_count == 0 or offered_menu.item_count == 0 or requested_menu.item_count == 0:
		return
	var recipient := str(friend_menu.get_item_metadata(friend_menu.selected))
	var offered := str(offered_menu.get_item_metadata(offered_menu.selected))
	var requested := str(requested_menu.get_item_metadata(requested_menu.selected))
	if offered == requested:
		host._network_message = "CHOOSE TWO DIFFERENT CARDS"
		host._render_network()
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/trades/create", {
		"recipientFriendCode": recipient, "offeredCardId": offered,
		"requestedCardId": requested, "requestId": rid
	}, rid)
	if response.ok:
		Events.track("trade_created", {"recipientPlayerId": recipient, "offeredCardId": offered, "requestedCardId": requested})
	host._network_message = "SWAP PROPOSED" if response.ok else "DUPLICATE NOT AVAILABLE"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func trade_action(path: String, trade_id: String, event_name: String, sync_state: bool) -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", path, {"tradeId": trade_id, "requestId": rid}, rid)
	if response.ok:
		Events.track(event_name, {"tradeId": trade_id})
		if sync_state:
			var state_response := await Net.protected_request("GET", "/state")
			if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
				Store.apply_state(state_response.data)
	host._network_message = "SWAP UPDATED" if response.ok else "SWAP NO LONGER AVAILABLE"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func search(query: LineEdit) -> void:
	if host._social_busy or query.text.strip_edges().length() < 2:
		return
	host._social_busy = true
	var response := await Net.protected_request("GET", "/players/search?q=" + query.text.strip_edges().uri_encode())
	host._network_results = response.data.get("results", []) if response.ok and typeof(response.data) == TYPE_DICTIONARY else []
	host._network_message = "" if response.ok else "SEARCH FAILED"
	host._social_busy = false
	host._render_network()

func update_profile(input: LineEdit) -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/profile", {"displayName": input.text, "requestId": rid}, rid)
	if response.ok:
		Events.track("profile_updated")
		var state_response := await Net.protected_request("GET", "/state")
		if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
			Store.apply_state(state_response.data)
	host._network_message = "PROFILE UPDATED" if response.ok else "INVALID PROFILE NAME"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func friend_action(path: String, player_id: String, event_name: String) -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", path, {"friendCode": player_id, "requestId": rid}, rid)
	if response.ok:
		Events.track(event_name, {"playerId": player_id})
	host._network_message = "NETWORK UPDATED" if response.ok else "ACTION REFUSED"
	host._network_results.clear()
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()

func select_target(player_id: String, source: String) -> void:
	if host._social_busy:
		return
	host._social_busy = true
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/social/target", {"friendCode": player_id, "source": source, "requestId": rid}, rid)
	if response.ok:
		Events.track("social_target_selected", {"playerId": player_id, "source": source})
	host._network_message = "TARGET ARMED FOR NEXT SIGNAL JAM" if response.ok else "TARGET NOT AVAILABLE"
	await host._fetch_network_data()
	host._social_busy = false
	host._render_network()
