extends Control
## District 1 — construction data-driven, mutation autoritaire.

signal navigate_requested(tab: String)

## Décor de secours quand un district n'a pas encore son art propre.
const FALLBACK_BACKGROUND := "res://assets/generated/districts/stages/neon_slums.webp"
const HERO_ART := "res://assets/generated/api_gpt/heroes/district_hero.webp"
const STAR_ART := "res://assets/generated/ui/star.webp"
const HAMMER_ART := "res://assets/generated/ui/hammer.webp"
const WRENCH_ART := "res://assets/generated/ui/wrench.webp"
const ASSET_ROOT := "res://assets/generated/"
## WebP runtime, PNG accepté si un art n'est pas encore converti.
const ASSET_EXTENSIONS: Array[String] = [".webp", ".png"]

const IVORY := Color("#061224")
const INK := Color("#F1FCFF")
const PAD_SIZE := Vector2(250, 360)
const ART_SIZE := Vector2(250, 270)
const HAMMER := 68

var _credits: Label
var _progress: ProgressBar
var _progress_label: Label
var _list: Control
var _background: TextureRect
var _hero_holder: VBoxContainer
var _busy := false
var _district: Dictionary = {}
var _layout_busy := false
var _armed_element := -1
var _map_view: RefCounted
var _map_message := ""

func _ready() -> void:
	_district = _active_district()
	_build_background()
	_build()
	Store.state_changed.connect(_refresh)
	_refresh()

## Résout un nom d'asset de config en texture. Les configs stockent des noms
## relatifs sans extension ; un asset absent renvoie null plutôt que d'échouer,
## donc un district peut être livré par config avant son art.
##
## Le nom vient d'une config distante mise en cache sur l'appareil, donc il est
## traité comme une donnée non fiable : il reste confiné sous ASSET_ROOT et le
## résultat doit être une texture, jamais un script ou une scène.
func _asset_texture(name: String) -> Texture2D:
	var trimmed := name.strip_edges()
	if trimmed.is_empty() or trimmed.contains("..") or trimmed.contains(":") or trimmed.begins_with("/"):
		return null
	for extension in ASSET_EXTENSIONS:
		var path := ASSET_ROOT + trimmed + extension
		if not ResourceLoader.exists(path):
			continue
		var resource := load(path)
		if resource is Texture2D:
			return resource
	return null

func _build_background() -> void:
	_background = TextureRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sky := ColorRect.new()
	sky.color = Color("#071A4A")
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	Ui.soften_tex(_background)
	_background.modulate = Color.WHITE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_apply_background()

func _apply_background() -> void:
	if _background == null:
		return
	var texture := _asset_texture(str(_district.get("background", "")))
	if texture == null:
		texture = load(FALLBACK_BACKGROUND)
	_background.texture = texture

func _build() -> void:
	_map_view = preload("res://scripts/components/DistrictMapView.gd").new()
	_map_view.build(self)

func _rebuild_hero() -> void:
	if _map_view != null:
		_map_view.rebuild_header()

func _refresh() -> void:
	var active := _active_district()
	if not active.is_empty() and int(active.get("id", 0)) != int(_district.get("id", 0)):
		_district = active
		_armed_element = -1
		_apply_background()
		_rebuild_hero()
	if _map_view != null:
		_map_view.refresh()

func _layout_pads() -> void:
	if _map_view != null:
		_map_view.layout()

func _open_build_bay() -> void:
	if not _busy and not _district.is_empty():
		Sfx.click()
		_map_view.open_bay()

func _active_district() -> Dictionary:
	var completed := int(Store.state.get("districtIndex", 0))
	var fallback: Dictionary = {}
	for candidate in Config.districts():
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		fallback = candidate
		if int(candidate.get("id", 0)) > completed:
			return candidate
	return fallback

func _element_visual(element: Dictionary, current: int) -> Control:
	var levels: Array = element.get("levels", [])
	if current >= 0 and current < levels.size() and typeof(levels[current]) == TYPE_DICTIONARY:
		var texture := _asset_texture(str(levels[current].get("asset", "")))
		if texture != null:
			var art := TextureRect.new()
			art.texture = texture
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			Ui.soften_tex(art)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.custom_minimum_size = ART_SIZE
			art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			return art
	var glyph := StructureGlyph.new()
	glyph.kind = int(element.get("id", 1))
	glyph.variant = int(_district.get("id", 1))
	glyph.level = current
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.custom_minimum_size = ART_SIZE
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return glyph

