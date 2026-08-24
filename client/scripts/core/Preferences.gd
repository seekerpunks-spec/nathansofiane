extends Node
## Préférences locales non économiques.

const PATH := "user://preferences.cfg"
var sound_enabled := true
var haptics_enabled := true
var reduced_motion := false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sound_enabled = bool(cfg.get_value("accessibility", "sound", true))
	haptics_enabled = bool(cfg.get_value("accessibility", "haptics", true))
	reduced_motion = bool(cfg.get_value("accessibility", "reduced_motion", false))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("accessibility", "sound", sound_enabled)
	cfg.set_value("accessibility", "haptics", haptics_enabled)
	cfg.set_value("accessibility", "reduced_motion", reduced_motion)
	cfg.save(PATH)
