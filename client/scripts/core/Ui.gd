class_name Ui
## Ui — design system « arcade cyber-cartoon » partagé par les écrans.
##
## Aucune valeur économique ici : uniquement des couleurs et du formatage.

# Palette plus saturée et chaleureuse : cobalt, cyan, magenta et or récompense.
# Le contraste reste WCAG-friendly, mais les surfaces ne ressemblent plus à
# une console technique noire.
const BG := Color("#071A4A")
const PANEL := Color("#10285E")
const PANEL_HI := Color("#1A3D7A")
const BORDER := Color("#4278D7")
const NEON_CYAN := Color("#2BE7FF")
const NEON_MAGENTA := Color("#FF45B5")
const NEON_PINK := Color("#FF628F")
const NEON_BLUE := Color("#5A84FF")
const GOLD := Color("#FFD34E")
const GREEN := Color("#61ED91")
const GREY := Color("#90A5D4")
const TEXT := Color("#FFF8E8")
const TEXT_DIM := Color("#B6C7EB")
const DANGER := Color("#FF526E")
const NAV_HEIGHT := 104
const SAFE_MARGIN := 20
const HERO_HEIGHT := 172

## Couleur d'une rareté (cohérente roue / bannières / cartes).
static func tier_color(tier: String) -> Color:
	match tier.to_lower():
		"uncommon":
			return GREEN
		"rare":
			return NEON_CYAN
		"epic":
			return NEON_MAGENTA
		"legendary":
			return GOLD
		_:
			return GREY

## Formatage compact jusqu'aux grandes économies : K/M/B/T/Qa/Qi.
static func compact(n: int) -> String:
	if absi(n) < 1000:
		return str(n)
	var sign := "-" if n < 0 else ""
	var value := absf(float(n))
	var suffixes: Array[String] = ["K", "M", "B", "T", "Qa", "Qi"]
	var suffix: String = suffixes[0]
	for candidate in suffixes:
		value /= 1000.0
		suffix = candidate
		if value < 1000.0:
			break
	return sign + _trim(value) + suffix

static func _trim(v: float) -> String:
	var s: String
	if v < 10.0:
		s = "%.1f" % v
	elif v < 100.0:
		s = "%.1f" % v
	else:
		s = "%d" % int(round(v))
	# Supprime le ".0" final pour un rendu propre (15K plutôt que 15.0K).
	return s.replace(".0", "")

## mm:ss à partir de millisecondes.
static func mmss(ms: int) -> String:
	var s := maxi(0, ms / 1000)
	return "%02d:%02d" % [s / 60, s % 60]

static func mmss_long(ms: int) -> String:
	var seconds := maxi(0, ms / 1000)
	var days := seconds / 86400
	var hours := (seconds % 86400) / 3600
	var minutes := (seconds % 3600) / 60
	return "%dj %02dh %02dm" % [days, hours, minutes] if days > 0 else "%02dh %02dm" % [hours, minutes]

