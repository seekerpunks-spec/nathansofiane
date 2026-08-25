extends Node
## Net — client HTTP vers le serveur authoritative (Godot 4, nœud HTTPRequest).
##
## Le client est une VUE : il envoie des intentions et affiche l'état renvoyé.
## Il ne calcule jamais un résultat, un solde, une probabilité.
##
## API vérifiée contre la doc officielle Godot 4.7 :
##   request(url: String, custom_headers: PackedStringArray, method: Method, request_data: String)
##   request_raw(url: String, custom_headers: PackedStringArray, method: Method, request_data_raw: PackedByteArray)
##   signal request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)
## Un seul HTTPRequest ne gère qu'UNE requête à la fois → file d'attente interne.

## Serveur (dev desktop). En prod : changer pour l'URL du dApp Store.
const SERVER_HOST := "127.0.0.1"
const SERVER_PORT := 8080

const DEV_ADDRESS := "dev-player-0001"

## Impression des traces réseau (panneau Output). M1 validé (R16) : gate fermée par défaut.
const DEBUG := false

## Timeout REST en secondes (0.0 = jamais).
const REQUEST_TIMEOUT := 15.0

var token: String = ""
var refresh_token: String = ""
var server_url: String = ""

var _http: HTTPRequest
var _request_in_flight := false
signal _request_done
var _refresh_in_flight := false
var _last_refresh_ok := false
signal _refresh_done

func _ready() -> void:
	server_url = OS.get_environment("CYBERSEEKER_API_URL").strip_edges()
	if server_url == "":
		server_url = "http://" + SERVER_HOST + ":" + str(SERVER_PORT)
	server_url = server_url.trim_suffix("/")
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	add_child(_http)

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

## Génère un UUID v4-ish (idempotence).
func request_id() -> String:
	var t := int(Time.get_unix_time_from_system() * 1000)
	var a := "%08x" % (randi() & 0xFFFFFFFF)
	var b := "%04x" % (randi() & 0xFFFF)
	var c := "%04x" % (randi() & 0xFFFF)
	var d := "%04x" % (randi() & 0xFFFF)
	return "%d-%s-%s-%s-%s" % [t, a, b, c, d]

## Parse JSON robuste.
func parse_json(text: String) -> Variant:
	if text == "":
		return null
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.get_data()

## Construit l'URL complète.
func _url(path: String) -> String:
	return server_url + path

func is_dev_mode() -> bool:
	return OS.has_feature("editor") or OS.has_feature("debug")

# ---------------------------------------------------------------------------
# Tokens
# ---------------------------------------------------------------------------

func store_token(access_token: String, refresh: String) -> void:
	token = access_token
	refresh_token = refresh

func has_token() -> bool:
	return token != ""

func clear_session() -> void:
	token = ""
	refresh_token = ""
	_last_refresh_ok = false

## Révoque le refresh courant puis purge toujours la session locale. Le client
## ne reste jamais connecté parce que le réseau est indisponible au logout.
func logout() -> bool:
	if _refresh_in_flight:
		await _refresh_done
	var token_to_revoke := refresh_token
	var revoked := true
	if token_to_revoke != "":
		var r := await request("POST", "/auth/logout", { "refreshToken": token_to_revoke }, false, "")
		revoked = r.ok
	clear_session()
	return revoked

# ---------------------------------------------------------------------------
# Cœur réseau — file d'attente (1 requête à la fois)
# ---------------------------------------------------------------------------

## Enfile une requête et attend sa réponse.
## Retour : { result: int (HTTPRequest.RESULT_*), code: int, body: String }
func _queue_request(url: String, headers: PackedStringArray, method: int, body_bytes: PackedByteArray) -> Dictionary:
	while _request_in_flight:
		# Une requête est en cours : on attend qu'elle finisse.
		await _request_done
	_request_in_flight = true
	var err: int = _http.request_raw(url, headers, method, body_bytes)
	if err != OK:
		_request_in_flight = false
		_request_done.emit()
		return { "result": -1, "code": 0, "body": "" }
	var args: Array = await _http.request_completed
	_request_in_flight = false
	_request_done.emit()
	# args = [result, response_code, headers, body]
	return {
		"result": int(args[0]),
		"code": int(args[1]),
		"body": (args[3] as PackedByteArray).get_string_from_utf8(),
	}

