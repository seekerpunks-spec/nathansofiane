extends RefCounted
## Illustrated encounters; all mutations remain in the controller.
const Neon := preload("res://scripts/components/NeonSkin.gd")
var host

func _init(owner: Control) -> void:
	host = owner

func show_encounter(encounter: Dictionary, banner: String = "") -> void:
	host._clear_social_overlay()
	host._social_busy = false
	var attack_mode := str(encounter.get("kind", "")) == "attack"
	var accent := Ui.NEON_MAGENTA if attack_mode else Ui.GOLD
	var dialog := Neon.modal(host, "Signal Jam" if attack_mode else "Ghost Vault", 2 if attack_mode else 3, accent, "COME BACK LATER")
	host._social_overlay = dialog.overlay
	var box: VBoxContainer = dialog.content
	box.add_child(Neon.feature("TARGET ACQUIRED", str(encounter.get("target", "NEON CORP")), 2, accent))
	if banner != "":
		var notice := Ui.label(banner, 19, Ui.NEON_CYAN)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(notice)
	var copy := Ui.label("Choose a node to jam. A Firewall can block the pulse." if attack_mode else "Open caches to grow the haul. A TRACE wipes unbanked credits.", 17, Ui.TEXT_DIM)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(copy)
	var grid := GridContainer.new()
	grid.columns = 2 if attack_mode else 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	if attack_mode:
		for element_id in encounter.get("choices", []):
			var node := _node_card("JAM NODE %d" % int(element_id), 2, accent)
			node.pressed.connect(host._resolve_attack.bind(encounter, int(element_id), box))
			grid.add_child(node)
	else:
		var unbanked := int(encounter.get("unbankedCredits", 0))
		var haul := Ui.label("UNBANKED  •  %s CR" % Ui.compact(unbanked), 26, Ui.GOLD)
		box.add_child(haul)
		box.move_child(haul, 1)
		var picked: Array = encounter.get("picked", [])
		for node_index in int(encounter.get("nodeCount", 6)):
			var node := _node_card("OPENED" if picked.has(node_index) else "CACHE %d" % (node_index + 1), 3, Ui.NEON_CYAN)
			node.disabled = picked.has(node_index)
			node.modulate = Color(0.5, 0.5, 0.6) if node.disabled else Color.WHITE
			node.pressed.connect(host._raid_pick.bind(encounter, node_index))
			grid.add_child(node)
		if bool(encounter.get("canCashout", false)):
			var cashout := Ui.button("CASH OUT  %s CR" % Ui.compact(unbanked), Ui.GOLD)
			cashout.pressed.connect(host._raid_cashout.bind(encounter, box))
			box.add_child(cashout)

func _node_card(caption: String, index: int, accent: Color) -> Button:
	var holder := Control.new()
	var button := Neon.button(holder, "", Rect2(0, 0, 130, 148), accent)
	holder.remove_child(button)
	holder.free()
	button.custom_minimum_size = Vector2(0, 148)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var art := Neon.art(button, Neon.icon(index), Rect2(14, 6, 104, 104))
	art.anchor_right = 1
	art.offset_right = -14
	var text := Neon.text(button, caption, Rect2(4, 113, 122, 28), 15)
	text.anchor_right = 1
	text.offset_right = -4
	button.add_to_group("horizontal_bounds_check")
	return button

func show_result(message: String, failed: bool) -> void:
	host._clear_social_overlay()
	host._social_busy = false
	var accent := Ui.NEON_MAGENTA if failed else Ui.GOLD
	var dialog := Neon.modal(host, "Signal Lost" if failed else "Mission Complete", 5 if failed else 10, accent)
	host._social_overlay = dialog.overlay
	var art := TextureRect.new()
	art.texture = Neon.icon(5 if failed else 0)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = 230
	dialog.content.add_child(art)
	dialog.content.add_child(Ui.label("BREACH FAILED" if failed else "LOOT SECURED", 30, accent))
	var caption := Ui.label(message, 24, Ui.TEXT)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.content.add_child(caption)
