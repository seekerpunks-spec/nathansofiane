extends RefCounted
## R42: reference composition. This view reads state, never awards currency.
const Neon := preload("res://scripts/components/NeonSkin.gd")
const Visuals := preload("res://scripts/components/SpinVisuals.gd")
var host: Control
var root: Control
var machine: Control
var left_rail: Control
var right_rail: Control
var village: Control
var shield_value: Label
var power_value: Label
var score_value: Label
var chest_value: Label
var card_value: Label
var daily_value: Label
var village_value: Label
var village_progress: Label
var village_title: Label
var village_bar: ProgressBar
var village_art: Array[TextureRect] = []
var village_levels: Array[Label] = []
var village_buttons: Array[Button] = []
var district_id := -1

func _init(owner: Control) -> void:
	host = owner

func build() -> void:
	var bg := Neon.art(host, Neon.CITY, Rect2(0, 0, 540, 1170))
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root = Control.new()
	root.name = "PunkCityHome"
	host.add_child(root)
	_build_header()
	_build_hero()
	_build_machine()
	_build_rails()
	_build_village()
	host.resized.connect(layout)
	layout.call_deferred()

func layout() -> void:
	var safe := Ui.safe_insets()
	var available := Vector2(maxf(1, host.size.x - safe.x - safe.z), maxf(1, host.size.y - Ui.NAV_HEIGHT - safe.y - safe.w))
	var factor := minf(available.x / 1024.0, available.y / 1490.0)
	var logical_height := available.y / factor
	root.position = Vector2(safe.x + (available.x - 1024 * factor) / 2, safe.y)
	root.scale = Vector2.ONE * factor
	root.size = Vector2(1024, logical_height)
	var extra := maxf(0, logical_height - 1490)
	machine.position.y = 332 + extra * 0.10
	machine.size.y = 880 + extra * 0.74
	left_rail.position.y = 380 + extra * 0.10
	right_rail.position.y = 408 + extra * 0.10
	village.position.y = logical_height - 272

func _go(tab: String) -> void:
	host.navigate_requested.emit(tab)

func _build_header() -> void:
	var menu := Neon.button(root, "☰", Rect2(18, 18, 74, 78))
	menu.add_theme_font_size_override("font_size", 43)
	menu.tooltip_text = "Network, friends and clan"
	menu.pressed.connect(host._open_network)
	Neon.frame(root, Rect2(106, 18, 354, 78))
	Neon.art(root, Neon.icon(0), Rect2(111, 16, 79, 80))
	host._credits_value = Neon.text(root, "0", Rect2(188, 22, 206, 68), 33)
	_plus(Rect2(400, 31, 48, 51), "store")
	Neon.frame(root, Rect2(475, 18, 235, 78), Ui.NEON_MAGENTA)
	Neon.art(root, Neon.icon(10), Rect2(482, 22, 64, 66))
	power_value = Neon.text(root, "0", Rect2(548, 24, 150, 64), 30)
	power_value.tooltip_text = "Global progression score"
	Neon.frame(root, Rect2(725, 18, 282, 78))
	Neon.art(root, Neon.icon(4), Rect2(731, 20, 63, 69))
	host._spins_value = Neon.text(root, "0", Rect2(794, 24, 148, 64), 31, Ui.NEON_CYAN)
	_plus(Rect2(947, 31, 48, 51), "store")

func _plus(rect: Rect2, tab: String) -> void:
	var hit := Rect2(rect.position - Vector2(18, 16), rect.size + Vector2(36, 32))
	var button := Neon.button(root, "+", hit, Ui.GREEN, false)
	var plate := Neon.frame(button, Rect2(Vector2(18, 16), rect.size), Ui.GREEN)
	plate.show_behind_parent = true
	button.add_theme_font_size_override("font_size", 40)
	button.pressed.connect(_go.bind(tab))

func _build_hero() -> void:
	Neon.frame(root, Rect2(18, 131, 284, 212))
	var preview := Neon.art(root, Neon.CITY, Rect2(31, 144, 258, 176))
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.clip_contents = true
	village_value = Neon.text(root, "VILLAGE 1", Rect2(26, 142, 268, 37), 29)
	host._district_label = Neon.text(root, "", Rect2(25, 183, 270, 35), 22, Ui.NEON_CYAN)
	village_bar = Ui.progress_bar(Ui.NEON_CYAN, 24)
	village_bar.position = Vector2(38, 291)
	village_bar.size = Vector2(242, 30)
	root.add_child(village_bar)
	village_progress = Neon.text(root, "", Rect2(38, 289, 242, 33), 25)
	var visit := Neon.button(root, "", Rect2(18, 131, 284, 212), Ui.NEON_CYAN, false)
	visit.tooltip_text = "Build and upgrade your village"
	visit.pressed.connect(_go.bind("district"))
	var logo := Neon.art(root, Neon.LOGO, Rect2(310, 108, 391, 269))
	Juice.breathe(logo, 0.009, 1.4)
	Neon.frame(root, Rect2(709, 131, 298, 109))
	Neon.art(root, Neon.icon(1), Rect2(720, 139, 89, 91))
	Neon.text(root, "FIREWALL", Rect2(808, 147, 187, 36), 26, Ui.NEON_CYAN)
	shield_value = Neon.text(root, "0 / 3", Rect2(808, 187, 187, 32), 27)
	var event_button := Neon.button(root, "", Rect2(709, 256, 298, 125), Ui.NEON_MAGENTA)
	event_button.pressed.connect(_go.bind("missions"))
	Neon.art(event_button, Neon.icon(7), Rect2(7, 13, 84, 97))
	host._event_label = Neon.text(event_button, "EVENTS", Rect2(88, 19, 198, 35), 25, Ui.NEON_MAGENTA)
	host._event_timer = Neon.text(event_button, "", Rect2(88, 60, 198, 42), 21)

