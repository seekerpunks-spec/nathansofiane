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
	if d.has("pendingEncounter"):
		state["pendingEncounter"] = d["pendingEncounter"]
	if d.has("globalProgression"):
		state["progression"] = d["globalProgression"]
	var feature: Variant = d.get("featureReward", null)
	if typeof(feature) == TYPE_DICTIONARY:
		if feature.has("firewallCharges"):
			state["firewallCharges"] = feature["firewallCharges"]
		if feature.has("chestId"):
			_upsert_quantity("chests", "chestId", str(feature.get("chestId", "")), int(feature.get("quantity", 0)))
		if feature.has("cardId"):
			_upsert_quantity("cards", "cardId", str(feature.get("cardId", "")), int(feature.get("quantity", 0)))
	var progress: Variant = d.get("progress", {})
	if typeof(progress) == TYPE_DICTIONARY:
		_apply_event_progress(progress.get("events", []))
		_apply_team_event_progress(progress.get("teamEvents", []))
		_apply_achievement_progress(progress.get("achievements", []))
	if d.has("serverTimeMs"):
		set_clock(int(d["serverTimeMs"]))
	state_changed.emit()
	spin_result.emit(d)

func _upsert_quantity(collection_key: String, id_key: String, id_value: String, quantity: int) -> void:
	var rows: Array = state.get(collection_key, [])
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get(id_key, "")) == id_value:
			row["qty"] = quantity
			return
	var entry := {"qty": quantity}
	entry[id_key] = id_value
	rows.append(entry)
	state[collection_key] = rows

func _apply_event_progress(progress_events: Array) -> void:
	var events: Array = state.get("events", [])
	for update in progress_events:
		if typeof(update) != TYPE_DICTIONARY:
			continue
		var event_id := str(update.get("eventId", ""))
		for event in events:
			if typeof(event) != TYPE_DICTIONARY or str(event.get("eventId", "")) != event_id:
				continue
			event["points"] = int(update.get("points", event.get("points", 0)))
			var claimed_indexes: Array = update.get("autoMilestonesClaimed", [])
			for milestone in event.get("milestones", []):
				if typeof(milestone) == TYPE_DICTIONARY and claimed_indexes.has(int(milestone.get("index", -1))):
					milestone["claimed"] = true
					milestone["autoClaimed"] = true

func _apply_team_event_progress(progress_events: Array) -> void:
	var team_events: Array = state.get("teamEvents", [])
	for update in progress_events:
		if typeof(update) != TYPE_DICTIONARY:
			continue
		var event_id := str(update.get("eventId", ""))
		for event in team_events:
			if typeof(event) != TYPE_DICTIONARY or str(event.get("eventId", "")) != event_id:
				continue
			event["teamPoints"] = int(update.get("teamPoints", event.get("teamPoints", 0)))
			event["contributionPoints"] = int(update.get("contributionPoints", event.get("contributionPoints", 0)))

func _apply_achievement_progress(progress_achievements: Array) -> void:
	var achievements: Array = state.get("achievements", [])
	for update in progress_achievements:
		if typeof(update) != TYPE_DICTIONARY:
			continue
		var achievement_id := str(update.get("achievementId", ""))
		for achievement in achievements:
			if typeof(achievement) == TYPE_DICTIONARY and str(achievement.get("achievementId", "")) == achievement_id:
				achievement["progress"] = int(update.get("progress", achievement.get("progress", 0)))

## Applique les champs communs d'une mutation puis fusionne les collections.
func apply_mutation(d: Dictionary) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	for key in ["spins", "credits", "nextSpinAtMs", "districtIndex", "districtProgress", "districtDamage", "firewallCharges", "firewallMax", "pendingEncounter", "profile", "progression", "globalProgression", "cards", "chests", "missions", "achievements", "entitlements", "events", "teamEvents", "seasons", "dailyStreak", "dailyAvailable"]:
		if d.has(key):
			state["progression" if key == "globalProgression" else key] = d[key]
	if d.has("serverTimeMs"):
		set_clock(int(d["serverTimeMs"]))
	state_changed.emit()

func district_level(district_id: int, element_id: int) -> int:
	for row in state.get("districtProgress", []):
		if typeof(row) == TYPE_DICTIONARY and int(row.get("districtId", 0)) == district_id and int(row.get("elementId", 0)) == element_id:
			return int(row.get("level", 0))
	return 0

func district_damaged(district_id: int, element_id: int) -> bool:
	for row in state.get("districtDamage", []):
		if typeof(row) == TYPE_DICTIONARY and int(row.get("districtId", 0)) == district_id and int(row.get("elementId", 0)) == element_id:
			return true
	return false

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

func apply_insufficient_spins(available: int, next_ms: int) -> void:
	state["spins"] = maxi(0, available)
	if next_ms > 0:
		state["nextSpinAtMs"] = next_ms
	state_changed.emit()
	if available <= 0:
		no_spins.emit(next_ms)

func reset_session() -> void:
	state = {}
	clock_offset_ms = 0

func spins() -> int:
	return int(state.get("spins", 0))

func credits() -> int:
	return int(state.get("credits", 0))
