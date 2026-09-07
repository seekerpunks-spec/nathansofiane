extends Node
## Smoke test sans réseau : instancie chaque scène avec un état représentatif.
##
## Durci en R26 : `assert()` n'interrompt PAS l'exécution en headless (le run
## continuait, imprimait SMOKE_SCENES_OK et sortait en 0 malgré un échec) et
## disparaît des builds release. Chaque vérification passe donc par `_check`,
## qui compte les échecs, et le harnais sort en quit(1) si au moins une
## vérification a échoué. SMOKE_SCENES_OK n'est imprimé qu'à zéro échec.

const SCENES := [
	"res://scenes/screens/OnboardingScreen.tscn",
	"res://scenes/screens/SpinScreen.tscn",
	"res://scenes/screens/DistrictScreen.tscn",
	"res://scenes/screens/CollectionScreen.tscn",
	"res://scenes/screens/MissionsScreen.tscn",
	"res://scenes/screens/StoreScreen.tscn",
]
const SpinVisuals := preload("res://scripts/components/SpinVisuals.gd")

var _failures: int = 0

func _ready() -> void:
	call_deferred("_run")

## Remplace assert() : signale, compte, et laisse le run aller au bout pour
## rapporter TOUS les échecs d'un coup au lieu du premier seulement.
func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures += 1
		print("SMOKE_CHECK_FAILED: ", message)
		push_error("SMOKE_CHECK_FAILED: " + message)
	return condition

