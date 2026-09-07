extends Node
## Captures déterministes des cinq écrans secondaires pour la QA visuelle.

const SCREENS := {
	"onboarding": "res://scenes/screens/OnboardingScreen.tscn",
	"district": "res://scenes/screens/DistrictScreen.tscn",
	"collection": "res://scenes/screens/CollectionScreen.tscn",
	"missions": "res://scenes/screens/MissionsScreen.tscn",
	"store": "res://scenes/screens/StoreScreen.tscn",
}


func _json(relative: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://../config/" + relative)
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else {}


func _ready() -> void:
	Config.raw = {
		"economy": _json("economy.json"),
		"spinTable": _json("spin_table.json"),
		"daily": _json("daily.json"),
		"districts": [_json("districts/district_01.json")],
		"cards": _json("cards.json").get("items", []),
		"sets": _json("sets.json").get("items", []),
		"chests": _json("chests.json").get("items", []),
		"events": _json("events.json").get("items", []),
		"offers": _json("offers.json").get("items", []),
		"seasons": _json("seasons.json").get("items", []),
	}
	Config._index_outcomes()
	var season: Dictionary = Config.seasons()[0].duplicate(true)
	season["points"] = 600
	season["premium"] = false
	season["freeClaimed"] = []
	season["paidClaimed"] = []
	Store.apply_state({
		"spins": 47, "credits": 8500000,
		"serverTimeMs": int(Time.get_unix_time_from_system() * 1000),
		"nextSpinAtMs": int(Time.get_unix_time_from_system() * 1000) + 180000,
		"districtProgress": [
			{"districtId": 1, "elementId": 1, "level": 2},
			{"districtId": 1, "elementId": 2, "level": 1},
		],
		"cards": [{"cardId": "ghost_terminal", "qty": 2}],
		"chests": [{"chestId": "basic", "qty": 1}],
		"completedSets": [], "dailyStreak": 4, "dailyAvailable": true,
		"adsWatchedToday": 1,
		"missions": [{"missionId": "use_spins", "name": "Use 10 Spins", "target": 10, "progress": 6, "claimed": false, "reward": {"spins": 20}}],
		"events": [{"eventId": "neon_rush_r17", "name": "Neon Rush", "endsAtMs": Store.now_ms() + 86400000, "points": 420}],
		"seasons": [season],
	})
	call_deferred("_capture_all")


func _capture_all() -> void:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	var bg := ColorRect.new()
	bg.color = Ui.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)
	var ambiance := Ui.SignalBackdrop.new()
	ambiance.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(ambiance)
	for key in SCREENS:
		var screen: Control = load(SCREENS[key]).instantiate()
		screen.set_meta("qa_skip_sync", true)
		if key == "store" and not Config.offers().is_empty():
			screen.set_meta("qa_offers", [Config.offers()[0]])
		stage.add_child(screen)
		for frame in 10:
			await get_tree().process_frame
		RenderingServer.force_draw()
		var output := ProjectSettings.globalize_path("res://../captures/" + key + "_runtime.png")
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var error := get_viewport().get_texture().get_image().save_png(output)
		print("CAPTURE_SCREEN_OK: ", key, " output=", output, " error=", error)
		screen.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
