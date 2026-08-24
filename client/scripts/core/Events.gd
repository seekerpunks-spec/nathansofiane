extends Node
## Events — analytics batché (GDD §41, ARCH §4.1).
##
## Tampon côté client : flush à 10 événements, toutes les 15 s, et à la
## fermeture. Cap 100 ; en cas d'échec, le batch est conservé (re-queue).
## Horloge SERVEUR (le serveur ignore toute date client — GDD §39).

const FLUSH_BATCH := 10
const FLUSH_INTERVAL_S := 15.0
const MAX_BUFFER := 100

var _buffer: Array = []
var _timer: Timer
var _flushing: bool = false
var _active_batch_id := ""
var _active_batch_size := 0

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = FLUSH_INTERVAL_S
	_timer.one_shot = false
	_timer.timeout.connect(_flush.bind())
	add_child(_timer)
	_timer.start()

## Track un événement. `props` est un dictionnaire libre.
func track(name: String, props: Dictionary = {}) -> void:
	_buffer.append({ "name": name, "props": props })
	if _buffer.size() > MAX_BUFFER:
		_buffer = _buffer.slice(_buffer.size() - MAX_BUFFER)
	if _buffer.size() >= FLUSH_BATCH:
		_flush.call()

func _flush() -> void:
	if _flushing:
		return  # un flush est déjà en cours (évite le double-claim du buffer)
	if _buffer.is_empty():
		return
	if not Net.has_token():
		return
	_flushing = true
	if _active_batch_id == "":
		_active_batch_id = Net.request_id()
		_active_batch_size = min(_buffer.size(), 100)
	var batch := _buffer.slice(0, _active_batch_size)
	var r := await Net.post("/analytics", { "batchId": _active_batch_id, "events": batch }, true, _active_batch_id)
	if r.ok:
		_buffer = _buffer.slice(batch.size())
		_active_batch_id = ""
		_active_batch_size = 0
	_flushing = false
	# Sinon : on garde le buffer (re-queue), nouvel essai au prochain flush.

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _buffer.is_empty() and Net.has_token():
			if _active_batch_id == "":
				_active_batch_id = Net.request_id()
				_active_batch_size = min(_buffer.size(), 100)
			var batch := _buffer.slice(0, _active_batch_size)
			Net.post("/analytics", { "batchId": _active_batch_id, "events": batch }, true, _active_batch_id)