## Panel avec bordure néon + fond.
static func style_box(bg: Color = PANEL, border: Color = BORDER, radius: int = 18, width: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(15)
	sb.shadow_color = Color("#020929", 0.58)
	sb.shadow_size = 9
	sb.shadow_offset = Vector2(0, 6)
	return sb

static func panel(bg: Color = PANEL, border: Color = BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style_box(bg, border))
	return p

## Label centré.
static func label(text: String, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("#03102E", 0.94))
	l.add_theme_constant_override("outline_size", 4)
	return l

static func button(text: String, accent: Color = NEON_CYAN, secondary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	var base := PANEL_HI if secondary else accent
	var font := TEXT if secondary else BG
	b.add_theme_stylebox_override("normal", style_box(base, Color(accent, 0.92), 20, 3))
	b.add_theme_stylebox_override("hover", style_box(base.lightened(0.09), accent, 20, 3))
	b.add_theme_stylebox_override("pressed", style_box(base.darkened(0.16), Color.WHITE, 20, 3))
	b.add_theme_stylebox_override("disabled", style_box(Color(PANEL_HI, 0.55), BORDER, 20, 1))
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	return b

static func page_title(kicker: String, title: String, subtitle: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var k := label(kicker.to_upper(), 12, NEON_CYAN)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(k)
	var t := label(title, 32, TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(t)
	if subtitle != "":
		var s := label(subtitle, 14, TEXT_DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(s)
	return box

## En-tête illustré : le texte reste natif et accessible, tandis que le rendu
## L'illustration transparente flotte à droite comme un véritable objet 2.5D.
static func hero_card(image_path: String, kicker: String, title: String, subtitle: String, accent: Color = NEON_CYAN) -> PanelContainer:
	var frame := panel(Color("#102C69", 0.98), Color(accent, 0.94))
	frame.custom_minimum_size.y = HERO_HEIGHT
	frame.clip_contents = true

	var stage := Control.new()
	stage.custom_minimum_size.y = HERO_HEIGHT - 28

	var art := HeroArt.new()
	art.name = "HeroArt"
	art.texture = load(image_path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.anchor_left = 0.35
	art.offset_left = -18
	art.offset_right = 28
	art.offset_top = -12
	art.offset_bottom = 12
	stage.add_child(art)

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.64, 1.0])
	gradient.colors = PackedColorArray([
		Color("#0B2259", 0.99),
		Color("#0B2259", 0.94),
		Color("#0B2259", 0.0),
	])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 256
	gradient_texture.height = 32
	gradient_texture.fill_from = Vector2(0, 0.5)
	gradient_texture.fill_to = Vector2(1, 0.5)
	var veil := TextureRect.new()
	veil.texture = gradient_texture
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.anchor_right = 0.74
	veil.anchor_bottom = 1.0
	stage.add_child(veil)

	var copy := VBoxContainer.new()
	copy.anchor_right = 0.60
	copy.anchor_bottom = 1.0
	copy.offset_left = 4
	copy.offset_right = -6
	copy.offset_top = 4
	copy.offset_bottom = -4
	copy.add_theme_constant_override("separation", 3)
	var k := label(kicker.to_upper(), 10, accent)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	copy.add_child(k)
	var t := label(title, 27, TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(t)
	var s := label(subtitle, 12, TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(s)
	stage.add_child(copy)
	frame.add_child(stage)
	return frame

static func section_title(text: String, accent: Color = NEON_CYAN) -> Label:
	var l := label(text.to_upper(), 15, accent)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l

static func progress_bar(accent: Color = NEON_CYAN, height: int = 10) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0
	pb.max_value = 100
	pb.custom_minimum_size = Vector2(0, height)
	pb.add_theme_stylebox_override("background", style_box(Color(1, 1, 1, 0.07), Color.TRANSPARENT, height / 2, 0))
	pb.add_theme_stylebox_override("fill", style_box(accent, accent, height / 2, 0))
	return pb

static func separator() -> HSeparator:
	var line := HSeparator.new()
	line.add_theme_color_override("separator", Color(BORDER, 0.65))
	return line

## Barre de défilement fine et colorée, à la place du rail gris natif Godot.
static func style_scroll(scroll: ScrollContainer, accent: Color = NEON_CYAN) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 8
	bar.add_theme_stylebox_override("scroll", _scroll_box(Color.TRANSPARENT))
	bar.add_theme_stylebox_override("scroll_focus", _scroll_box(Color.TRANSPARENT))
	bar.add_theme_stylebox_override("grabber", _scroll_box(Color(accent, 0.34)))
	bar.add_theme_stylebox_override("grabber_highlight", _scroll_box(Color(accent, 0.64)))
	bar.add_theme_stylebox_override("grabber_pressed", _scroll_box(accent))

static func _scroll_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	return box

static func screen_body() -> VBoxContainer:
	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = SAFE_MARGIN
	body.offset_right = -SAFE_MARGIN
	body.offset_top = SAFE_MARGIN
	body.offset_bottom = -(NAV_HEIGHT + 12)
	body.add_theme_constant_override("separation", 14)
	return body

## Entrée douce et décalée des cartes dynamiques. L'animation ne touche pas
## leur position, donc elle ne lutte jamais contre les Container Godot.
static func reveal(control: Control, delay: float = 0.0) -> void:
	if Preferences.get("reduced_motion"):
		control.modulate = Color.WHITE
		return
	control.modulate = Color(1, 1, 1, 0)
	var tween := control.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, "modulate", Color.WHITE, 0.24)

## Fond commun vivant, volontairement léger pour rester fluide sur mobile.
class SignalBackdrop extends Control:
	var phase := 0.0
	var accent := Color(0.20, 0.92, 1.0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		if not Preferences.get("reduced_motion"):
			phase += delta
		queue_redraw()

	func _draw() -> void:
		var drift := sin(phase * 0.32) * 24.0
		for x in range(-160, int(size.x) + 240, 92):
			draw_line(Vector2(x + drift, 0), Vector2(x - 210 + drift, size.y), Color(accent, 0.055), 2.0)
		for y in range(80, int(size.y), 150):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(NEON_BLUE, 0.045), 1.0)
		var core := Vector2(size.x * 0.82 + sin(phase * 0.42) * 12.0, size.y * 0.24)
		for ring in range(5, 0, -1):
			draw_circle(core, 42.0 + ring * 34.0, Color(accent, 0.012 + ring * 0.006))
		var hot := Vector2(size.x * 0.10, size.y * 0.72 + cos(phase * 0.36) * 18.0)
		for ring in range(4, 0, -1):
			draw_circle(hot, 36.0 + ring * 30.0, Color(NEON_MAGENTA, 0.012 + ring * 0.006))

## Animation intrinsèque du rendu de héros. Elle respecte le réglage de
## réduction des mouvements et ne modifie jamais le layout des conteneurs.
class HeroArt extends TextureRect:
	var phase := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate = Color(1, 1, 1, 0)
		var intro := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		intro.tween_property(self, "modulate", Color.WHITE, 0.45)

	func _process(delta: float) -> void:
		pivot_offset = size * 0.5
		if Preferences.get("reduced_motion"):
			rotation = 0.0
			scale = Vector2.ONE
			return
		phase += delta
		rotation = sin(phase * 0.85) * 0.006
		var breathe := 1.0 + sin(phase * 1.15) * 0.008
		scale = Vector2(breathe, breathe)