func _build_machine() -> void:
	machine = Control.new()
	machine.position = Vector2(201, 332)
	machine.size = Vector2(627, 930)
	root.add_child(machine)
	host._cabinet_root = machine
	host._cabinet = Visuals.SlotCabinet.new()
	host._cabinet.visible = false
	machine.add_child(host._cabinet)
	Neon.art(machine, Neon.CABINET, Rect2(0, 0, 627, 930), true)
	host._status_label = Neon.text(machine, "SPINS", Rect2(121, 73, 382, 42), 34)
	# Window coordinates measured against the generated 1024x1536 cabinet.
	for index in 3:
		var reel := Visuals.SlotReel.new()
		reel.atlas = Neon.ICONS
		reel.symbols = host.SYMBOLS
		reel.position = Vector2(116 + index * 128, 183)
		reel.size = Vector2(127, 403)
		reel.reel_index = index
		reel.final_symbol = ["hack", "credits", "vault"][index]
		reel.clip_contents = true
		machine.add_child(reel)
		host._reels.append(reel)
	Neon.frame(machine, Rect2(116, 129, 388, 34), Ui.NEON_MAGENTA)
	host._result_banner = Neon.text(machine, "MATCH 3 • WIN BIG", Rect2(120, 129, 380, 34), 21, Ui.NEON_CYAN)
	host._multiplier_btn = Neon.button(machine, "BET ×1", Rect2(190, 601, 234, 84), Ui.NEON_CYAN, false)
	host._multiplier_btn.add_theme_font_size_override("font_size", 30)
	host._multiplier_btn.pressed.connect(host._cycle_multiplier)
	host._spin_btn = Neon.button(machine, "SPIN", Rect2(154, 710, 309, 111), Ui.GOLD, false)
	host._spin_btn.add_theme_font_size_override("font_size", 69)
	host._spin_btn.add_theme_color_override("font_color", Color("#FFF6CE"))
	host._spin_btn.pressed.connect(host._on_spin_pressed)
	var lever := Neon.button(machine, "", Rect2(539, 253, 88, 142), Ui.NEON_MAGENTA, false)
	lever.tooltip_text = "Pull to spin"
	lever.pressed.connect(host._on_spin_pressed)
	Neon.text(machine, "TAP TO SPIN", Rect2(155, 795, 310, 30), 21, Color("#FFF4B5"))
	Neon.frame(machine, Rect2(72, 875, 483, 54), Ui.NEON_CYAN)
	host._regen_bar = Ui.progress_bar(Ui.NEON_CYAN, 12)
	host._regen_bar.custom_minimum_size.y = 7
	host._regen_bar.position = Vector2(94, 885)
	host._regen_bar.size = Vector2(430, 7)
	machine.add_child(host._regen_bar)
	host._regen_label = Neon.text(machine, "", Rect2(30, 898, 565, 27), 19, Ui.NEON_CYAN)
	# Stretch the cabinet and drum apertures on tall phones, not the glyphs/icons.
	for child in machine.get_children():
		if child is Control:
			var rect: Rect2 = child.get_rect()
			child.anchor_top = rect.position.y / 930.0
			child.anchor_bottom = rect.end.y / 930.0
			child.offset_top = 0
			child.offset_bottom = 0

func _tile(parent: Node, title: String, index: int, rect: Rect2, accent: Color, action: Callable) -> Label:
	var button := Neon.button(parent, "", rect, accent)
	button.tooltip_text = title
	button.pressed.connect(action)
	Neon.art(button, Neon.icon(index), Rect2(18, 12, rect.size.x - 36, rect.size.y - 70))
	Neon.text(button, title, Rect2(10, rect.size.y - 63, rect.size.x - 20, 31), 23)
	return Neon.text(button, "", Rect2(10, rect.size.y - 33, rect.size.x - 20, 25), 20, accent)