func _json(relative: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://../config/" + relative)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Config smoke introuvable: " + path)
		return {}
	return JSON.parse_string(file.get_as_text())

## Tous les districts livrés, scannés comme le fait le serveur. Charger seulement
## le district 1 laisserait le contenu suivant sans aucune couverture.
func _districts() -> Array:
	var result: Array = []
	var names := DirAccess.get_files_at(ProjectSettings.globalize_path("res://../config/districts"))
	names.sort()
	for name in names:
		if not name.ends_with(".json"):
			continue
		var parsed: Variant = _json("districts/" + name)
		if typeof(parsed) == TYPE_DICTIONARY:
			result.append(parsed)
	return result

func _run() -> void:
	Config.raw = {
		"economy": _json("economy.json"),
		"spinTable": _json("spin_table.json"),
		"social": _json("social.json"),
		"progression": _json("progression.json"),
		"daily": _json("daily.json"),
		"achievements": _json("achievements.json").get("items", []),
		"entitlements": _json("entitlements.json").get("items", []),
		"rewardPool": _json("reward_pool.json"),
		"districts": _districts(),
		"cards": _json("cards.json").get("items", []),
		"sets": _json("sets.json").get("items", []),
		"chests": _json("chests.json").get("items", []),
		"events": _json("events.json").get("items", []),
		"offers": _json("offers.json").get("items", []),
		"seasons": _json("seasons.json").get("items", []),
	}
	Config._index_outcomes()
	_check_building_art()
	var credits_only := Ui.reward_text({"credits": 300000})
	_check(credits_only == "+300K CR", "récompense crédits-only mal formatée: " + credits_only)
	_check(not credits_only.contains("SPINS"), "récompense crédits-only invente des spins")
	_check(Ui.reward_text({"chest": "basic"}) == "+1 BASIC CACHE", "coffre-only mal formaté")
	var mixed_reward := Ui.reward_text({"spins": 25, "credits": 100000, "chest": "neon"})
	_check(mixed_reward.contains("+25 SPINS"), "spins absents de la récompense mixte")
	_check(mixed_reward.contains("+100K CR"), "crédits absents de la récompense mixte")
	_check(mixed_reward.contains("+1 NEON CACHE"), "coffre absent de la récompense mixte")
	_check(
		SpinVisuals.symbols_for_result({"type": "attack", "tier": "rare"}) == ["hack", "hack", "hack"],
		"mapping visuel Attack invalide"
	)
	_check(
		SpinVisuals.symbols_for_result({"type": "credits", "tier": "legendary"}) == ["credits", "credits", "credits"],
		"mapping visuel jackpot invalide"
	)
	var juice_btn := Ui.button("SPIN", Ui.NEON_CYAN)
	_check(juice_btn.offset_transform_enabled, "Juice.arm n'active pas offset_transform_enabled")
	_check(juice_btn.offset_transform_pivot_ratio == Vector2(0.5, 0.5), "pivot juice hors centre")
	juice_btn.free()
	_check(ResourceLoader.exists("res://assets/generated/ui/star.webp"), "chrome star absent")
	_check(ResourceLoader.exists("res://assets/generated/ui/hammer.webp"), "chrome hammer absent")
	_check(ResourceLoader.exists("res://assets/generated/ui/wrench.webp"), "chrome wrench absent")
	_check(ResourceLoader.exists("res://assets/fonts/Nunito-ExtraBold.ttf"), "police Nunito absente")
	var polish_box := Ui.style_box()
	_check(polish_box.anti_aliasing, "StyleBoxFlat anti_aliasing off")
	_check(polish_box.corner_detail == 1, "R42: cadres biseautes attendus")
	var probe := Control.new()
	Preferences.reduced_motion = true
	Juice.pop(probe, 1.2, 0.2)
	_check(probe.offset_transform_scale == Vector2.ONE, "reduced_motion doit ignorer le pop")
	probe.free()
	Preferences.reduced_motion = false
	_check(
		SpinVisuals.symbols_for_result({"type": "none"}) == ["glitch", "credits", "energy"],
		"mapping visuel spin vide invalide"
	)
	Store.apply_state({
		"spins": 12, "credits": 8500000, "serverTimeMs": int(Time.get_unix_time_from_system() * 1000),
		"nextSpinAtMs": int(Time.get_unix_time_from_system() * 1000) + 180000,
		"districtProgress": [{"districtId":1,"elementId":1,"level":2}],
		"cards": [{"cardId":"ghost_terminal","qty":2}], "chests": [{"chestId":"basic","qty":1}],
		"completedSets": [], "dailyStreak": 2, "dailyAvailable": true, "adsWatchedToday": 1,
		"missions": [{"missionId":"use_spins","name":"Use 10 Spins","target":10,"progress":6,"claimed":false,"reward":{"spins":20}}],
		"profile": {"playerId":"CYB-000000000001","displayName":"Smoke Runner","districtIndex":0},
		"achievements": [{"achievementId":"signal_runner_1","name":"Signal Runner I","description":"Spend 10 spins.","target":10,"progress":10,"claimed":false,"reward":{"spins":25,"credits":100000}}],
		"entitlements": {"dailySpinBonus":0,"items":[],"verificationMode":"server_provider_required"},
		"rewardPool": {"enabled":false,"settlementEnabled":false,"pools":[]},
		"events": [{"eventId":"neon_rush_r17","name":"Neon Rush","endsAtMs":Store.now_ms()+86400000,"points":420}],
		"seasons": [{"seasonId":"neon_genesis","name":"Neon Genesis","points":600,"premium":false,"freeClaimed":[]}],
	})
	for path in SCENES:
		var packed: PackedScene = load(path)
		if not _check(packed != null, "Scène introuvable: " + path):
			continue
		var instance := packed.instantiate()
		if not _check(instance.get_script() != null, "Script non chargé: " + path):
			instance.queue_free()
			continue
		instance.set_meta("qa_skip_sync", true)
		instance.set_meta("qa_offers", [])
		add_child(instance)
		await get_tree().process_frame
		if path.ends_with("DistrictScreen.tscn"):
			await _check_district_screen(instance)
		if path.ends_with("CollectionScreen.tscn"):
			_check_collection_screen(instance)
			_check_horizontal_bounds(instance)
		if path.ends_with("SpinScreen.tscn"):
			_check_reference_home(instance)
			instance._network_snapshot = {
				"giftRules":{"rewardSpins":1,"maxSentPerDay":20,"sentToday":0},
				"friends":[{"playerId":"CYB-000000000002","displayName":"Long Friend Name","score":123456,"giftedToday":false}],
				"incoming":[],"recentAttacks":[]
			}
			instance._team_snapshot = {"ownTeam":{
				"name":"Smoke Crew","teamCode":"NET-0000000000000001","role":"owner","score":999999,
				"members":[
					{"playerId":"CYB-000000000001","displayName":"Smoke Runner","role":"owner","score":500000},
					{"playerId":"CYB-000000000002","displayName":"Long Crew Member","role":"member","score":499999}
				],
				"quickChatPhrases":Config.social().get("teams", {}).get("quickChatPhrases", []),
				"messages":[{"phraseId":"thanks","displayName":"Long Crew Member"}],
				"helpRules":{"requestSpins":5,"maxPerMember":2},
				"helpRequests":[{"helpId":"00000000-0000-4000-8000-000000000001","requesterPlayerId":"CYB-000000000002","displayName":"Long Crew Member","requestedSpins":5,"donatedSpins":2,"canDonate":true}]
			}}
			instance._render_network()
			await get_tree().process_frame
			_check(is_instance_valid(instance._social_overlay), "Modale Seeker Network absente")
			_check_horizontal_bounds(instance._social_overlay)
			instance._clear_social_overlay()
			instance._show_social_encounter({"kind":"attack","encounterId":"smoke-attack","target":"Runner","choices":[1,2],"multiplier":4})
			await get_tree().process_frame
			_check(is_instance_valid(instance._social_overlay), "Modale Attack absente")
			instance._show_social_encounter({"kind":"raid","encounterId":"smoke-raid","target":"Vault","nodeCount":6,"picked":[0],"unbankedCredits":1000,"canCashout":true})
			await get_tree().process_frame
			_check(is_instance_valid(instance._social_overlay), "Modale Raid absente")
			instance._show_social_result("SMOKE RESULT", false)
			instance._clear_social_overlay()
		instance.queue_free()
		await get_tree().process_frame
	await _check_reference_shell()
	# Let the audio mixer release the last navigation click before engine exit.
	Sfx.stop_all()
	await get_tree().create_timer(0.06).timeout
	if _failures > 0:
		print("SMOKE_SCENES_FAILED: ", _failures)
		get_tree().quit(1)
		return
	print("SMOKE_SCENES_OK: ", SCENES.size())
	get_tree().quit(0)

## Les scènes pouvaient être instanciées avec succès tout en poussant leurs
## actions hors du viewport. Les contrôles critiques s'inscrivent explicitement
## dans ce groupe afin que chaque résolution de la gate vérifie leurs bounds.
func _check_reference_shell() -> void:
	var shell := preload("res://scenes/Main.tscn").instantiate()
	shell.qa_bypass_boot = true
	add_child(shell)
	shell._enter_game("spin")
	await get_tree().process_frame
	_check(shell._nav_buttons.size() == 6, "R42: six navigation tabs expected")
	shell._on_nav_pressed("events")
	await get_tree().process_frame
	_check(shell._current_tab == "missions", "R42: events route does not reach rewards")
	for tab in ["missions", "collection", "store"]:
		shell._open_tab(tab)
		await get_tree().process_frame
		for node in shell._screen.get_children():
			if node is VBoxContainer:
				_check(node.get_combined_minimum_size().x <= shell.size.x - Ui.SAFE_MARGIN * 2, "R42: " + tab + " content forces horizontal overflow")
	shell.queue_free()
	await get_tree().process_frame

func _check_reference_home(instance: Node) -> void:
	var home: RefCounted = instance._home_view
	home.layout()
	_check(instance._reels.size() == 3, "R42: exactly three animated drums")
	_check(home.village_art.size() == 5, "R42: five village structures")
	_check(instance._event_label.text != "", "R42: event label missing")
	for kind in ["raid", "shield", "chest", "card"]:
		var expected: String = {"raid": "vault", "shield": "shield", "chest": "chest", "card": "card"}[kind]
		_check(SpinVisuals.symbols_for_result({"type": kind}) == [expected, expected, expected], "R42: incorrect symbol for " + kind)
	for control in [instance._spin_btn, instance._multiplier_btn, home.village, instance._credits_value, instance._spins_value]:
		var rect: Rect2 = control.get_global_rect()
		var area: Vector2 = instance.get_viewport_rect().size
		_check(rect.position.x >= -1 and rect.end.x <= area.x + 1, "R42: control outside horizontal viewport")
		_check(rect.position.y >= 0 and rect.end.y <= area.y - Ui.NAV_HEIGHT + 1, "R42: control overlaps navigation")
	var selected: int = instance._selected_multiplier
	instance._selected_multiplier = 100000
	instance._normalize_multiplier()
	_check(instance._selected_multiplier == 1, "R42: unaffordable bet must fall back to one")
	var affordable: Array = instance._affordable_multipliers()
	for step in affordable.size():
		instance._cycle_multiplier()
		_check(affordable.has(instance._selected_multiplier), "R42: unaffordable value in bet cycle")
	_check(instance._selected_multiplier == 1, "R42: bet cycle must wrap")
	instance._selected_multiplier = selected
	instance._normalize_multiplier()
	for reel in instance._reels:
		reel.start_spin()
		reel.land("credits")
		_check(not reel.spinning and reel.final_symbol == "credits", "R42: reel landing mismatch")
	var original_events: Variant = Store.state.get("events", [])
	Store.state["events"] = [{"name": "Expired", "endsAtMs": Store.now_ms() - 1}]
	home.update_event()
	_check(instance._event_label.text == "EVENTS", "R42: expired event advertised as active")
	Store.state["events"] = original_events
	home.update_event()

func _check_horizontal_bounds(instance: Node) -> void:
	var viewport_width: float = instance.get_viewport_rect().size.x
	for child in instance.find_children("*", "Control", true, false):
		if not child.is_in_group("horizontal_bounds_check") or not child.is_visible_in_tree():
			continue
		var rect: Rect2 = child.get_global_rect()
		_check(
			rect.position.x >= -1.0 and rect.end.x <= viewport_width + 1.0,
			"contrôle hors viewport (%s): %.1f..%.1f / %.1f" % [child.name, rect.position.x, rect.end.x, viewport_width]
		)

## Les sets existent sous deux formes de récompense et peuvent être verrouillés.
## Sans cette couverture, un set en completionReward afficherait « +0 SPINS »
## sans que rien ne le signale.
func _check_collection_screen(instance: Node) -> void:
	var sets := Config.sets()
	if not _check(not sets.is_empty(), "aucun set dans la config"):
		return
	var saw_legacy := false
	var saw_object := false
	var saw_lock := false
	for set_data in sets:
		if typeof(set_data) != TYPE_DICTIONARY:
			continue
		var reward: Dictionary = instance._set_reward(set_data)
		_check(
			int(reward.get("spins", 0)) > 0 or int(reward.get("credits", 0)) > 0,
			"récompense de set nulle: " + str(set_data.get("setId", ""))
		)
		_check(
			instance._reward_label(reward).contains("CLAIM"),
			"libellé de récompense vide: " + str(set_data.get("setId", ""))
		)
		if set_data.has("completionReward"):
			saw_object = true
		else:
			saw_legacy = true
		if instance._set_lock_reason(set_data) != "":
			saw_lock = true
		# Un thème inconnu doit rester lisible plutôt que transparent.
		var color: Color = instance._theme_color(str(set_data.get("visualTheme", "")))
		_check(color.a > 0.0, "thème de set sans couleur")
	_check(saw_object, "aucun set en completionReward")
	_check(saw_legacy, "aucun set en completionSpins, compatibilité non couverte")
	_check(saw_lock, "aucun set verrouillé, prérequis non couvert")

	var chests := Config.chests()
	_check(chests.size() == 4, "quatre paliers de coffres attendus")
	for chest in chests:
		if typeof(chest) != TYPE_DICTIONARY:
			continue
		var art := str(chest.get("image", ""))
		_check(
			art != "" and ResourceLoader.exists(art),
			"art de coffre introuvable: " + art
		)

## L'écran de district doit vraiment consommer la config : un `background` mal
## orthographié tomberait sinon sur le repli sans que rien ne le signale.
func _check_district_screen(instance: Node) -> void:
	var districts := Config.districts()
	if not _check(districts.size() >= 2, "au moins deux districts attendus dans la config"):
		return
	for district in districts:
		var background := str(district.get("background", ""))
		_check(
			instance._asset_texture(background) != null,
			"Fond de district introuvable: " + background
		)

	# Changer de district doit changer le décor ET le bandeau nom.
	var last: Dictionary = districts[districts.size() - 1]
	var expected: Texture2D = instance._asset_texture(str(last.get("background", "")))
	instance._district = last
	instance._apply_background()
	instance._rebuild_hero()
	await get_tree().process_frame
	_check(instance._background.texture == expected, "Le décor ne suit pas le district actif")
	_check(instance._hero_holder.get_child_count() == 1, "Bandeau village non reconstruit")
	_check(instance.has_method("_open_build_bay"), "BUILD BAY absent")

	# Tout asset déclaré (les 5 districts) doit réellement charger.
	for district in districts:
		if typeof(district) != TYPE_DICTIONARY:
			continue
		for element in district.get("elements", []):
			if typeof(element) != TYPE_DICTIONARY:
				continue
			for level in element.get("levels", []):
				if typeof(level) != TYPE_DICTIONARY:
					continue
				var asset := str(level.get("asset", ""))
				if asset.is_empty():
					continue
				_check(
					instance._asset_texture(asset) != null,
					"Art de structure introuvable: " + asset
				)

	# Les silhouettes procédurales doivent couvrir n'importe quel identifiant
	# d'élément, pas seulement les cinq premiers. On passe par le rendu réel
	# plutôt que par la classe, pour couvrir le chemin que le joueur emprunte.
	var probe := {
		"id": districts.size() + 1,
		"name": "Overflow Probe",
		"background": str(last.get("background", "")),
		"elements": [],
	}
	for element_id in range(6, 13):
		probe["elements"].append({
			"id": element_id,
			"name": "Probe %d" % element_id,
			"levels": [{"level": 0, "cost": 0}, {"level": 1, "cost": 1000}],
		})
	var restore_districts: Array = districts.duplicate()
	var restore_index: int = int(Store.state.get("districtIndex", 0))
	Config.raw["districts"] = restore_districts + [probe]
	Store.state["districtIndex"] = districts.size()
	instance._refresh()
	await get_tree().process_frame
	_check(
		instance._list.get_child_count() == probe["elements"].size(),
		"Éléments au-delà de cinq non rendus"
	)
	Config.raw["districts"] = restore_districts
	Store.state["districtIndex"] = restore_index
	instance._refresh()
	await get_tree().process_frame
	await _check_map_interactions(instance)

func _check_map_interactions(instance: Node) -> void:
	var view: RefCounted = instance._map_view
	var original: Dictionary = Store.state.duplicate(true)
	var elements: Array = instance._district.get("elements", [])
	_check(view.cards.size() == elements.size(), "R43: MAP structure count")
	var before_credits := Store.credits()
	var before_progress: Array = Store.state.get("districtProgress", []).duplicate(true)
	var target: Control = view.cards[1].get_child(0)
	target.pressed.emit()
	await get_tree().process_frame
	_check(instance._armed_element == int(elements[1].id), "R43: selected building not updated")
	_check(Store.credits() == before_credits and Store.state.get("districtProgress", []) == before_progress, "R43: selecting a building must not buy it")
	var q: Dictionary = view.quote(view.selected)
	_check(int(q.cost) == int(elements[1].levels[1].cost), "R43: next level quote differs from config")
	Store.state["credits"] = 0
	instance._refresh()
	_check(view.action.disabled, "R43: unaffordable upgrade enabled")
	_check(view.feedback.text.begins_with("NEED "), "R43: insufficient credit hint missing")
	var district_id := int(instance._district.id)
	var element_id := int(elements[1].id)
	Store.state["credits"] = before_credits
	Store.state["districtProgress"] = [{"districtId": district_id, "elementId": element_id, "level": 5}]
	instance._refresh()
	_check(view.action.disabled and view.action.text == "MAX LEVEL", "R43: maximum level still purchasable")
	Store.state["districtDamage"] = [{"districtId": district_id, "elementId": element_id}]
	instance._refresh()
	q = view.quote(view.selected)
	var expected_repair: int = int(elements[1].levels[5].cost) * int(Config.social().get("attack", {}).get("repairCostBps", 2500)) / 10000
	_check(q.damaged and not q.maxed and int(q.cost) == expected_repair, "R43: damaged maximum level repair quote")
	_check(view.action.text.begins_with("REPAIR"), "R43: repair action missing")
	instance._busy = true
	instance._refresh()
	_check(view.action.disabled and view.bay.disabled, "R43: duplicate action allowed while request pending")
	instance._busy = false
	Store.state = original
	instance._refresh()
	for control in [view.action, view.bay, view.route, view.detail, view.stage]:
		var rect: Rect2 = control.get_global_rect()
		_check(rect.position.x >= 0 and rect.end.x <= instance.size.x + 1, "R43: MAP horizontal overflow")
		_check(rect.position.y >= 0 and rect.end.y <= instance.size.y - Ui.NAV_HEIGHT + 1, "R43: MAP overlaps bottom navigation")
	view.open_bay()
	await get_tree().process_frame
	_check(is_instance_valid(view._modal) and view._modal.is_in_group("dismiss_on_back"), "R43: Build Bay Android back support")
	for node in view._modal.find_children("*", "Button", true, false):
		_check(node.size.x <= instance.size.x - 28, "R43: Build Bay action overflow")
	view.open_route()
	await get_tree().process_frame
	_check(view._modal.find_children("*", "ScrollContainer", true, false).size() == 1, "R43: district route must scroll")
	view._modal.queue_free()
	await get_tree().process_frame

func _check_building_art() -> void:
	var paths: Dictionary = {}
	for district in Config.districts():
		for element in district.get("elements", []):
			var unique: Dictionary = {}
			for level in element.get("levels", []):
				var asset := str(level.get("asset", ""))
				unique[asset] = true
				paths[asset] = true
			_check(unique.size() == 3, "R44: each building needs three illustrated evolutions")
	_check(paths.size() == 75, "R44: 75 distinct building sprites expected")
	for asset in paths:
		var texture := load("res://assets/generated/" + str(asset) + ".webp") as Texture2D
		if not _check(texture != null, "R44: building texture missing"):
			continue
		_check(texture.get_size() == Vector2(320, 360), "R44: inconsistent building canvas")
		var bitmap := texture.get_image()
		if bitmap.is_compressed():
			bitmap.decompress()
		_check(bitmap.detect_alpha() != Image.ALPHA_NONE, "R44: opaque building background")
		for corner in [Vector2i(0, 0), Vector2i(319, 0), Vector2i(0, 359), Vector2i(319, 359)]:
			_check(bitmap.get_pixelv(corner).a == 0, "R44: nontransparent sprite corner")
