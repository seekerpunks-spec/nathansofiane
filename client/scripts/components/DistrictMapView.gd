extends RefCounted
## R43 — responsive MAP presentation. Server mutations stay in DistrictScreen.
const Neon := preload("res://scripts/components/NeonSkin.gd")
var host: Control
var header: Control
var wallet: Control
var reward: Control
var stage: Control
var detail: Control
var bay: Button
var route: Button
var action: Button
var feedback: Label
var selected: Dictionary = {}
var cards: Array[Control] = []
var _modal: Control

func build(screen: Control) -> void:
	host = screen
	var city := Neon.art(host, Neon.CITY, Rect2(0, 0, 540, 1170))
	city.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	city.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	city.modulate = Color(0.4, 0.4, 0.58)
	header = Control.new()
	host.add_child(header)
	wallet = Control.new()
	host.add_child(wallet)
	reward = Control.new()
	host.add_child(reward)
	stage = Control.new()
	stage.clip_contents = true
	host.add_child(stage)
	host._background.reparent(stage)
	detail = Control.new()
	host.add_child(detail)
	host._hero_holder = VBoxContainer.new()
	header.add_child(host._hero_holder)
	host._list = Control.new()
	stage.add_child(host._list)
	host.resized.connect(layout)
	rebuild_header()
	layout()

func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func rebuild_header() -> void:
	if not is_instance_valid(host._hero_holder):
		return
	clear(host._hero_holder)
	var title := Neon.header("VILLAGE %02d  /  CITY MAP" % int(host._district.get("id", 1)),
		str(host._district.get("name", "DISTRICT")).to_upper(), 9)
	title.custom_minimum_size.y = 90
	host._hero_holder.add_child(title)

func layout() -> void:
	if not is_instance_valid(host) or not is_instance_valid(stage):
		return
	var safe := Ui.safe_insets()
	var width := maxf(300, host.size.x - safe.x - safe.z - 24)
	var top := safe.y + 10
	var bottom := host.size.y - safe.w - Ui.NAV_HEIGHT - 10
	header.position = Vector2(12 + safe.x, top)
	header.size = Vector2(width, 90)
	host._hero_holder.size = header.size
	wallet.position = Vector2(12 + safe.x, top + 98)
	wallet.size = Vector2(width, 50)
	reward.position = Vector2(12 + safe.x, top + 156)
	reward.size = Vector2(width, 82)
	detail.position = Vector2(12 + safe.x, bottom - 178)
	detail.size = Vector2(width, 178)
	stage.position = Vector2(12 + safe.x, top + 248)
	stage.size = Vector2(width, maxf(180, detail.position.y - stage.position.y - 10))
	host._background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host._background.modulate = Color(0.48, 0.55, 0.72)
	host._list.position = Vector2(8, 38)
	host._list.size = stage.size - Vector2(16, 66)
	render_wallet()
	render_reward()
	render_stage()
	render_detail()

func refresh() -> void:
	selected = {}
	for element in host._district.get("elements", []):
		if typeof(element) == TYPE_DICTIONARY and int(element.get("id", 0)) == host._armed_element:
			selected = element
	if selected.is_empty():
		for element in host._district.get("elements", []):
			if typeof(element) == TYPE_DICTIONARY:
				selected = element
				host._armed_element = int(element.get("id", 0))
				break
	layout()

func render_wallet() -> void:
	clear(wallet)
	Neon.frame(wallet, Rect2(Vector2.ZERO, Vector2(wallet.size.x * 0.54, 50)), Ui.GOLD)
	Neon.art(wallet, Neon.icon(0), Rect2(8, 4, 42, 42))
	host._credits = Neon.text(wallet, Ui.compact(Store.credits()) + " CR", Rect2(54, 4, wallet.size.x * 0.54 - 64, 42), 24)
	var x := wallet.size.x * 0.56
	route = Neon.button(wallet, "DISTRICTS", Rect2(x, 0, wallet.size.x - x, 50))
	route.add_theme_font_size_override("font_size", 20)
	route.pressed.connect(open_route)

