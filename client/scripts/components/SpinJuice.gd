extends RefCounted
## Rythme visuel du slot. Le serveur a déjà tranché : ici on ne fait que
## mettre en scène (stagger 300 ms, overshoot, anticipation rare+).
## Réfs : arrêts décalés L→R, crawl du dernier rouleau, bounce physique.
## `reduced_motion` raccourcit et coupe shake / overshoot (REDESIGN § mouvement).

const CELL := 58.0


static func spin_reels(host: Node, reels: Array, anticipation: bool, on_land: Callable) -> Array:
	var tweens: Array = []
	for i in 3:
		var reel: Control = reels[i]
		reel.start_spin()
		Juice.arm(reel)
		var duration := 0.24 + i * 0.08 if Juice.reduced() else 0.88 + i * 0.32
		if i == 2 and anticipation and not Juice.reduced():
			duration += 0.42
		var travel := CELL * float(12 + i * 4)
		var tween := host.create_tween()
		if Juice.reduced():
			tween.tween_property(reel, "roll_offset", travel, duration) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(reel, "roll_offset", CELL * 2.0, 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_property(reel, "roll_offset", travel - CELL * 2.4, duration - 0.42) \
				.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(reel, "roll_offset", travel + 10.0, 0.22) \
				.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
			tween.tween_property(reel, "roll_offset", travel, 0.10) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(on_land.bind(i))
		tweens.append(tween)
	return tweens


static func land_bounce(reel: Control) -> void:
	Juice.pop(reel, 1.10, 0.18)


static func impact(banner: Control, cabinet: Control, flash: ColorRect, particles: Control, tier: String, accent: Color) -> void:
	Juice.pop(banner, 1.32, 0.28)
	var count := 22
	var flash_alpha := 0.12
	match tier:
		"rare":
			count = 38
			flash_alpha = 0.22
		"epic":
			count = 64
			flash_alpha = 0.34
		"legendary":
			count = 96
			flash_alpha = 0.54
	particles.emit_burst(Vector2(270, 500), accent, count)
	if tier == "legendary" and particles.has_method("emit_ring"):
		particles.emit_ring(Vector2(270, 430), accent)
	flash.color = Color(accent, flash_alpha)
	var flash_tween := flash.create_tween()
	flash_tween.tween_property(flash, "color", Color(accent, 0), 0.46)
	if not Juice.reduced():
		Juice.shake(cabinet, 9.0 if tier in ["epic", "legendary"] else 5.0)


static func anticipation_pulse(cabinet: Control) -> void:
	Juice.pulse(cabinet, 1.03)
