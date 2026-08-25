extends Control
## Main — racine : fond néon, ScreenManager (pile simple), boot flow.
##
## Boot (ARCH §3.2) :
##   1. téléchargement de la remote config (GET /config) — échec → "no network"
##   2. session existante (token) ? GET /state → Spin. Sinon → Onboarding.

const SPIN := "res://scenes/screens/SpinScreen.tscn"
const ONBOARDING := "res://scenes/screens/OnboardingScreen.tscn"
const SCREENS := {
	"spin": "res://scenes/screens/SpinScreen.tscn",
	"district": "res://scenes/screens/DistrictScreen.tscn",
	"collection": "res://scenes/screens/CollectionScreen.tscn",
	"missions": "res://scenes/screens/MissionsScreen.tscn",
	"store": "res://scenes/screens/StoreScreen.tscn",
}

var _screen_root: Control
var _screen: Control = null
var _nav: PanelContainer
var _nav_buttons: Dictionary = {}
var _current_tab := ""
var qa_bypass_boot := false

func _ready() -> void:
	_build_shell()
	if qa_bypass_boot:
		return
	Events.track("app_open")
	Store.session_expired.connect(_on_session_expired)
	_boot()

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _screen != null and _screen.has_method("handle_back") and bool(_screen.call("handle_back")):
		return
	if _dismiss_top_modal():
		return
	if _current_tab != "" and _current_tab != "spin":
		_open_tab("spin")
		return
	get_tree().quit()

func _dismiss_top_modal() -> bool:
	if _screen == null:
		return false
	var nodes := get_tree().get_nodes_in_group("dismiss_on_back")
	for index in range(nodes.size() - 1, -1, -1):
		var node := nodes[index]
		if is_instance_valid(node) and node is CanvasItem and node.visible and (_screen == node or _screen.is_ancestor_of(node)):
			node.queue_free()
			return true
	return false

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = Ui.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Grille et halos animés communs à tous les écrans.
	var ambiance := Ui.SignalBackdrop.new()
	ambiance.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ambiance)

	_screen_root = Control.new()
	_screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_root)

func _loading(text: String) -> void:
	_clear_screen()
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var l := Ui.label(text, 22, Ui.TEXT_DIM)
	l.set_anchors_preset(Control.PRESET_CENTER)
	c.add_child(l)
	_show(c)

func _show(node: Control) -> void:
	_clear_screen()
	_screen = node
	_screen_root.add_child(node)

func _clear_screen() -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null

func _show_screen(path: String) -> void:
	var inst: Control = load(path).instantiate()
	_show(inst)

func _enter_game(tab: String = "spin") -> void:
	if _nav == null:
		_build_nav()
	_nav.visible = true
	_open_tab(tab)

func _open_tab(tab: String) -> void:
	if not SCREENS.has(tab) or tab == _current_tab:
		return
	_current_tab = tab
	var inst: Control = load(SCREENS[tab]).instantiate()
	if inst.has_signal("navigate_requested"):
		inst.connect("navigate_requested", _open_tab)
	_show(inst)
	if not Preferences.reduced_motion:
		inst.modulate = Color(1, 1, 1, 0)
		inst.position = Vector2(18, 0)
		var entrance := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		entrance.tween_property(inst, "modulate", Color.WHITE, 0.22)
		entrance.tween_property(inst, "position", Vector2.ZERO, 0.28)
	for key in _nav_buttons:
		var btn: Button = _nav_buttons[key]
		btn.add_theme_color_override("font_color", Color.WHITE if key == tab else Color("#B9C7F2"))
		btn.button_pressed = key == tab


func _nav_box(bg: Color, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(18)
	box.set_content_margin_all(6)
	return box

func _build_nav() -> void:
	_nav = Ui.panel(Color("#15183C", 0.98), Color("#5DE9FF"))
	_nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	var safe := Ui.safe_insets()
	_nav.offset_left = 10 + safe.x
	_nav.offset_right = -(10 + safe.z)
	_nav.offset_top = -Ui.NAV_HEIGHT
	_nav.offset_bottom = -(8 + safe.w)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	var active_rail := ColorRect.new()
	active_rail.color = Color(Ui.GOLD, 0.94)
	active_rail.custom_minimum_size.y = 2
	active_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(active_rail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var labels := {
		"spin":"◎\nSPIN",
		"district":"▦\nBASE",
		"collection":"✦\nCARDS",
		"missions":"✓\nQUESTS",
		"store":"◆\nSHOP",
	}
	for key in labels:
		var button := Button.new()
		button.text = labels[key]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 70
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _nav_box(Color.TRANSPARENT))
		button.add_theme_stylebox_override("hover", _nav_box(Color("#31529A", 0.72)))
		button.add_theme_stylebox_override("pressed", _nav_box(Color("#334D9A"), Ui.GOLD, 3))
		button.pressed.connect(_on_nav_pressed.bind(key))
		row.add_child(button)
		_nav_buttons[key] = button
	stack.add_child(row)
	_nav.add_child(stack)
	add_child(_nav)
	_nav.visible = false

func _on_nav_pressed(tab: String) -> void:
	if tab == _current_tab:
		return
	Sfx.click()
	Haptics.vibrate(0.18, 12)
	_open_tab(tab)

func _boot() -> void:
	_loading("CHARGEMENT…")
	var ok := await Config.load_remote()
	if not ok:
		_show_network_error()
		return
	Events.track("session_start", { "configVersion": Config.version })
	if Config.from_cache:
		Events.track("config_cache_fallback", {"configVersion": Config.version})
	if Net.has_token():
		var st := await Net.protected_request("GET", "/state")
		if st.ok:
			Store.apply_state(st.data)
			_enter_game("spin")
			return
		if st.code == 401:
			Net.clear_session()
			Store.reset_session()
			Events.reset_session()
	# Pas de session valide → onboarding.
	_go_onboarding()

func _go_onboarding() -> void:
	_current_tab = ""
	if _nav != null:
		_nav.visible = false
	var inst: Control = load(ONBOARDING).instantiate()
	inst.connected.connect(_go_spin)
	_show(inst)

func _go_spin() -> void:
	_enter_game("spin")

func _show_network_error() -> void:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	box.custom_minimum_size = Vector2(0, 0)

	var title := Ui.label("HORS LIGNE", 34, Ui.NEON_MAGENTA)
	var msg := Ui.label("Serveur CyberSeeker injoignable.\nVérifie ta connexion et réessaie.", 18, Ui.TEXT_DIM)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var retry := Button.new()
	retry.text = "RÉESSAYER"
	retry.custom_minimum_size = Vector2(0, 64)
	retry.pressed.connect(_on_retry)

	box.add_child(title)
	box.add_child(msg)
	box.add_child(retry)
	center.add_child(box)
	c.add_child(center)
	_show(c)

func _on_retry() -> void:
	Sfx.click()
	_boot()

func _on_session_expired() -> void:
	Net.clear_session()
	Store.reset_session()
	Events.reset_session()
	_go_onboarding()
