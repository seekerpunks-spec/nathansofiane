extends Node
## Smoke test sans réseau : instancie chaque scène avec un état représentatif.

const SCENES := [
	"res://scenes/screens/OnboardingScreen.tscn",
	"res://scenes/screens/SpinScreen.tscn",
	"res://scenes/screens/DistrictScreen.tscn",
	"res://scenes/screens/CollectionScreen.tscn",
	"res://scenes/screens/MissionsScreen.tscn",
	"res://scenes/screens/StoreScreen.tscn",
]

func _ready() -> void:
	call_deferred("_run")

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
	Store.apply_state({
		"spins": 12, "credits": 8500000, "serverTimeMs": int(Time.get_unix_time_from_system() * 1000),
		"nextSpinAtMs": int(Time.get_unix_time_from_system() * 1000) + 180000,
		"districtProgress": [{"districtId":1,"elementId":1,"level":2}],
		"cards": [{"cardId":"ghost_terminal","qty":2}], "chests": [{"chestId":"basic","qty":1}],
		"completedSets": [], "dailyStreak": 2, "dailyAvailable": true, "adsWatchedToday": 1,
		"missions": [{"missionId":"use_spins","name":"Use 10 Spins","target":10,"progress":6,"claimed":false,"reward":{"spins":20}}],
		"achievements": [{"achievementId":"signal_runner_1","name":"Signal Runner I","description":"Dépense 10 spins.","target":10,"progress":10,"claimed":false,"reward":{"spins":25,"credits":100000}}],
		"entitlements": {"dailySpinBonus":0,"items":[],"verificationMode":"server_provider_required"},
		"rewardPool": {"enabled":false,"settlementEnabled":false,"pools":[]},
		"events": [{"eventId":"neon_rush_r17","name":"Neon Rush","endsAtMs":Store.now_ms()+86400000,"points":420}],
		"seasons": [{"seasonId":"neon_genesis","name":"Neon Genesis","points":600,"premium":false,"freeClaimed":[]}],
	})
	for path in SCENES:
		var packed: PackedScene = load(path)
		assert(packed != null, "Scène introuvable: " + path)
		var instance := packed.instantiate()
		if instance.get_script() == null:
			push_error("Script non chargé: " + path)
			get_tree().quit(1)
			return
		add_child(instance)
		await get_tree().process_frame
		if path.ends_with("DistrictScreen.tscn"):
			await _check_district_screen(instance)
		if path.ends_with("SpinScreen.tscn"):
			instance._render_network()
			await get_tree().process_frame
			assert(is_instance_valid(instance._social_overlay), "Modale Seeker Network absente")
			instance._clear_social_overlay()
			instance._show_social_encounter({"kind":"attack","encounterId":"smoke-attack","target":"Runner","choices":[1,2],"multiplier":4})
			await get_tree().process_frame
			assert(is_instance_valid(instance._social_overlay), "Modale Attack absente")
			instance._show_social_encounter({"kind":"raid","encounterId":"smoke-raid","target":"Vault","nodeCount":6,"picked":[0],"unbankedCredits":1000,"canCashout":true})
			await get_tree().process_frame
			assert(is_instance_valid(instance._social_overlay), "Modale Raid absente")
			instance._show_social_result("SMOKE RESULT", false)
			instance._clear_social_overlay()
		instance.queue_free()
		await get_tree().process_frame
	print("SMOKE_SCENES_OK: ", SCENES.size())
	get_tree().quit(0)

## L'écran de district doit vraiment consommer la config : un `background` mal
## orthographié tomberait sinon sur le repli sans que rien ne le signale.
func _check_district_screen(instance: Node) -> void:
	var districts := Config.districts()
	assert(districts.size() >= 2, "au moins deux districts attendus dans la config")
	for district in districts:
		var background := str(district.get("background", ""))
		assert(
			instance._asset_texture(background) != null,
			"Fond de district introuvable: " + background
		)

	# Changer de district doit changer le décor ET la carte héros.
	var last: Dictionary = districts[districts.size() - 1]
	var expected: Texture2D = instance._asset_texture(str(last.get("background", "")))
	instance._district = last
	instance._apply_background()
	instance._rebuild_hero()
	await get_tree().process_frame
	assert(instance._background.texture == expected, "Le décor ne suit pas le district actif")
	assert(instance._hero_holder.get_child_count() == 1, "Carte héros non reconstruite")

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
	assert(
		instance._list.get_child_count() == probe["elements"].size(),
		"Éléments au-delà de cinq non rendus"
	)
	Config.raw["districts"] = restore_districts
	Store.state["districtIndex"] = restore_index
