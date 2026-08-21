extends SceneTree

func _init() -> void:
	print("=== Validating All Scripts and Scenes in Project ===")
	call_deferred("_validate_all")

func _validate_all() -> void:
	var errors = 0

	# 1. Validate all scripts
	var scripts = _get_files_recursive("res://scripts", "gd")
	scripts.append_array(_get_files_recursive("res://tools", "gd"))
	for s_path in scripts:
		var script_res = load(s_path)
		if not script_res:
			print("❌ Error loading script: ", s_path)
			errors += 1
		else:
			print("✓ Script OK: ", s_path)

	# 2. Validate all scenes
	var scenes = _get_files_recursive("res://scenes", "tscn")
	for sc_path in scenes:
		var scene_res = load(sc_path)
		if not scene_res:
			print("❌ Error loading scene: ", sc_path)
			errors += 1
		else:
			print("✓ Scene OK: ", sc_path)
			# Test instantiating
			var inst = scene_res.instantiate()
			if not inst:
				print("❌ Error instantiating scene: ", sc_path)
				errors += 1
			else:
				inst.free()

	print("\nValidation finished. Total Errors: %d" % errors)
	if errors > 0:
		quit(1)
	else:
		print("🎉 All scripts and scenes compiled and instantiated cleanly! 🎉")
		quit(0)

func _get_files_recursive(dir_path: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	var dir = DirAccess.open(dir_path)
	if not dir:
		return result
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			result.append_array(_get_files_recursive(dir_path + "/" + file_name, extension))
		elif file_name.ends_with("." + extension):
			result.append(dir_path + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
