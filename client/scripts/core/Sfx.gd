extends Node
## Sfx — synthèse audio procédurale (AudioStreamWAV généré en code).
##
## M1 : aucun asset audio requis. Les sons courts (< 400 ms) sont générés à
## la volée (sinus/carré/scie) et échelonnés par rareté du résultat (ARCH §3.3).

var _pool: Array = []
var _idx: int = 0

const _RATE := 22050

func _ready() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = 0.0
		add_child(p)
		_pool.append(p)

func _pick() -> AudioStreamPlayer:
	_idx = (_idx + 1) % _pool.size()
	return _pool[_idx]

## Génère un stream à partir de segments [freq, dur_s, shape(0/1/2), vol].
func _make_stream(segments: Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	for seg in segments:
		var freq: float = float(seg[0])
		var dur: float = float(seg[1])
		var shape: int = int(seg[2])
		var vol: float = float(seg[3])
		var n := int(_RATE * dur)
		for i in n:
			var t := float(i) / float(_RATE)
			var s := 0.0
			match shape:
				1:
					s = 1.0 if sin(TAU * freq * t) >= 0.0 else -1.0
				2:
					s = 2.0 * (freq * t - floor(0.5 * freq * t)) - 1.0
				_:
					s = sin(TAU * freq * t)
			# Enveloppe : attaque 2 ms + décroissance linéaire.
			var env := clampf(float(i) / (_RATE * 0.002), 0.0, 1.0)
			env *= (1.0 - float(i) / float(n))
			var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
			bytes.append(v & 0xFF)
			bytes.append((v >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _RATE
	stream.stereo = false
	stream.data = bytes
	return stream

func _play(segments: Array) -> void:
	if not Preferences.sound_enabled:
		return
	var p := _pick()
	p.stream = _make_stream(segments)
	p.play()

# ---------------------------------------------------------------------------
# Sons du jeu
# ---------------------------------------------------------------------------

func coin() -> void:
	_play([[980, 0.03, 0, 0.22], [1320, 0.05, 0, 0.18]])

func upgrade() -> void:
	_play([[190, 0.05, 1, 0.30], [340, 0.06, 0, 0.28], [520, 0.08, 0, 0.22]])

func click() -> void:
	_play([[700, 0.05, 0, 0.35]])

func tick() -> void:
	_play([[1100, 0.02, 0, 0.18]])

func start() -> void:
	_play([[320, 0.06, 2, 0.25], [440, 0.06, 2, 0.25]])

func stop() -> void:
	_play([[240, 0.05, 1, 0.3], [180, 0.06, 1, 0.3]])

## Démarrage mécanique des trois rouleaux : moteur grave, puis montée nette.
func reel_start() -> void:
	_play([
		[170, 0.05, 2, 0.22], [235, 0.05, 2, 0.25],
		[330, 0.06, 0, 0.27], [460, 0.07, 0, 0.24],
	])

## Claquement d'arrêt individualisé : chaque rouleau monte légèrement en hauteur.
func reel_stop(index: int) -> void:
	var base := 330.0 + float(index) * 75.0
	_play([[base, 0.035, 1, 0.30], [base * 0.58, 0.065, 0, 0.26]])

## Montée de tension avant le dernier rouleau sur les gros gains.
func anticipation() -> void:
	_play([
		[520, 0.045, 0, 0.30], [650, 0.045, 0, 0.32],
		[790, 0.05, 0, 0.34], [980, 0.09, 2, 0.22],
	])

## Impact final de la machine quand la ligne est complètement verrouillée.
func reel_finish() -> void:
	_play([[190, 0.04, 1, 0.30], [122, 0.07, 1, 0.24]])

## Fanfare jackpot distincte du simple son de rareté.
func jackpot() -> void:
	_play([
		[392, 0.065, 0, 0.38], [523, 0.065, 0, 0.40],
		[659, 0.065, 0, 0.42], [784, 0.08, 0, 0.44],
		[1047, 0.16, 0, 0.48], [1568, 0.12, 2, 0.16],
	])

func error() -> void:
	_play([[150, 0.12, 1, 0.35]])

## Son du résultat, échelonné par rareté (ARCH §3.3).
func result(tier: String) -> void:
	match tier.to_lower():
		"rare":
			_play([[660, 0.07, 0, 0.4], [880, 0.09, 0, 0.4]])
		"epic":
			_play([[440, 0.06, 0, 0.45], [660, 0.06, 0, 0.45], [880, 0.10, 0, 0.45]])
		"legendary":
			_play([
				[523, 0.08, 0, 0.5], [659, 0.08, 0, 0.5], [784, 0.08, 0, 0.5],
				[1047, 0.18, 0, 0.55], [1047, 0.10, 2, 0.2],
			])
		"glitch", "none":
			_play([[210, 0.10, 2, 0.35], [196, 0.10, 2, 0.35]])
		_:
			_play([[520, 0.06, 0, 0.35]])
