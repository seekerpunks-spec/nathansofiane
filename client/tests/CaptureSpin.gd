extends Node
## Capture visuelle déterministe du slot, utile pour la QA hors appareil.


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
	Store.apply_state({
		"spins": 47,
		"credits": 8500000,
		"serverTimeMs": int(Time.get_unix_time_from_system() * 1000),
		"nextSpinAtMs": int(Time.get_unix_time_from_system() * 1000) + 180000,
		"districtProgress": [{"districtId": 1, "elementId": 1, "level": 2}],
		"cards": [],
		"chests": [],
		"completedSets": [],
		"dailyStreak": 2,
		"dailyAvailable": true,
		"adsWatchedToday": 1,
		"missions": [],
		"events": [],
		"seasons": [],
	})

	var slot := preload("res://scenes/screens/SpinScreen.tscn").instantiate()
	add_child(slot)
	for frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../captures/slot_runtime.png")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("CAPTURE_SPIN_OK: ", output, " error=", error)
	get_tree().quit(0 if error == OK else 1)