func _repair(element_id: int) -> void:
	if _busy:
		return
	_busy = true
	_map_message = ""
	_map_view.render_detail()
	var district_id := int(_district.get("id", 1))
	Events.track("repair_started", {"districtId": district_id, "elementId": element_id})
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/district/repair", {"districtId": district_id, "elementId": element_id, "requestId": rid}, rid)
	if response.ok and typeof(response.data) == TYPE_DICTIONARY:
		Store.apply_mutation(response.data)
		var cost := int(response.data.get("cost", 0))
		Events.track("repair_completed", {"districtId": district_id, "elementId": element_id, "cost": cost})
		Events.track("currency_spent", {"currency": "credits", "amount": cost, "sink": "repair", "districtId": district_id, "elementId": element_id})
		await _sync_state()
	else:
		_map_message = "ACTION NOT CONFIRMED • CHECK CONNECTION AND BALANCE"
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()

func _sync_state() -> void:
	var state_response := await Net.protected_request("GET", "/state")
	if state_response.ok and typeof(state_response.data) == TYPE_DICTIONARY:
		Store.apply_state(state_response.data)

func _upgrade(element_id: int) -> void:
	if _busy:
		return
	_busy = true
	_map_message = ""
	_map_view.render_detail()
	var upgraded_district_id := int(_district.get("id", 1))
	var current_level := Store.district_level(upgraded_district_id, element_id)
	var expected_cost := 0
	for element in _district.get("elements", []):
		if typeof(element) == TYPE_DICTIONARY and int(element.get("id", 0)) == element_id:
			var levels: Array = element.get("levels", [])
			if current_level + 1 < levels.size():
				expected_cost = int(levels[current_level + 1].get("cost", 0))
			break
	Events.track("upgrade_started", {
		"districtId": upgraded_district_id,
		"elementId": element_id,
		"fromLevel": current_level,
		"expectedCost": expected_cost,
	})
	Sfx.click()
	var rid := Net.request_id()
	var response := await Net.protected_request("POST", "/district/upgrade", {"districtId": int(_district.get("id", 1)), "elementId": element_id, "requestId": rid}, rid)
	if response.ok:
		Store.apply_mutation(response.data)
		var paid := int(response.data.get("cost", expected_cost))
		Events.track("upgrade_completed", {"districtId": upgraded_district_id, "elementId": element_id, "level": response.data.get("level", 0), "cost": paid})
		Events.track("currency_spent", {"currency": "credits", "amount": paid, "sink": "upgrade", "districtId": upgraded_district_id, "elementId": element_id})
		_track_reward_pool(response.data.get("rewardPoolAllocations", []))
		Haptics.vibrate(0.55, 45)
		Sfx.upgrade()
		if response.data.get("districtComplete", false):
			_show_complete(
				response.data.get("completionReward", {}),
				upgraded_district_id,
				int(response.data.get("nextDistrictId", 0)),
				bool(response.data.get("allDistrictsComplete", false))
			)
	elif response.code == 401:
		Store.session_expired.emit()
	else:
		_map_message = "ACTION NOT CONFIRMED • CHECK CONNECTION AND BALANCE"
		Sfx.error()
		Haptics.error()
	_busy = false
	_refresh()
	if response.ok:
		call_deferred("_pulse_element", element_id)

func _pulse_element(element_id: int) -> void:
	var target: Control = null
	for child in _list.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.has_meta("element_id") and int(child.get_meta("element_id")) == element_id:
			target = child
	if target != null:
		var bounce: Control = target
		for child in target.get_children():
			if child is BaseButton:
				bounce = child
				break
		Juice.pop(bounce, 1.08, 0.24)

func _track_reward_pool(allocations: Variant) -> void:
	if typeof(allocations) != TYPE_ARRAY:
		return
	for allocation in allocations:
		if typeof(allocation) == TYPE_DICTIONARY and int(allocation.get("amountU64", 0)) > 0:
			Events.track("reward_pool_progress", allocation)

func _show_complete(reward: Dictionary, district_id: int, next_district_id: int, all_complete: bool) -> void:
	Events.track("village_completed", {"districtId": district_id, "nextDistrictId": next_district_id, "allDistrictsComplete": all_complete})
	if int(reward.get("credits", 0)) > 0:
		Events.track("currency_earned", {"currency": "credits", "amount": int(reward.get("credits", 0)), "source": "village_completed", "districtId": district_id})
	_map_view.complete(reward, all_complete)
	Sfx.result("legendary")
	Haptics.win("legendary")

class ToolGlyph extends Control:
	var repair := false

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var ink := Color("#11225A")
		draw_circle(center + Vector2(-7, 9), 8, ink)
		draw_line(center + Vector2(-5, 6), center + Vector2(13, -11), ink, 7.0)
		var head := Color("#FF8A3A") if repair else Color("#FFD34E")
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(6, -16),
			center + Vector2(18, -8),
			center + Vector2(12, -2),
			center + Vector2(2, -10),
		]), head)

