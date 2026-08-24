extends Node
## Store — cache local de l'état joueur (jamais source de vérité).
##
## Après chaque réponse API, le client met à jour ce cache et ré-applique la
## vue (ARCH §3.1). Le serveur fait foi : le cache sert à l'affichage immédiat
## et à la persistance du dernier état connu entre les sessions.

signal state_changed
signal spin_result(result: Dictionary)
signal no_spins(next_ms: int)
signal session_expired

var state: Dictionary = {}

## Offset horloge (serveur - client) en ms, dérivé des serverTimeMs reçus.
var clock_offset_ms: int = 0

# ---------------------------------------------------------------------------
# Horloge compensée
# ---------------------------------------------------------------------------

func _local_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

## Temps "serveur" estimé (ms) — base de tous les compteurs (regen, offers...).
func now_ms() -> int:
	return _local_ms() + clock_offset_ms

## Dérive l'offset à partir d'un timestamp serveur reçu.
func set_clock(server_time_ms: int) -> void:
	if server_time_ms > 0:
		clock_offset_ms = server_time_ms - _local_ms()

## Millisecondes restantes avant le prochain spin (regen).
func regen_remaining_ms() -> int:
	var next: Variant = state.get("nextSpinAtMs", null)
	if next == null:
		return 0
	return maxi(0, int(next) - now_ms())

# ---------------------------------------------------------------------------
# Application des réponses
# ---------------------------------------------------------------------------

## GET /state — snapshot complet.
func apply_state(d: Dictionary) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	state = d
	if state.has("serverTimeMs"):
		set_clock(int(state["serverTimeMs"]))
	state_changed.emit()

## POST /spin — résultat + nouveaux soldes.
func apply_spin(d: Dictionary) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	if d.has("spins"):
		state["spins"] = d["spins"]
	if d.has("credits"):
		state["credits"] = d["credits"]
	if d.has("nextSpinAtMs"):
		state["nextSpinAtMs"] = d["nextSpinAtMs"]
	if d.has("serverTimeMs"):
		set_clock(int(d["serverTimeMs"]))
	state_changed.emit()
	spin_result.emit(d)

## Applique les champs communs d'une mutation puis fusionne les collections.
func apply_mutation(d: Dictionary) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	for key in ["spins", "credits", "nextSpinAtMs", "districtProgress", "cards", "chests", "missions", "events", "seasons", "dailyStreak", "dailyAvailable"]:
		if d.has(key):
			state[key] = d[key]
	if d.has("serverTimeMs"):
		set_clock(int(d["serverTimeMs"]))
	state_changed.emit()

func district_level(district_id: int, element_id: int) -> int:
	for row in state.get("districtProgress", []):
		if typeof(row) == TYPE_DICTIONARY and int(row.get("districtId", 0)) == district_id and int(row.get("elementId", 0)) == element_id:
			return int(row.get("level", 0))
	return 0

func chest_qty(chest_id: String) -> int:
	for row in state.get("chests", []):
		if typeof(row) == TYPE_DICTIONARY and str(row.get("chestId", "")) == chest_id:
			return int(row.get("qty", 0))
	return 0

## 403 NO_SPINS — on connaît l'heure du prochain spin.
func apply_no_spins(next_ms: int) -> void:
	state["spins"] = 0
	if next_ms > 0:
		state["nextSpinAtMs"] = next_ms
	state_changed.emit()
	no_spins.emit(next_ms)

func reset_session() -> void:
	state = {}
	clock_offset_ms = 0

func spins() -> int:
	return int(state.get("spins", 0))

func credits() -> int:
	return int(state.get("credits", 0))
