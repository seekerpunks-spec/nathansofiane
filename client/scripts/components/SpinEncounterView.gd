extends RefCounted
## Présentation des rencontres Attack/Raid. Les choix appellent le contrôleur ;
## aucun calcul économique n'est effectué ici.

var host

func _init(owner: Control) -> void:
	host = owner

func show_encounter(encounter: Dictionary, banner: String = "") -> void:
	host._clear_social_overlay()
	host._social_busy = false
	host._social_overlay = ColorRect.new()
	host._social_overlay.color = Color(0.015, 0.02, 0.07, 0.97)
	host._social_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	host._social_overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := Ui.panel(Ui.PANEL_HI, Ui.NEON_MAGENTA)
	panel.custom_minimum_size = Vector2(0, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var kind := str(encounter.get("kind", ""))
	box.add_child(Ui.label("SIGNAL JAM" if kind == "attack" else "GHOST VAULT", 31, Ui.NEON_MAGENTA if kind == "attack" else Ui.GOLD))
	box.add_child(Ui.label("TARGET  •  " + str(encounter.get("target", "NEON CORP")), 14, Ui.TEXT_DIM))
	if banner != "":
		box.add_child(Ui.label(banner, 18, Ui.NEON_CYAN))
	if kind == "attack":
		box.add_child(Ui.label("Pick a node to jam. A rival Firewall can absorb the pulse.", 14, Ui.TEXT))
		var choices: Array = encounter.get("choices", [])
		for element_id in choices:
			var attack := Ui.button("JAM NODE %d" % int(element_id), Ui.NEON_MAGENTA)
			attack.pressed.connect(host._resolve_attack.bind(encounter, int(element_id), box))
			box.add_child(attack)
	else:
		var unbanked := int(encounter.get("unbankedCredits", 0))
		box.add_child(Ui.label("UNBANKED  •  %s CR" % Ui.compact(unbanked), 19, Ui.GOLD))
		box.add_child(Ui.label("Each cache grows the haul. A TRACE wipes everything unbanked.", 14, Ui.TEXT))
		var grid := GridContainer.new()
		grid.columns = 3
		var picked: Array = encounter.get("picked", [])
		for node_index in int(encounter.get("nodeCount", 6)):
			var node := Ui.button("NODE %d" % (node_index + 1), Ui.NEON_CYAN, true)
			node.disabled = picked.has(node_index)
			node.pressed.connect(host._raid_pick.bind(encounter, node_index))
			grid.add_child(node)
		box.add_child(grid)
		if bool(encounter.get("canCashout", false)):
			var cashout := Ui.button("CASH OUT  %s CR" % Ui.compact(unbanked), Ui.GOLD)
			cashout.pressed.connect(host._raid_cashout.bind(encounter, box))
			box.add_child(cashout)
	var later := Ui.button("COME BACK LATER", Ui.TEXT_DIM, true)
	later.pressed.connect(host._clear_social_overlay)
	box.add_child(later)
	panel.add_child(box)
	center.add_child(panel)
	host._social_overlay.add_child(center)
	host.add_child(host._social_overlay)

func show_result(message: String, failed: bool) -> void:
	host._clear_social_overlay()
	host._social_busy = false
	host._social_overlay = ColorRect.new()
	host._social_overlay.color = Color(0.015, 0.02, 0.07, 0.97)
	host._social_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	host._social_overlay.add_to_group("dismiss_on_back")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 0
	box.add_theme_constant_override("separation", 16)
	box.add_child(Ui.label(message, 25, Ui.NEON_MAGENTA if failed else Ui.GOLD))
	var close := Ui.button("CONTINUE", Ui.NEON_CYAN)
	close.pressed.connect(host._clear_social_overlay)
	box.add_child(close)
	center.add_child(box)
	host._social_overlay.add_child(center)
	host.add_child(host._social_overlay)