## Cinq silhouettes × six états, dessinées sans dépendance à un sprite. Chaque
## niveau ajoute énergie, néons et détails, donc l'amélioration reste visible
## même si un pack d'art distant n'est pas encore téléchargé.
##
## `kind` accepte n'importe quel identifiant d'élément : les silhouettes tournent
## en boucle et un bandeau de série marque les identifiants au-delà de cinq, donc
## un district ajouté par config ne peut plus produire de plateforme nue.
## `variant` décale la palette par district pour qu'ils ne se ressemblent pas.
class StructureGlyph extends Control:
	var kind := 1
	var level := 0
	var variant := 1

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _shape() -> int:
		return posmod(maxi(kind, 1) - 1, 5) + 1

	func _series() -> int:
		return (maxi(kind, 1) - 1) / 5

	func _accent() -> Color:
		match posmod(maxi(variant, 1) - 1, 5):
			1: return Ui.NEON_MAGENTA
			2: return Ui.GREEN
			3: return Ui.GOLD
			4: return Ui.NEON_CYAN
			_: return Ui.NEON_CYAN

	func _secondary() -> Color:
		match posmod(maxi(variant, 1) - 1, 5):
			1: return Ui.GOLD
			2: return Ui.NEON_CYAN
			3: return Ui.NEON_MAGENTA
			4: return Ui.GREEN
			_: return Ui.NEON_MAGENTA

	func _draw() -> void:
		var draw_scale := size.x / 76.0 if size.x > 1.0 else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(draw_scale, draw_scale))
		var accent := _accent()
		var secondary := _secondary()
		var base := Rect2(8, 50, 60, 18)
		draw_rect(base, Color(0.08, 0.10, 0.18), true)
		draw_rect(base, Ui.BORDER, false, 2.0)
		var shell := Color(0.16, 0.19, 0.30) if level > 0 else Color(0.09, 0.10, 0.14)
		match _shape():
			1:
				draw_rect(Rect2(17, 16, 42, 38), shell, true)
				for y in range(23, 49, 10):
					draw_rect(Rect2(24, y, 8, 5), _light(level, y), true)
					draw_rect(Rect2(43, y, 8, 5), _light(level - 1, y), true)
			2:
				draw_rect(Rect2(12, 24, 52, 31), shell, true)
				draw_rect(Rect2(19, 30, 38, 17), Color(accent, 0.15 + level * 0.12), true)
				draw_line(Vector2(38, 24), Vector2(38, 11), secondary if level >= 4 else Ui.BORDER, 3)
			3:
				draw_circle(Vector2(38, 35), 20, shell)
				for ring in range(1, mini(level, 3) + 1):
					draw_arc(Vector2(38, 35), 5.0 + ring * 5.0, 0, TAU, 24, Color(accent, 0.35 + ring * 0.15), 2)
				draw_line(Vector2(38, 15), Vector2(38, 7), Ui.GOLD if level >= 5 else Ui.BORDER, 3)
			4:
				draw_rect(Rect2(12, 27, 52, 29), shell, true)
				draw_colored_polygon(PackedVector2Array([Vector2(9,27),Vector2(67,27),Vector2(59,17),Vector2(17,17)]), secondary if level >= 2 else Ui.BORDER)
				draw_rect(Rect2(21, 35, 34, 8), Color(Ui.GOLD, 0.18 + level * 0.12), true)
			5:
				draw_line(Vector2(38, 54), Vector2(38, 9), shell.lightened(0.4), 6)
				draw_line(Vector2(38, 18), Vector2(20, 30), Ui.BORDER, 3)
				draw_line(Vector2(38, 18), Vector2(56, 30), Ui.BORDER, 3)
				for ring in range(mini(level, 3)):
					draw_arc(Vector2(38, 14), 8.0 + ring * 6.0, PI + 0.3, TAU - 0.3, 18, Color(accent, 0.45), 2)
		for series in range(mini(_series(), 3)):
			draw_rect(Rect2(10 + series * 7, 46, 5, 3), Color(secondary, 0.85), true)
		if level == 0:
			draw_line(Vector2(11, 61), Vector2(64, 19), Color(Ui.DANGER, 0.45), 3)
		elif level >= 5:
			draw_arc(Vector2(38, 37), 31, 0, TAU, 36, Color(Ui.GOLD, 0.75), 2)

	func _light(required: int, seed: int) -> Color:
		return Color(_accent(), 0.85) if level >= maxi(1, required % 5) else Color(Ui.BORDER, 0.35)
