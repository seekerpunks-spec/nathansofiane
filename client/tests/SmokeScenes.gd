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
		"districts": [_json("districts/district_01.json")],
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