func _build_rails() -> void:
	left_rail = Control.new()
	left_rail.position = Vector2(18, 380)
	root.add_child(left_rail)
	_tile(left_rail, "SHOP", 6, Rect2(0, 0, 170, 164), Ui.NEON_CYAN, _go.bind("store"))
	card_value = _tile(left_rail, "CARDS", 7, Rect2(0, 180, 170, 181), Ui.NEON_MAGENTA, _go.bind("collection"))
	chest_value = _tile(left_rail, "CHESTS", 3, Rect2(0, 377, 170, 178), Ui.NEON_CYAN, _go.bind("collection"))
	daily_value = _tile(left_rail, "DAILY BONUS", 8, Rect2(0, 571, 170, 176), Ui.NEON_MAGENTA, _go.bind("missions"))
	right_rail = Control.new()
	right_rail.position = Vector2(836, 408)
	root.add_child(right_rail)
	_tile(right_rail, "REWARDS", 3, Rect2(0, 0, 171, 209), Ui.NEON_CYAN, _go.bind("missions"))
	_tile(right_rail, "SEASON", 11, Rect2(0, 226, 171, 193), Ui.GOLD, _go.bind("missions"))
	score_value = _tile(right_rail, "RANKING", 10, Rect2(0, 436, 171, 253), Ui.NEON_MAGENTA, host._open_network)

func _build_village() -> void:
	village = Control.new()
	village.position = Vector2(18, 1218)
	village.size = Vector2(989, 260)
	root.add_child(village)
	Neon.frame(village, Rect2(Vector2.ZERO, village.size))
	village_title = Neon.text(village, "BUILD YOUR CITY", Rect2(150, 6, 688, 41), 27, Ui.NEON_CYAN)
	for index in 5:
		var button := Neon.button(village, "", Rect2(16 + index * 193, 49, 184, 195), Ui.NEON_CYAN, false)
		button.tooltip_text = "Open village upgrades"
		button.pressed.connect(_go.bind("district"))
		village_buttons.append(button)
		village_art.append(Neon.art(button, null, Rect2(2, 0, 180, 150)))
		village_levels.append(Neon.text(button, "LV. 0", Rect2(0, 151, 112, 34), 23))
		var arrow := Neon.frame(button, Rect2(133, 149, 48, 42), Ui.GREEN)
		Neon.text(arrow, "↑", Rect2(0, -3, 48, 46), 35, Ui.GREEN)

func refresh() -> void:
	power_value.text = Ui.compact(int(Store.state.get("progression", {}).get("score", 0)))
	score_value.text = power_value.text + " PWR"
	shield_value.text = "%d / %d" % [int(Store.state.get("firewallCharges", 0)), int(Store.state.get("firewallMax", 3))]
	card_value.text = "%d FOUND" % Store.state.get("cards", []).size()
	var chests := 0
	for item in Store.state.get("chests", []):
		chests += int(item.get("qty", 0))
	chest_value.text = "%d READY" % chests
	daily_value.text = "CLAIM NOW" if bool(Store.state.get("dailyAvailable", false)) else "COLLECTED"
	var district: Dictionary = {}
	for candidate in Config.districts():
		district = candidate
		if int(candidate.get("id", 0)) > int(Store.state.get("districtIndex", 0)):
			break
	if district.is_empty():
		return
	district_id = int(district.get("id", 1))
	village_value.text = "VILLAGE %d" % district_id
	host._district_label.text = str(district.get("name", "")).to_upper()
	village_title.text = host._district_label.text
	if not host._busy and not host._revealed:
		host._status_label.text = "SPINS  %s" % Ui.compact(Store.spins())
	var total := 0
	var built := 0
	var elements: Array = district.get("elements", [])
	for index in 5:
		village_buttons[index].visible = index < elements.size()
		if index >= elements.size():
			continue
		var element: Dictionary = elements[index]
		var levels: Array = element.get("levels", [])
		var current := Store.district_level(district_id, int(element.get("id", 0)))
		built += current
		total += maxi(0, levels.size() - 1)
		village_levels[index].text = "LV. %d" % current
		if levels.is_empty():
			continue
		var name := str(levels[clampi(current, 0, levels.size() - 1)].get("asset", ""))
		# Only data-driven bundled textures, never executable remote resources.
		if not name.begins_with("districts/buildings/") or name.contains("..") or name.contains(":") or name.contains("\\"):
			continue
		var path := "res://assets/generated/" + name + ".webp"
		if ResourceLoader.exists(path):
			village_art[index].texture = load(path) as Texture2D
	village_bar.max_value = maxi(1, total)
	village_bar.value = built
	village_progress.text = "%d / %d" % [built, total]
	village_bar.tooltip_text = "%d / %d upgrades" % [built, total]

func update_event() -> void:
	var active: Dictionary = {}
	for item in Store.state.get("events", []):
		if int(item.get("endsAtMs", 0)) > Store.now_ms():
			active = item
			break
	host._event_label.text = str(active.get("name", "EVENTS")).to_upper()
	host._event_timer.text = "VIEW REWARDS" if active.is_empty() else Ui.mmss_long(int(active.get("endsAtMs", 0)) - Store.now_ms())