func render_reward() -> void:
	clear(reward)
	Neon.frame(reward, Rect2(Vector2.ZERO, reward.size), Ui.NEON_CYAN)
	var earned := 0
	var total := 0
	for element in host._district.get("elements", []):
		if typeof(element) != TYPE_DICTIONARY:
			continue
		var maximum := maxi(0, element.get("levels", []).size() - 1)
		total += maximum
		earned += mini(maximum, Store.district_level(int(host._district.get("id", 1)), int(element.get("id", 0))))
	host._progress_label = Neon.text(reward, "VILLAGE PROGRESS   %d / %d" % [earned, total], Rect2(16, 7, reward.size.x - 86, 22), 18)
	host._progress = Ui.progress_bar(Ui.NEON_CYAN, 12)
	reward.add_child(host._progress)
	host._progress.position = Vector2(16, 34)
	host._progress.size = Vector2(reward.size.x - 96, 12)
	host._progress.value = 100.0 if total == 0 else 100.0 * earned / total
	var copy := Ui.reward_text(host._district.get("completionReward", {}))
	Neon.text(reward, "COMPLETE: " + copy, Rect2(16, 50, reward.size.x - 85, 25), 14, Ui.GOLD)
	Neon.art(reward, Neon.icon(3), Rect2(reward.size.x - 77, 8, 67, 66))

func render_stage() -> void:
	for child in stage.get_children():
		if child != host._background and child != host._list:
			stage.remove_child(child)
			child.queue_free()
	var rim := Neon.frame(stage, Rect2(Vector2.ZERO, stage.size))
	rim.fill = Color(0.01, 0.025, 0.09, 0.2)
	rim.queue_redraw()
	stage.move_child(rim, 1)
	Neon.text(stage, "BUILD YOUR CITY", Rect2(14, 5, stage.size.x - 28, 30), 20, Ui.NEON_CYAN)
	Neon.text(stage, "SELECT A STRUCTURE TO UPGRADE", Rect2(12, stage.size.y - 27, stage.size.x - 24, 23), 13, Ui.TEXT_DIM)
	clear(host._list)
	cards.clear()
	var elements: Array = host._district.get("elements", [])
	var count := elements.size()
	for i in count:
		if typeof(elements[i]) != TYPE_DICTIONARY:
			continue
		var element: Dictionary = elements[i]
		var cell := Control.new()
		cell.set_meta("element_id", int(element.get("id", 0)))
		host._list.add_child(cell)
		cards.append(cell)
		var area: Vector2 = host._list.size
		var rows := 3 if count <= 5 else ceili(count / 2.0)
		var cell_height := area.y / maxi(1, rows)
		var cell_width := minf(area.x * 0.47, cell_height * 1.2)
		var column := float(i % 2)
		var row := int(i / 2.0)
		if count == 5:
			row = 0 if i < 2 else (1 if i == 2 else 2)
			column = 0.5 if i == 2 else float(i % 2) if i < 2 else float((i - 3) % 2)
		cell.position = Vector2(lerpf(0.03 * area.x, area.x * 0.97 - cell_width, column), row * cell_height)
		cell.size = Vector2(cell_width, cell_height - 3)
		render_card(cell, element)

func render_card(cell: Control, element: Dictionary) -> void:
	var id := int(element.get("id", 0))
	var current := Store.district_level(int(host._district.get("id", 1)), id)
	var maximum := maxi(0, element.get("levels", []).size() - 1)
	var damaged := Store.district_damaged(int(host._district.get("id", 1)), id)
	var active: bool = host._armed_element == id
	var accent := Ui.NEON_MAGENTA if active or damaged else Ui.NEON_CYAN
	var button := Neon.button(cell, "", Rect2(Vector2.ZERO, cell.size), accent, false)
	button.tooltip_text = str(element.get("name", "")) + " • LEVEL %d / %d" % [current, maximum]
	var art: Control = host._element_visual(element, current)
	art.custom_minimum_size = Vector2.ZERO
	art.position = Vector2(0, -3)
	art.size = Vector2(cell.size.x, maxf(28, cell.size.y - 37))
	button.add_child(art)
	if damaged:
		art.modulate = Color(1, 0.55, 0.7)
	var plate := Neon.frame(button, Rect2(0, cell.size.y - 40, cell.size.x, 39), accent)
	plate.fill = Color("#24082F") if active else Color("#041326")
	Neon.text(button, str(element.get("name", "STRUCTURE")).to_upper(), Rect2(7, cell.size.y - 39, cell.size.x - 14, 19), 14)
	var status := "REPAIR" if damaged else ("MAX" if current >= maximum else "LV. %d / %d" % [current, maximum])
	Neon.text(button, status, Rect2(7, cell.size.y - 22, cell.size.x - 14, 19), 13, Ui.NEON_MAGENTA if damaged else Ui.GOLD)
	button.pressed.connect(func() -> void:
		if host._busy:
			return
		host._armed_element = id
		host._map_message = ""
		Sfx.click()
		refresh()
		Juice.pop(detail, 1.015, 0.15)
	)

