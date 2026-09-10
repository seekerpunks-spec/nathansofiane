extends Control
## Main — racine : fond néon, ScreenManager (pile simple), boot flow.
##
## Boot (ARCH §3.2) :
##   1. téléchargement de la remote config (GET /config) — échec → "no network"
##   2. session existante (token) ? GET /state → Spin. Sinon → Onboarding.

const Neon := preload("res://scripts/components/NeonSkin.gd")
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
	theme = Neon.control_theme()
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
	if qa_bypass_boot:
		inst.set_meta("qa_skip_sync", true)
		inst.set_meta("qa_offers", [])
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
		btn.add_theme_color_override("font_color", Color.WHITE if key == tab or key == "spin" else Color("#B9C7F2"))
		btn.button_pressed = key == tab
		Neon.select(btn, key == tab)


func _nav_box(bg: Color, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var box := Ui.style_box(bg, border, 18, width, bg.a > 0.04)
	box.set_content_margin_all(6)
	return box

func _build_nav() -> void:
	_nav = PanelContainer.new()
	_nav.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	var safe := Ui.safe_insets()
	_nav.offset_left = 8 + safe.x
	_nav.offset_right = -(8 + safe.z)
	_nav.offset_top = -(Ui.NAV_HEIGHT + safe.w)
	_nav.offset_bottom = -(6 + safe.w)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var labels := {"district": "MAP", "missions": "MISSIONS", "collection": "COLLECTION", "spin": "SPIN", "events": "EVENTS", "clan": "CLAN"}
	var icons := {"district": 9, "missions": 8, "collection": 7, "spin": 4, "events": 10, "clan": 1}
	for key in labels:
		var button := Neon.button(row, "", Rect2(0, 0, 74, 76), Ui.NEON_MAGENTA if key == "spin" else Ui.NEON_CYAN)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 76)
		button.tooltip_text = labels[key]
		var picture := Neon.art(button, Neon.icon(icons[key]), Rect2(10, 3, 52, 50))
		picture.set_anchors_preset(Control.PRESET_TOP_WIDE)
		picture.offset_left = 10
		picture.offset_right = -10
		picture.offset_top = 3
		picture.offset_bottom = 53
		var label := Neon.text(button, labels[key], Rect2(0, 53, 74, 19), 10 if key == "collection" else 12)
		label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		label.offset_left = 0
		label.offset_right = 0
		label.offset_top = -22
		label.offset_bottom = -3
		button.pressed.connect(_on_nav_pressed.bind(key))
		_nav_buttons[key] = button
	_nav.add_child(row)
	add_child(_nav)
	_nav.visible = false

func _on_nav_pressed(tab: String) -> void:
	Sfx.click()
	Haptics.vibrate(0.18, 12)
	match tab:
		"clan":
			_open_tab("spin")
			_screen.set_meta("network_page", 2)
			_screen.call("_open_network")
		"events":
			_open_tab("missions")
			_screen.call("_select_page", 1)
		"missions":
			_open_tab("missions")
			_screen.call("_select_page", 0)
		_:
			_open_tab(tab)
	for key in _nav_buttons:
		_nav_buttons[key].button_pressed = key == tab
		Neon.select(_nav_buttons[key], key == tab)


func _boot() -> void:
	_loading("LOADING…")
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
	var body := Ui.screen_body()
	body.add_child(Neon.header("PUNK CITY / CONNECTION", "Offline", 2, Ui.NEON_MAGENTA))
	body.add_child(Neon.feature("SIGNAL INTERRUPTED", "The city will be here when your connection returns.", 1, Ui.NEON_CYAN))
	var msg := Ui.label("CyberSeeker server unreachable. Check your connection and try again.", 18, Ui.TEXT_DIM)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(msg)
	var retry := Ui.button("RECONNECT", Ui.NEON_CYAN)
	retry.pressed.connect(_on_retry)
	body.add_child(retry)
	c.add_child(body)
	_show(c)

func _on_retry() -> void:
	Sfx.click()
	_boot()

func _on_session_expired() -> void:
	Net.clear_session()
	Store.reset_session()
	Events.reset_session()
	_go_onboarding()
