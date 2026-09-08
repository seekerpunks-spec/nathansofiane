extends Button
## One atlas region per collectible; authentic vector emblem stays separate.

var data: Dictionary = {}
var quantity := 0
var preview := false
var large := false
var _art: Texture2D
var _logo: Texture2D

static func local_texture(path: String, prefix: String) -> Texture2D:
	if not path.begins_with(prefix) or path.contains("..") or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func artwork(card: Dictionary) -> Texture2D:
	var sheet := local_texture(str(card.get("image", "")), "res://assets/generated/crypto_cards/")
	var index := int(card.get("imageIndex", -1))
	if sheet == null or index < 0 or index > 8:
		return null
	var tile := AtlasTexture.new()
	tile.atlas = sheet
	var cell := sheet.get_size() / 3.0
	# Keep the scene's safe center; no neighbouring atlas tile can bleed in.
	tile.region = Rect2(Vector2(index % 3, floori(float(index) / 3.0)) * cell + cell * 0.08, cell * 0.84)
	tile.filter_clip = true
	return tile

func _ready() -> void:
	custom_minimum_size = Vector2(0, 184)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_art = artwork(data)
	_logo = local_texture(str(data.get("logo", "")), "res://assets/crypto_logos/")
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	tooltip_text = "%s (%s) • %s • %d owned" % [data.get("name", "Card"), data.get("symbol", ""), data.get("rarity", "common"), quantity]
	var title := Ui.label(str(data.get("name", "Card")), 23 if large else 14, Ui.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.anchor_top = 0.69
	title.anchor_bottom = 0.90
	title.offset_left = 5
	title.offset_right = -5
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var status := Ui.label("PREVIEW" if preview else ("MISSING" if quantity == 0 else ("×%d OWNED" % quantity)), 15 if large else 10, Ui.TEXT_DIM if quantity == 0 else Ui.NEON_CYAN)
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status.anchor_top = 0.90
	status.offset_bottom = -3
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	add_to_group("horizontal_bounds_check")

func _draw() -> void:
	var accent := Ui.tier_color(str(data.get("rarity", "common")))
	var bounds := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	draw_style_box(Ui.style_box(Color("#080e25"), accent, 9, 2), bounds)
	var area := Rect2(5, 5, maxf(0, size.x - 10), size.y * 0.67 - 5)
	if _art != null:
		draw_texture_rect(_art, area, false, Color.WHITE if quantity > 0 or preview else Color(0.52, 0.57, 0.70))
	var radius := minf(area.size.x * 0.24, area.size.y * 0.26)
	var center := Vector2(size.x * 0.5, area.end.y - radius - 7)
	draw_circle(center, radius + 5, Color("#050a1b"))
	draw_arc(center, radius + 5, 0, TAU, 48, accent, 2, true)
	if _logo != null:
		draw_texture_rect(_logo, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), false)
	draw_line(Vector2(5, area.end.y + 2), Vector2(size.x - 5, area.end.y + 2), accent, 2)
	var rank: int = ["common", "uncommon", "rare", "epic", "legendary"].find(str(data.get("rarity", "common"))) + 1
	for i in maxi(1, rank):
		draw_circle(Vector2(12 + i * 9, 13), 2.5, accent)
	if has_focus() or is_hovered():
		draw_style_box(Ui.style_box(Color(accent, 0.08), Color.WHITE, 9, 2), bounds)
