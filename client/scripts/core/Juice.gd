class_name Juice
## Juice — animations UI Godot 4.7, sans lutter contre les Container.
##
## API vérifiée (docs.godotengine.org/en/4.7/classes/class_control.html) :
## `offset_transform_enabled`, `offset_transform_scale`, `offset_transform_position`,
## `offset_transform_pivot_ratio`. Tween : `create_tween`, `tween_property`,
## `tween_method`, `kill`, `is_valid` (class_tween.html). Aucune valeur
## économique ici. `reduced_motion` coupe squash/shake/count-up.

const _META_TWEEN := "juice_tween"
const _META_ARMED := "juice_armed"


static func reduced() -> bool:
	return Preferences.reduced_motion


static func arm(control: Control, pressable: bool = false) -> void:
	control.offset_transform_enabled = true
	control.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	if pressable and control is BaseButton and not control.has_meta(_META_ARMED):
		control.set_meta(_META_ARMED, true)
		var button := control as BaseButton
		button.button_down.connect(func() -> void: press(control, true))
		button.button_up.connect(func() -> void: press(control, false))
		button.mouse_exited.connect(func() -> void: press(control, false))


static func press(control: Control, down: bool) -> void:
	arm(control)
	if reduced():
		control.offset_transform_scale = Vector2.ONE
		return
	_kill(control)
	var target := Vector2(0.94, 0.88) if down else Vector2.ONE
	var tween := control.create_tween()
	tween.tween_property(control, "offset_transform_scale", target, 0.08 if down else 0.16) \
		.set_trans(Tween.TRANS_BACK if not down else Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)
	control.set_meta(_META_TWEEN, tween)


static func pop(control: Control, peak: float = 1.08, duration: float = 0.22) -> void:
	arm(control)
	if reduced():
		control.offset_transform_scale = Vector2.ONE
		return
	_kill(control)
	control.offset_transform_scale = Vector2(peak, peak)
	var tween := control.create_tween()
	tween.tween_property(control, "offset_transform_scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta(_META_TWEEN, tween)


static func shake(control: Control, pixels: float = 8.0) -> void:
	arm(control)
	if reduced():
		control.offset_transform_position = Vector2.ZERO
		return
	_kill(control)
	var tween := control.create_tween()
	tween.tween_property(control, "offset_transform_position", Vector2(-pixels, 2.0), 0.035)
	tween.tween_property(control, "offset_transform_position", Vector2(pixels, -2.0), 0.035)
	tween.tween_property(control, "offset_transform_position", Vector2(-pixels * 0.45, 1.0), 0.04)
	tween.tween_property(control, "offset_transform_position", Vector2.ZERO, 0.08) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta(_META_TWEEN, tween)


static func pulse(control: Control, peak: float = 1.03) -> void:
	arm(control)
	if reduced():
		return
	_kill(control)
	var tween := control.create_tween()
	tween.tween_property(control, "offset_transform_scale", Vector2(peak, peak), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "offset_transform_scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta(_META_TWEEN, tween)


static func modal(panel: Control) -> void:
	arm(panel)
	panel.modulate = Color(1, 1, 1, 0)
	if reduced():
		panel.modulate = Color.WHITE
		panel.offset_transform_scale = Vector2.ONE
		return
	panel.offset_transform_scale = Vector2(0.86, 0.92)
	var tween := panel.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.18)
	tween.tween_property(panel, "offset_transform_scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	panel.set_meta(_META_TWEEN, tween)


static func count(label: Label, from_n: int, to_n: int, duration: float, format: Callable) -> void:
	if reduced() or from_n == to_n or duration <= 0.0:
		label.text = str(format.call(to_n))
		return
	_kill(label)
	var tween := label.create_tween()
	tween.tween_method(
		func(value: float) -> void:
			label.text = str(format.call(int(round(value)))),
		float(from_n),
		float(to_n),
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	label.set_meta(_META_TWEEN, tween)


static func breathe(control: Control, amount: float = 0.025, period: float = 0.85) -> Tween:
	arm(control)
	if reduced():
		return null
	_kill(control)
	var tween := control.create_tween().set_loops()
	tween.tween_property(control, "offset_transform_scale", Vector2(1.0 + amount, 1.0 + amount), period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "offset_transform_scale", Vector2.ONE, period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	control.set_meta(_META_TWEEN, tween)
	return tween


static func stop(control: Control) -> void:
	_kill(control)
	if control.offset_transform_enabled:
		control.offset_transform_scale = Vector2.ONE
		control.offset_transform_position = Vector2.ZERO
		control.offset_transform_rotation = 0.0


static func _kill(control: Control) -> void:
	if not control.has_meta(_META_TWEEN):
		return
	var tween: Variant = control.get_meta(_META_TWEEN)
	if tween is Tween and (tween as Tween).is_valid():
		(tween as Tween).kill()
	control.remove_meta(_META_TWEEN)
