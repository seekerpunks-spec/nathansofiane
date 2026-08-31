extends Control
## OnboardingScreen — détection + signature wallet (ARCH §3.2).
##
## M1 / DEV : le bouton CONNECT exécute le vrai flow challenge → verify avec
## le joueur de test (`dev-player-0001`, signature littérale "dev", acceptée
## côté serveur quand DEV_AUTH=true). En production, `signature` sera la vraie
## signature Ed25519 du nonce par le SDK wallet Seeker (même contrat API).

signal connected

var _btn: Button
var _status: Label
var _busy: bool = false

func _ready() -> void:
	_build()

func _build() -> void:
	var art := TextureRect.new()
	art.texture = load("res://assets/generated/api_gpt/spin_background.webp")
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color.WHITE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var shade := ColorRect.new()
	shade.color = Color("#06143E", 0.10)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var signal_label := Ui.label("BYTE ONLINE  •  SEEKER NETWORK", 13, Color("#172A63"))
	signal_label.position = Vector2(90, 38)
	signal_label.size = Vector2(360, 32)
	signal_label.add_theme_color_override("font_outline_color", Color.WHITE)
	signal_label.add_theme_constant_override("outline_size", 5)
	add_child(signal_label)

	var mascot := Ui.HeroArt.new()
	mascot.texture = load("res://assets/generated/api_gpt/byte.webp")
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.position = Vector2(56, 72)
	mascot.size = Vector2(428, 550)
	mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mascot)

	var panel := Ui.panel(Color("#102B68", 0.98), Ui.GOLD)
	panel.position = Vector2(20, 675)
	panel.size = Vector2(500, 420)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 13)

	var title := Ui.label("CYBER SEEKER", 44, Ui.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(title)
	var chapter := Ui.label("SPIN  •  BUILD  •  COLLECT", 12, Ui.NEON_CYAN)
	chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(chapter)

	var sub := Ui.label("Fais tourner le slot. Rebâtis la ville.\nOuvre des caches avec BYTE.", 17, Ui.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)

	var divider := Ui.separator()
	root.add_child(divider)
	_status = Ui.label("CONNECTE TON WALLET POUR COMMENCER", 13, Ui.NEON_CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_btn = _big_button("LET'S GO  •  CONNECT WALLET", Ui.GOLD)
	root.add_child(_btn)

	var mode_text := "MODE TEST  •  AUCUN ACHAT RÉEL" if Wallet.is_dev() else "CONNEXION SÉCURISÉE SOLANA"
	var dev_note := Ui.label(mode_text, 11, Ui.TEXT_DIM)
	root.add_child(dev_note)
	panel.add_child(root)
	add_child(panel)

func _big_button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(_connect)
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent
	sb.border_color = Color("#FFF1A6")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(12)
	b.add_theme_stylebox_override("normal", sb)
	var sb_hi := StyleBoxFlat.new()
	sb_hi.bg_color = accent.lightened(0.15)
	sb_hi.border_color = Color.WHITE
	sb_hi.set_border_width_all(3)
	sb_hi.set_corner_radius_all(24)
	sb_hi.set_content_margin_all(12)
	b.add_theme_stylebox_override("hover", sb_hi)
	var sb_p := StyleBoxFlat.new()
	sb_p.bg_color = accent.darkened(0.2)
	sb_p.border_color = Ui.NEON_MAGENTA
	sb_p.set_border_width_all(3)
	sb_p.set_corner_radius_all(24)
	sb_p.set_content_margin_all(12)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_color_override("font_color", Ui.BG)
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
	_set_status("Demande d'un nonce…")
	var wallet_address := Wallet.address()
	if wallet_address == "":
		_finish_error("Wallet Seeker indisponible sur cet appareil.")
		return
	var c := await Net.post("/auth/challenge", { "address": wallet_address }, false, "")
	if not c.ok:
		_finish_error("Réseau injoignable.")
		return

	# 2) Signature. DEV : littérale "dev". PROD : signature Ed25519(nonce).
	var signed := Wallet.sign_nonce(str(c.data.get("nonce", "")))
	if not signed.get("ok", false):
		_finish_error(str(signed.get("error", "Signature refusée.")))
		return
	var signature := str(signed.get("signature", ""))
	_set_status("Signature du nonce…")
	var v := await Net.post("/auth/verify", { "address": wallet_address, "signature": signature }, false, "")
	if not v.ok or typeof(v.data) != TYPE_DICTIONARY:
		_finish_error("Authentification refusée.")
		return

	# 3) Session établie + état initial.
	Net.store_token(v.data["token"], v.data.get("refreshToken", ""))
	Events.track("login", { "isNewPlayer": v.data.get("isNewPlayer", false) })

	_set_status("Connexion établie. Chargement de ton district…")
	var st := await Net.fetch("/state")
	if st.ok:
		Store.apply_state(st.data)
	else:
		# Ne jamais fabriquer un solde local : sans snapshot autoritaire, la
		# session est abandonnée et l'utilisateur relance le flow complet.
		Net.clear_session()
		Store.reset_session()
		Events.reset_session()
		_finish_error("État joueur indisponible. Réessaie dans un instant.")
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
