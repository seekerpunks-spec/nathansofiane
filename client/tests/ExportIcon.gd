extends SceneTree
## Outil headless : rasterise l'icone projet (SVG importe a 512 px) vers
## export/icons/icon_512.png, base des icones launcher Android composees par
## tools/android_icons/build_icons.py. Exclu de l'export (tests/*).

func _init() -> void:
	var texture: Texture2D = load("res://assets/icon.svg")
	if texture == null:
		push_error("ICON_EXPORT_FAILED: icone introuvable")
		quit(1)
		return
	var img := texture.get_image()
	var err := img.save_png("res://export/icons/icon_512.png")
	if err != OK:
		push_error("ICON_EXPORT_FAILED: save_png err=%d" % err)
		quit(1)
		return
	print("ICON_EXPORT_OK %dx%d" % [img.get_width(), img.get_height()])
	quit(0)
