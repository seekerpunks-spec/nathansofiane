extends SceneTree
## WebP quality 96 format conversion; no resizing, compositing or alpha removal.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected source PNG and destination WebP")
		quit(1)
		return
	var source := Image.load_from_file(args[0])
	if source == null:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[1].get_base_dir())
	var result := source.save_webp(args[1], true, 0.96)
	print("ART_IMPORT: ", args[1], " alpha=", source.detect_alpha(), " error=", result)
	quit(0 if result == OK else 1)