func quote(element: Dictionary) -> Dictionary:
	var id := int(element.get("id", 0))
	var current := Store.district_level(int(host._district.get("id", 1)), id)
	var levels: Array = element.get("levels", [])
	var maximum := maxi(0, levels.size() - 1)
	var damaged := Store.district_damaged(int(host._district.get("id", 1)), id)
	var cost := 0
	if damaged and current >= 0 and current < levels.size():
		cost = int(levels[current].get("cost", 0)) * int(Config.social().get("attack", {}).get("repairCostBps", 2500)) / 10000
	elif current + 1 < levels.size():
		cost = int(levels[current + 1].get("cost", 0))
	return {"id": id, "current": current, "maximum": maximum, "damaged": damaged, "cost": cost,
		"maxed": current >= maximum and not damaged, "affordable": Store.credits() >= cost}

func render_detail() -> void:
	clear(detail)
	Neon.frame(detail, Rect2(Vector2.ZERO, detail.size), Ui.NEON_MAGENTA)
	if selected.is_empty():
		Neon.text(detail, "NO STRUCTURES CONFIGURED", Rect2(16, 20, detail.size.x - 32, 40), 20)
		return
	var q := quote(selected)
	var width := detail.size.x
	var thumb: Control = host._element_visual(selected, int(q.current) if q.damaged else mini(int(q.current) + 1, int(q.maximum)))
	thumb.custom_minimum_size = Vector2.ZERO
	thumb.position = Vector2(8, 8)
	thumb.size = Vector2(92, 94)
	detail.add_child(thumb)
	Neon.text(detail, "REPAIR STRUCTURE" if q.damaged else ("STRUCTURE COMPLETE" if q.maxed else "NEXT UPGRADE"), Rect2(106, 9, width - 120, 19), 14, Ui.NEON_MAGENTA)
	Neon.text(detail, str(selected.get("name", "")).to_upper(), Rect2(106, 27, width - 120, 29), 24)
	var level_copy := "LEVEL %d / %d" % [q.current, q.maximum] if q.maxed or q.damaged else "LEVEL %d  >  %d" % [q.current, int(q.current) + 1]
	Neon.text(detail, level_copy, Rect2(106, 56, width - 120, 22), 17, Ui.GOLD)
	feedback = Neon.text(detail, "RESTORE TO ENABLE UPGRADES" if q.damaged else "UPGRADE ALL STRUCTURES TO UNLOCK THE NEXT VILLAGE", Rect2(12, 87, width - 24, 22), 12, Ui.TEXT_DIM)
	if not host._map_message.is_empty():
		feedback.text = host._map_message
		feedback.add_theme_color_override("font_color", Ui.GOLD)
	elif not q.affordable and not q.maxed:
		feedback.text = "NEED " + Ui.compact(int(q.cost) - Store.credits()) + " MORE CR"
	var caption := ("REPAIR" if q.damaged else "UPGRADE") + " • " + Ui.compact(int(q.cost)) + " CR"
	if q.maxed:
		caption = "MAX LEVEL"
	if host._busy:
		caption = "CONNECTING..."
	action = Neon.button(detail, caption, Rect2(12, 117, width * 0.68 - 14, 49), Ui.NEON_MAGENTA if q.damaged else Ui.GREEN)
	action.add_theme_font_size_override("font_size", 20)
	action.disabled = host._busy or q.maxed or not q.affordable
	action.pressed.connect(confirm_selected)
	bay = Neon.button(detail, "BUILD BAY", Rect2(width * 0.68 + 4, 117, width * 0.32 - 16, 49))
	bay.add_theme_font_size_override("font_size", 16)
	bay.disabled = host._busy
	bay.pressed.connect(host._open_build_bay)

func confirm_selected() -> void:
	if selected.is_empty() or host._busy:
		return
	var q := quote(selected)
	if q.maxed or not q.affordable:
		refresh()
		return
	host._map_message = ""
	if q.damaged:
		host._repair(int(q.id))
	else:
		host._upgrade(int(q.id))

