extends RefCounted
## R42 — illustrated atlas + native bevels, shared by the entire game.
const ICONS := preload("res://assets/generated/punk_city/icons.webp")
const CITY := preload("res://assets/generated/punk_city/city.webp")
const LOGO := preload("res://assets/generated/punk_city/logo.webp")
const CABINET := preload("res://assets/generated/punk_city/cabinet.webp")
const DISPLAY_FONT := preload("res://assets/fonts/Rajdhani-Bold.ttf")
## Measured sprite bounds; generated grids contain non-uniform gutters.
const ICON_RECTS := [
	Rect2(68, 22, 302, 285), Rect2(480, 12, 292, 298), Rect2(854, 20, 325, 288),
	Rect2(47, 324, 367, 288), Rect2(482, 324, 294, 289), Rect2(854, 322, 327, 291),
	Rect2(24, 622, 393, 290), Rect2(431, 622, 399, 290), Rect2(851, 620, 328, 293),
	Rect2(42, 914, 338, 317), Rect2(449, 911, 341, 320), Rect2(826, 911, 366, 320),
]

static func header(kicker: String, title: String, index: int, accent: Color = Ui.NEON_CYAN) -> Control:
	var root := Control.new()
	root.custom_minimum_size.y = 110
	var plate := frame(root, Rect2(0, 0, 500, 110), accent)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var picture := art(root, icon(index), Rect2(380, 5, 100, 100))
	picture.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	picture.offset_left = -110
	picture.offset_right = -10
	picture.offset_top = 5
	picture.offset_bottom = 105
	var heading := text(root, title, Rect2(20, 38, 340, 52), 34)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.anchor_right = 1
	heading.offset_right = -120
	var sub := text(root, kicker, Rect2(20, 17, 340, 22), 11, accent)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.anchor_right = 1
	sub.offset_right = -120
	return root

static func icon(index: int) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = ICONS
	result.region = ICON_RECTS[clampi(index, 0, ICON_RECTS.size() - 1)]
	result.filter_clip = true
	return result

static func art(parent: Node, texture: Texture2D, rect: Rect2, stretch: bool = false) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE if stretch else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Ui.soften_tex(node)
	parent.add_child(node)
	return node

static func text(parent: Node, copy: String, rect: Rect2, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Ui.label(copy, font_size, color)
	label.add_theme_font_override("font", DISPLAY_FONT)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func frame(parent: Node, rect: Rect2, accent: Color = Ui.NEON_CYAN) -> Control:
	var node := BevelFrame.new()
	node.accent = accent
	if accent == Ui.GREEN:
		node.fill = Color("#225A04")
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func button(parent: Node, copy: String, rect: Rect2, accent: Color = Ui.NEON_CYAN, framed: bool = true) -> Button:
	var node := Button.new()
	node.text = copy
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_ALL
	node.add_theme_font_override("font", DISPLAY_FONT)
	node.add_theme_font_size_override("font_size", 24)
	node.add_theme_color_override("font_color", Color.WHITE)
	node.add_theme_color_override("font_hover_color", accent.lightened(0.4))
	node.add_theme_color_override("font_pressed_color", accent)
	node.add_theme_color_override("font_disabled_color", Color("#71829B"))
	node.add_theme_color_override("font_outline_color", Color("#050719"))
	node.add_theme_constant_override("outline_size", 1)
	for state in ["normal", "hover", "pressed", "disabled"]:
		node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	node.add_theme_stylebox_override("focus", Ui.style_box(Color.TRANSPARENT, Color.WHITE, 8, 2, false))
	parent.add_child(node)
	if framed:
		var plate := frame(node, Rect2(Vector2.ZERO, rect.size), accent)
		plate.name = "Chrome"
		if accent == Ui.GREEN:
			plate.fill = Color("#225A04")
		plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plate.show_behind_parent = true
		node.mouse_entered.connect(func() -> void: plate.modulate = Color(1.2, 1.2, 1.2))
		node.mouse_exited.connect(func() -> void: plate.modulate = Color.WHITE)
	Juice.arm(node, true)
	return node

static func select(button_node: Button, active: bool) -> void:
	var chrome := button_node.get_node_or_null("Chrome")
	if chrome != null:
		chrome.accent = Ui.NEON_MAGENTA if active else Ui.NEON_CYAN
		chrome.fill = Color("#200A35") if active else Color("#020815", 0.96)
		chrome.queue_redraw()

class BevelFrame extends Control:
	var accent := Ui.NEON_CYAN
	var fill := Color("#020815", 0.96)

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _outline(inset: float) -> PackedVector2Array:
		var cut := minf(16.0, minf(size.x, size.y) * 0.18)
		var left := inset
		var top := inset
		var right := size.x - inset
		var bottom := size.y - inset
		return PackedVector2Array([Vector2(left + cut, top), Vector2(right - cut, top), Vector2(right, top + cut), Vector2(right, bottom - cut), Vector2(right - cut, bottom), Vector2(left + cut, bottom), Vector2(left, bottom - cut), Vector2(left, top + cut), Vector2(left + cut, top)])

	func _draw() -> void:
		if size.x < 20 or size.y < 20:
			return
		draw_colored_polygon(_outline(1), fill)
		draw_polyline(_outline(1), Color("#627FAD"), 2, true)
		draw_polyline(_outline(5), Color("#103564"), 6, true)
		draw_polyline(_outline(7), Color(accent, 0.6), 1.5, true)
		draw_polyline(_outline(11), Color("#1C2C55"), 1, true)
		var a := Vector2(size.x * 0.25, 5)
		var b := Vector2(size.x * 0.68, 5)
		draw_line(a, b, Color(accent, 0.12), 12, true)
		draw_line(a, b, accent, 3, true)
		draw_line(Vector2(6, 21), Vector2(21, 6), Color("#DBF5FF"), 2, true)
		draw_line(Vector2(size.x - 21, size.y - 6), Vector2(size.x - 6, size.y - 21), accent, 2, true)
