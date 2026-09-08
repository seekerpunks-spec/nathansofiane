extends Node
## Capture le vrai shell Main, y compris sa navigation inférieure.


func _json(relative: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://../config/" + relative)
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else {}


func _ready() -> void:
	Config.raw = {
		"economy": _json("economy.json"), "spinTable": _json("spin_table.json"),
		"daily": _json("daily.json"), "districts": [_json("districts/district_01.json")],
		"cards": _json("cards.json").get("items", []), "sets": _json("sets.json").get("items", []),
		"chests": _json("chests.json").get("items", []), "events": _json("events.json").get("items", []),
		"offers": _json("offers.json").get("items", []), "seasons": _json("seasons.json").get("items", []),
	}
	var district_files := DirAccess.get_files_at(ProjectSettings.globalize_path("res://../config/districts"))
	district_files.sort()
	var districts: Array = []
	for file_name in district_files:
		if file_name.ends_with(".json"):
			districts.append(_json("districts/" + file_name))
	Config.raw["districts"] = districts
	Config._index_outcomes()
	Store.apply_state({
		"spins": 47, "credits": 8500000,
		"serverTimeMs": int(Time.get_unix_time_from_system() * 1000),
		"nextSpinAtMs": int(Time.get_unix_time_from_system() * 1000) + 180000,
		"districtProgress": [{"districtId": 1, "elementId": 1, "level": 2}],
		"cards": [{"cardId": "ghost_terminal", "qty": 2}],
		"chests": [{"chestId": "basic", "qty": 1}], "completedSets": [],
		"dailyStreak": 4, "dailyAvailable": true, "adsWatchedToday": 1,
		"missions": [{"missionId": "use_spins", "name": "Use 10 Spins", "target": 10, "progress": 6, "claimed": false, "reward": {"spins": 20}}],
		"events": [{"eventId": "neon_rush_r17", "name": "Neon Rush", "endsAtMs": Store.now_ms() + 86400000, "points": 420}],
		"seasons": [{"seasonId": "neon_genesis", "name": "Neon Genesis", "points": 600, "premium": false, "freeClaimed": []}],
	})
	var capture_district := 1
	var capture_level := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--district="):
			capture_district = clampi(int(arg.substr(11)), 1, districts.size())
		elif arg.begins_with("--level="):
			capture_level = clampi(int(arg.substr(8)), 0, 5)
	Store.state["districtIndex"] = capture_district - 1
	if capture_level >= 0:
		var progress: Array = []
		for element in districts[capture_district - 1].get("elements", []):
			progress.append({"districtId": capture_district, "elementId": element.id, "level": capture_level})
		Store.state["districtProgress"] = progress
	var shell := preload("res://scenes/Main.tscn").instantiate()
	shell.qa_bypass_boot = true
	add_child(shell)
	var tab := "spin"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tab=") and shell.SCREENS.has(arg.substr(6)):
			tab = arg.substr(6)
	shell._enter_game(tab)
	if tab == "collection":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--collection-set="):
				shell._screen._select_set(clampi(int(arg.substr(17)), 0, Config.sets().size() - 1))
			elif arg == "--collection-modal=card":
				shell._screen._show_card(Config.cards()[0])
			elif arg == "--collection-modal=drops":
				shell._screen._show_drops([{"cardId": "ghost_terminal", "duplicate": true}, {"cardId": "data_spike", "duplicate": false}])
			elif arg == "--collection-chests":
				shell._screen._switch_mode(true)
	if tab == "district":
		for arg in OS.get_cmdline_user_args():
			if arg == "--map-modal=bay":
				shell._screen._open_build_bay()
			elif arg == "--map-modal=route":
				shell._screen._map_view.open_route()
			elif arg == "--map-modal=complete":
				shell._screen._map_view.complete({"spins": 500, "credits": 2000000, "chest": "neon"}, false)
	# Avoid unrelated tooltips from the desktop pointer in deterministic captures.
	Input.warp_mouse(Vector2(-1000, -1000))
	await get_tree().create_timer(0.65).timeout
	for node in shell._screen.find_children("*", "Control", true, false):
		var rect: Rect2 = node.get_global_rect()
		if rect.end.x > get_viewport().get_visible_rect().size.x + 2:
			print("CAPTURE_BOUNDS: ", node.get_path(), " rect=", rect, " min=", node.get_combined_minimum_size())
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../captures/shell_runtime.png")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("CAPTURE_SHELL_OK: ", output, " error=", error)
	get_tree().quit(0 if error == OK else 1)