# ---------------------------------------------------------------------------
# Requêtes (coroutines — à appeler avec await)
# ---------------------------------------------------------------------------

## Retour : { ok: bool, code: int, data: Variant, error: String }
func request(
	method: String,
	path: String,
	body: Dictionary = {},
	use_auth: bool = true,
	request_id_override: String = ""
) -> Dictionary:
	var headers := PackedStringArray(["accept: application/json"])
	var http_method: int = HTTPClient.METHOD_GET
	var body_bytes := PackedByteArray()

	if method != "GET":
		http_method = HTTPClient.METHOD_POST
		headers.append("content-type: application/json")
		body_bytes = JSON.stringify(body).to_utf8_buffer()
	if use_auth and token != "":
		headers.append("authorization: Bearer " + token)
	if request_id_override != "":
		headers.append("x-request-id: " + request_id_override)

	var r := await _queue_request(_url(path), headers, http_method, body_bytes)
	var http_code: int = r.code
	var error_code: int = r.result
	var body_text: String = r.body

	if error_code != HTTPRequest.RESULT_SUCCESS:
		if DEBUG:
			print("[NET] %s %s -> ERREUR %d (code HTTP %d)" % [method, path, error_code, http_code])
		return { "ok": false, "code": http_code, "data": null, "error": "net_error: %d" % error_code }

	if DEBUG:
		print("[NET] %s %s -> %d (%d octets)" % [method, path, http_code, body_text.length()])
	var data = parse_json(body_text)
	var ok := http_code >= 200 and http_code < 300
	return { "ok": ok, "code": http_code, "data": data, "error": "" if ok else body_text }

## GET simplifié (renommé fetch pour éviter la collision avec Object.get()).
func fetch(path: String, use_auth: bool = true) -> Dictionary:
	return await request("GET", path, {}, use_auth, "")

func post(path: String, body: Dictionary = {}, use_auth: bool = true, rid: String = "") -> Dictionary:
	return await request("POST", path, body, use_auth, rid)

## Échange un refresh token contre un nouveau pair.
func refresh() -> bool:
	if _refresh_in_flight:
		await _refresh_done
		return _last_refresh_ok
	if refresh_token == "":
		return false
	_refresh_in_flight = true
	var token_to_rotate := refresh_token
	var r := await request("POST", "/auth/refresh", { "refreshToken": token_to_rotate }, false, "")
	if r.ok and typeof(r.data) == TYPE_DICTIONARY and r.data.has("token"):
		store_token(r.data["token"], r.data.get("refreshToken", ""))
		_last_refresh_ok = true
	else:
		_last_refresh_ok = false
	_refresh_in_flight = false
	_refresh_done.emit()
	return _last_refresh_ok

## Appel protégé avec rejeu unique après 401.
func protected_request(
	method: String,
	path: String,
	body: Dictionary = {},
	rid: String = ""
) -> Dictionary:
	var access_token_used := token
	var res := await request(method, path, body, true, rid)
	# GET et mutations idempotentes peuvent être rejoués une fois après un
	# transport interrompu. Les POST sans request-id ne sont jamais rejoués.
	if res.code == 0 and (method == "GET" or rid != ""):
		await get_tree().create_timer(0.35).timeout
		res = await request(method, path, body, true, rid)
	if res.code == 401 and refresh_token != "":
		# Une autre coroutine peut avoir déjà renouvelé la session pendant que
		# cette requête attendait la file HTTP. Dans ce cas, rejouer avec le token
		# actuel évite de faire tourner inutilement le nouveau refresh.
		var session_ready := token != access_token_used
		if not session_ready:
			session_ready = await refresh()
		if session_ready:
			res = await request(method, path, body, true, rid)
	return res

# ---------------------------------------------------------------------------
# Cycle de vie
# ---------------------------------------------------------------------------

## Annule la requête en cours (changement de scène, perte de session).
func reset() -> void:
	if _http != null:
		_http.cancel_request()
