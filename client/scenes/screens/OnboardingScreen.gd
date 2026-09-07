extends Control
## OnboardingScreen — détection + signature wallet (ARCH §3.2).
##
## M1 / DEV : le bouton CONNECT exécute le vrai flow challenge → verify avec
## le joueur de test (`dev-player-0001`, signature littérale "dev", acceptée
## côté serveur quand DEV_AUTH=true). En production, `signature` sera la vraie
## signature Ed25519 du nonce par le SDK wallet Seeker (même contrat API).

const Neon := preload("res://scripts/components/NeonSkin.gd")

signal connected

var _btn: Button
var _status: Label
var _busy: bool = false

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(Ui.illustrated_stage("res://assets/generated/punk_city/city.webp"))
	var body := Ui.screen_body()
	body.offset_bottom = -20
	body.add_theme_constant_override("separation", 18)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var logo := TextureRect.new()
	logo.texture = Neon.LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size.y = 250
	Ui.soften_tex(logo)
	body.add_child(logo)
	var emblem := TextureRect.new()
	emblem.texture = Neon.icon(3)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size.y = 190
	Ui.soften_tex(emblem)
	body.add_child(emblem)
	var panel := Ui.panel(Ui.PANEL, Ui.NEON_CYAN)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 18)
	copy.add_child(Ui.label("THE CITY IS YOURS", 28, Ui.TEXT))
	var sub := Ui.label("Spin for loot. Build your district.\nBreach rival vaults and rise through the ranks.", 16, Ui.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(sub)
	_status = Ui.label("CONNECT YOUR WALLET TO START", 13, Ui.NEON_CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_status)
	_btn = _big_button("LET'S GO • CONNECT WALLET", Ui.GOLD)
	copy.add_child(_btn)
	var mode_text := "TEST MODE • NO REAL PURCHASES" if Wallet.is_dev() else "SECURE SOLANA CONNECTION"
	copy.add_child(Ui.label(mode_text, 11, Ui.TEXT_DIM))
	panel.add_child(copy)
	body.add_child(panel)
	var bottom := Control.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(bottom)
	add_child(body)

func _big_button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Ui.FACE)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(_connect)
	b.add_theme_stylebox_override("normal", Ui.style_box(accent, Color("#FFF1A6"), 24, 3))
	b.add_theme_stylebox_override("hover", Ui.style_box(accent.lightened(0.15), Color.WHITE, 24, 3))
	b.add_theme_stylebox_override("pressed", Ui.style_box(accent.darkened(0.2), Ui.NEON_MAGENTA, 24, 3))
	b.add_theme_color_override("font_color", Ui.BG)
	Juice.arm(b, true)
	return b

func _set_status(text: String, color: Color = Ui.NEON_CYAN) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)

func _connect() -> void:
	if _busy:
		return
	_busy = true
	Sfx.click()
	_btn.disabled = true

	# 1) Challenge → nonce.
	_set_status("Requesting nonce…")
	var wallet_address := Wallet.address()
	if wallet_address == "":
		_finish_error("Seeker wallet unavailable on this device.")
		return
	var c := await Net.post("/auth/challenge", { "address": wallet_address }, false, "")
	if not c.ok:
		_finish_error("Network unreachable.")
		return

	# 2) Signature. DEV : littérale "dev". PROD : message v2 lié au domaine,
	# à l'adresse et au nonce ; repli nonce uniquement pour un ancien serveur.
	var message := str(c.data.get("message", c.data.get("nonce", "")))
	var signed := Wallet.sign_nonce(message)
	if not signed.get("ok", false):
		_finish_error(str(signed.get("error", "Signature declined.")))
		return
	var signature := str(signed.get("signature", ""))
	_set_status("Signing nonce…")
	var v := await Net.post("/auth/verify", { "address": wallet_address, "signature": signature }, false, "")
	if not v.ok or typeof(v.data) != TYPE_DICTIONARY:
		_finish_error("Authentication refused.")
		return

	# 3) Session établie + état initial.
	Net.store_token(v.data["token"], v.data.get("refreshToken", ""))
	Events.track("login", { "isNewPlayer": v.data.get("isNewPlayer", false) })

	_set_status("Connected. Loading your district…")
	var st := await Net.fetch("/state")
	if st.ok:
		Store.apply_state(st.data)
	else:
		# Ne jamais fabriquer un solde local : sans snapshot autoritaire, la
		# session est abandonnée et l'utilisateur relance le flow complet.
		Net.clear_session()
		Store.reset_session()
		Events.reset_session()
		_finish_error("Player state unavailable. Try again in a moment.")
		return

	Haptics.vibrate(0.5, 40)
	connected.emit()
	# NOTE : onboarding sera libéré par Main (queue_free différé) — on s'arrête ici.

func _finish_error(msg: String) -> void:
	Sfx.error()
	Haptics.error()
	_set_status(msg, Ui.NEON_MAGENTA)
	_btn.disabled = false
	_busy = false