func modal(title: String, accent: Color = Ui.NEON_CYAN, preferred_height: float = 0) -> VBoxContainer:
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = ColorRect.new()
	_modal.color = Color(0.005, 0.01, 0.04, 0.96)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_to_group("dismiss_on_back")
	host.add_child(_modal)
	var safe := Ui.safe_insets()
	var bounds := Rect2(safe.x + 14, safe.y + 20, host.size.x - safe.x - safe.z - 28, host.size.y - safe.y - safe.w - Ui.NAV_HEIGHT - 40)
	if preferred_height > 0 and bounds.size.y > preferred_height:
		bounds.position.y += (bounds.size.y - preferred_height) * 0.5
		bounds.size.y = preferred_height
	Neon.frame(_modal, bounds, accent)
	Neon.text(_modal, title, Rect2(bounds.position + Vector2(18, 14), Vector2(bounds.size.x - 36, 42)), 27, accent)
	var scroll := ScrollContainer.new()
	scroll.position = bounds.position + Vector2(16, 66)
	scroll.size = bounds.size - Vector2(32, 140)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var close := Neon.button(_modal, "BACK TO VILLAGE", Rect2(bounds.position + Vector2(16, bounds.size.y - 64), Vector2(bounds.size.x - 32, 48)), accent)
	close.pressed.connect(_modal.queue_free)
	return list

func open_bay() -> void:
	var list := modal("BUILD BAY", Ui.NEON_MAGENTA)
	for element in host._district.get("elements", []):
		if typeof(element) != TYPE_DICTIONARY:
			continue
		var q := quote(element)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Ui.style_box(Ui.PANEL, Ui.NEON_CYAN))
		list.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 12)
		box.add_child(heading)
		var thumb: Control = host._element_visual(element, int(q.current))
		thumb.custom_minimum_size = Vector2(64, 72)
		heading.add_child(thumb)
		var label := Ui.label(str(element.get("name", "")).to_upper() + " • LV. %d/%d" % [q.current, q.maximum], 22)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(label)
		var caption := "REPAIR" if q.damaged else ("MAX LEVEL" if q.maxed else "VIEW UPGRADE")
		if not q.maxed:
			caption += " • " + Ui.compact(int(q.cost)) + " CR"
		var action_row := Control.new()
		action_row.custom_minimum_size.y = 52
		box.add_child(action_row)
		var button := Neon.button(action_row, caption, Rect2(0, 0, 250, 52), Ui.NEON_MAGENTA if q.damaged else Ui.GREEN)
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_theme_font_size_override("font_size", 20)
		button.disabled = host._busy
		button.pressed.connect(func() -> void:
			host._armed_element = int(q.id)
			_modal.queue_free()
			refresh()
		)

func open_route() -> void:
	var list := modal("CITY DISTRICTS")
	var completed := int(Store.state.get("districtIndex", 0))
	for district in Config.districts():
		if typeof(district) != TYPE_DICTIONARY:
			continue
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Ui.style_box(Ui.PANEL, Ui.NEON_CYAN if district.id == host._district.get("id", 0) else Ui.BORDER))
		list.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var picture := TextureRect.new()
		picture.texture = host._asset_texture(str(district.get("background", "")))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.custom_minimum_size.y = 125
		box.add_child(picture)
		var status := "COMPLETE" if int(district.id) <= completed else ("CURRENT VILLAGE" if district.id == host._district.get("id", 0) else "LOCKED • COMPLETE PREVIOUS VILLAGES")
		var title := Ui.label("%02d  %s" % [district.id, str(district.get("name", "")).to_upper()], 24)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(title)
		var sub := Ui.label(status, 15, Ui.NEON_CYAN)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(sub)
		var prize := Ui.label(Ui.reward_text(district.get("completionReward", {})), 16, Ui.GOLD)
		prize.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(prize)

func complete(reward_data: Dictionary, all_complete: bool) -> void:
	var list := modal("VILLAGE COMPLETE", Ui.GOLD, 560)
	var trophy := TextureRect.new()
	trophy.texture = Neon.icon(10)
	trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trophy.custom_minimum_size.y = 190
	list.add_child(trophy)
	var copy := Ui.label(Ui.reward_text(reward_data), 25, Ui.GOLD)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(copy)
	var button := Ui.button("CITY SECURED" if all_complete else "EXPLORE NEXT VILLAGE", Ui.GREEN)
	list.add_child(button)
	button.pressed.connect(func() -> void:
		_modal.queue_free()
		host._refresh()
	)
