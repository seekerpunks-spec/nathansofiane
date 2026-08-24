extends Node
## Haptics — feedback tactile (no-op sur desktop, actif sur mobile).
## NOTE : Input.vibrate_handpad() est indisponible en Godot 4.7 desktop.
## On le réactivera au build Android (O3 : API mobile à confirmer).

func vibrate(strength: float = 1.0, ms: int = 30) -> void:
	if not Preferences.haptics_enabled:
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, clampf(strength, 0.0, 1.0))

func win(tier: String) -> void:
	match tier.to_lower():
		"rare":
			vibrate(0.4, 30)
		"epic":
			vibrate(0.7, 50)
		"legendary":
			vibrate(1.0, 90)
			await get_tree().create_timer(0.12).timeout
			vibrate(1.0, 60)
		_:
			vibrate(0.2, 20)

func error() -> void:
	vibrate(0.5, 60)
