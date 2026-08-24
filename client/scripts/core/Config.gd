extends Node
## Config — remote config versionnée (ARCH §5).
##
## Le client la télécharge au lancement via GET /config, en garde le hash,
## et la compare aux mises à jour (live-ops). Aucune valeur économique n'est
## en dur dans le code : tout se lit ici (GDD §40).

var version: String = ""
var hash: String = ""
var raw: Dictionary = {}
var from_cache := false
const CACHE_PATH := "user://remote_config.json"

# Vue typée du spin table (M1 : outcomes credits/none ; chest/card en M3).
var _outcomes: Array = []
var _index_by_id: Dictionary = {}

# ---------------------------------------------------------------------------
## Charge la config distante. Retourne true si OK.
func load_remote() -> bool:
	var r := await Net.request("GET", "/config", {}, false, "")
	if not r.ok or typeof(r.data) != TYPE_DICTIONARY:
		return _load_cached()
	from_cache = false
	version = str(r.data.get("version", ""))
	hash = str(r.data.get("hash", ""))
	raw = r.data.get("payload", {})
	_index_outcomes()
	_save_cache(r.data)
	return true

func _save_cache(data: Dictionary) -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))

func _load_cached() -> bool:
	if not FileAccess.file_exists(CACHE_PATH):
		return false
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	version = str(data.get("version", ""))
	hash = str(data.get("hash", ""))
	raw = data.get("payload", {})
	from_cache = true
	_index_outcomes()
	return not raw.is_empty()

func _index_outcomes() -> void:
	_outcomes.clear()
	_index_by_id.clear()
	var st: Variant = raw.get("spinTable", {})
	if typeof(st) == TYPE_DICTIONARY:
		var outcomes: Variant = st.get("outcomes", [])
		if typeof(outcomes) == TYPE_ARRAY:
			for o in outcomes:
				_outcomes.append(o)
				if typeof(o) == TYPE_DICTIONARY and o.has("id"):
					_index_by_id[o["id"]] = _outcomes.size() - 1

func outcomes() -> Array:
	return _outcomes

## Index (segment de la roue) d'un outcome par son id ; -1 si inconnu.
func outcome_index(id: String) -> int:
	if _index_by_id.has(id):
		return _index_by_id[id]
	return -1

func economy() -> Dictionary:
	return raw.get("economy", {})

func social() -> Dictionary:
	return raw.get("social", {})

func progression() -> Dictionary:
	return raw.get("progression", {})

func spin_multipliers() -> Array:
	var configured: Variant = economy().get("spinMultipliers", [1])
	return configured if typeof(configured) == TYPE_ARRAY else [1]

func districts() -> Array:
	return raw.get("districts", [])

func cards() -> Array:
	return raw.get("cards", [])

func sets() -> Array:
	return raw.get("sets", [])

func chests() -> Array:
	return raw.get("chests", [])

func events() -> Array:
	return raw.get("events", [])

func offers() -> Array:
	return raw.get("offers", [])

func seasons() -> Array:
	return raw.get("seasons", [])

func daily() -> Dictionary:
	return raw.get("daily", {})

func entitlements() -> Array:
	return raw.get("entitlements", [])
