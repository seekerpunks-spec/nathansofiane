extends RefCounted
## Composants de rendu procédural du slot. Ils ne connaissent ni le réseau ni
## l'économie : SpinScreen leur transmet uniquement un état visuel.

static func symbols_for_result(outcome: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var result_type := str(outcome.get("type", "credits")).to_lower()
	var tier := str(outcome.get("tier", "common")).to_lower()
	if result_type in ["none", "glitch"]:
		result.assign(["glitch", "credits", "energy"])
		return result
	var symbol := "credits"
	match result_type:
		"attack":
			symbol = "hack"
		"raid":
			symbol = "vault"
		"shield":
			symbol = "shield"
		"chest":
			symbol = "energy"
		"card":
			symbol = "hack"
	if result_type != "credits":
		result.assign([symbol, symbol, symbol])
		return result
	match tier:
		"uncommon":
			symbol = "energy"
		"rare":
			symbol = "shield"
		"epic":
			symbol = "hack"
		"legendary":
			symbol = "vault"
	result.assign([symbol, symbol, symbol])
	return result

class SlotCabinet extends Control:
	var accent := Ui.NEON_CYAN
	var win_mode := false
	var _time := 0.0

	func _ready() -> void:
		set_process(true)

	func set_mode(color: Color, winning: bool) -> void:
		accent = color
		win_mode = winning
		queue_redraw()

	func _process(delta: float) -> void:
		if Preferences.reduced_motion:
			return
		_time += delta
		queue_redraw()

	func _box(color: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
		return Ui.style_box(color, border, radius, width)

	func _draw() -> void:
		var breathe := 0.60 + sin(_time * (4.0 if win_mode else 1.8)) * 0.18
		var outer := _box(Color("#080D1D"), Color(accent, breathe), 34, 4)
		outer.shadow_color = Color(accent, 0.35 + breathe * 0.20)
		outer.shadow_size = 24 if not win_mode else 34
		draw_style_box(outer, Rect2(4, 4, size.x - 8, size.y - 8))
		draw_style_box(_box(Color("#151E3D"), Color(accent, 0.88), 22, 2), Rect2(30, 22, size.x - 60, 58))
		draw_style_box(_box(Color("#050712"), Color("#35446E"), 26, 2), Rect2(24, 96, size.x - 48, 342))
		draw_rect(Rect2(30, 265, size.x - 60, 3), Color(accent, 0.92))
		draw_line(Vector2(30, 266), Vector2(size.x - 30, 266), Color(accent, 0.9), 3.0)
		for i in 7:
			var energy := 0.16 + 0.10 * sin(_time * 3.0 + i)
			draw_rect(Rect2(18 + i * 72, 92, 34, 3), Color(accent, energy))
		var corner := 18.0
		var corners := [Vector2(18, 18), Vector2(size.x - 18, 18), Vector2(18, size.y - 18), Vector2(size.x - 18, size.y - 18)]
		for point in corners:
			draw_circle(point, 4.0 + sin(_time * 2.0) * 1.2, Color(accent, 0.85))
			draw_arc(point, corner, 0, TAU, 20, Color(accent, 0.20), 2.0)


class SlotReel extends Control:
	const CELL_HEIGHT := 58.0
	var atlas: Texture2D
	var symbols: Array = []
	var reel_index := 0
	var spinning := false
	var final_symbol := "credits"
	var roll_offset := 0.0:
		set(value):
			roll_offset = value
			queue_redraw()
	var tick_flash := 0.0
	var _time := 0.0

	func _ready() -> void:
		set_process(true)

	func start_spin() -> void:
		spinning = true
		roll_offset = 0.0
		queue_redraw()

	func land(symbol: String) -> void:
		spinning = false
		final_symbol = symbol
		roll_offset = 0.0
		tick_flash = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		if not Preferences.reduced_motion or spinning:
			_time += delta
		tick_flash = maxf(0.0, tick_flash - delta * 6.0)
		if not Preferences.reduced_motion or spinning or tick_flash > 0.0:
			queue_redraw()

	func _draw() -> void:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(1, 1, 1, 0.015)
		panel.set_corner_radius_all(8)
		draw_style_box(panel, Rect2(0, 0, size.x, size.y))
		var row_height := (size.y - 16.0) / 3.0
		for row in 3:
			var cell := StyleBoxFlat.new()
			cell.bg_color = Color("#FFFDF4", 0.105) if row == 1 else Color("#FFFDF4", 0.065)
			cell.border_color = Color(Ui.GOLD, 0.32)
			cell.set_border_width_all(1)
			cell.set_corner_radius_all(7)
			draw_style_box(cell, Rect2(4, 5 + row * row_height, size.x - 8, row_height - 2))
		if spinning:
			_draw_scrolling()
		else:
			_draw_resting()
		var center_y := size.y / 2.0
		draw_rect(Rect2(4, center_y - 34, size.x - 8, 68), Color(Ui.GOLD, 0.045 + tick_flash * 0.09))
		var center_box := StyleBoxFlat.new()
		center_box.bg_color = Color(1, 1, 1, 0.018)
		center_box.border_color = Color("#FFB82E", 0.90)
		center_box.set_border_width_all(2)
		center_box.set_corner_radius_all(8)
		draw_style_box(center_box, Rect2(4, center_y - 34, size.x - 8, 68))

	func _draw_resting() -> void:
		var index := symbols.find(final_symbol)
		if index < 0:
			index = 0
		var top: String = symbols[posmod(index - 1, symbols.size())]
		var bottom: String = symbols[posmod(index + 1, symbols.size())]
		var bob := sin(_time * 1.7 + reel_index) * (1.8 if not Preferences.reduced_motion else 0.0)
		var center_y := size.y / 2.0
		_draw_symbol(top, Rect2(14, center_y - CELL_HEIGHT - 23 + bob, size.x - 28, 46), Color(1, 1, 1, 0.76))
		_draw_symbol(final_symbol, Rect2(9, center_y - 32 + bob, size.x - 18, 64), Color.WHITE)
		_draw_symbol(bottom, Rect2(14, center_y + CELL_HEIGHT - 23 + bob, size.x - 28, 46), Color(1, 1, 1, 0.76))

	func _draw_scrolling() -> void:
		var phase := roll_offset / CELL_HEIGHT
		var base := floori(phase)
		var fraction := phase - float(base)
		for slot in range(-2, 4):
			var symbol: String = symbols[posmod(base + slot + reel_index, symbols.size())]
			var y := size.y / 2.0 - 32.0 + (float(slot) - fraction) * CELL_HEIGHT
			var alpha := 1.0 if y > 26 and y < size.y - 58 else 0.45
			_draw_symbol(symbol, Rect2(9, y, size.x - 18, 64), Color(1, 1, 1, alpha))
		for streak in 5:
			var streak_y := 18.0 + streak * 32.0 + fmod(roll_offset * 0.42, 16.0)
			draw_rect(Rect2(14, streak_y, size.x - 28, 3), Color(Ui.GOLD, 0.14 + streak % 2 * 0.10))

	func _draw_symbol(symbol: String, destination: Rect2, tint: Color) -> void:
		if atlas == null or symbols.is_empty():
			return
		var index := symbols.find(symbol)
		if index < 0:
			index = 0
		var column := index % 3
		var row := index / 3
		var cell_width := float(atlas.get_width()) / 3.0
		var cell_height := float(atlas.get_height()) / 2.0
		var source := Rect2(column * cell_width, row * cell_height, cell_width, cell_height)
		draw_texture_rect_region(atlas, destination, source, tint, false, true)


class AnimatedBackdrop extends Control:
	var _time := 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		if Preferences.reduced_motion:
			return
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for i in 16:
			var px := fmod(float(i * 97) + _time * (7.0 + i % 4), 570.0) - 15.0
			var py := fmod(float(i * 67) + sin(_time * 0.7 + i) * 22.0, 990.0)
			var glow := Color.WHITE if i % 3 else Ui.NEON_MAGENTA
			draw_circle(Vector2(px, py), 1.6 + i % 3, Color(glow, 0.18))
		for i in 5:
			var x := 40.0 + i * 122.0 + sin(_time * 0.45 + i) * 16.0
			var y := 170.0 + i * 178.0 + cos(_time * 0.38 + i) * 14.0
			draw_arc(Vector2(x, y), 18.0 + i * 3.0, 0, TAU, 24, Color(Ui.NEON_CYAN, 0.12), 2.0)


class ParticleBurst extends Control:
	var _particles: Array = []

	func emit_burst(origin: Vector2, color: Color, count: int) -> void:
		_particles.clear()
		for i in count:
			var angle := randf_range(-PI, 0.0)
			if i % 3 == 0:
				angle = randf_range(0.0, TAU)
			var speed := randf_range(85.0, 360.0)
			_particles.append({
				"position": origin + Vector2(randf_range(-35, 35), randf_range(-25, 25)),
				"velocity": Vector2(cos(angle), sin(angle)) * speed,
				"life": randf_range(0.55, 1.25), "max_life": 1.25,
				"size": randf_range(2.5, 8.0),
				"color": color.lerp(Ui.NEON_MAGENTA if i % 2 else Ui.GOLD, randf_range(0.0, 0.45)),
			})
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		for particle in _particles:
			particle.position += particle.velocity * delta
			particle.velocity.y += 420.0 * delta
			particle.velocity *= 0.985
			particle.life -= delta
		_particles = _particles.filter(func(particle: Dictionary) -> bool: return particle.life > 0.0)
		if _particles.is_empty():
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		for particle in _particles:
			var alpha := clampf(particle.life / particle.max_life, 0.0, 1.0)
			var color: Color = particle.color
			color.a = alpha
			draw_circle(particle.position, particle.size * alpha, color)
			draw_line(particle.position, particle.position - particle.velocity.normalized() * particle.size * 2.2, Color(color, alpha * 0.55), maxf(1.0, particle.size * 0.30))
