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
		# load() 对一个**有语法错误**的脚本仍然会返回一个 GDScript 对象
		# (只是打一堆 Parse Error 到控制台), 所以只判 `if not script_res`
		# 是拦不住的 —— 实测过: pipe_conduit.gd 报了 10 条 Parse Error,
		# 而这个闸门输出 "Total Errors: 0"。一个叫"验证全部脚本能编译"的
		# 闸门放行编译不过的脚本, 比没有闸门更危险。
		#
		# 解析失败的脚本: can_instantiate() 为 false 且 get_instance_base_type()
		# 为空串; 正常脚本两者都有值。
		elif script_res is GDScript and str(script_res.get_instance_base_type()).is_empty():
			print("❌ 脚本有语法错误 (上面的 Parse Error 就是它的): ", s_path)
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

	errors += _validate_scene_references()

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


## 每一个 res:// 路径引用都得真的存在。
##
## 这条是照着一个真实踩过的坑写的: 删掉 spire_map.tscn 之后,
## main.gd::_on_button_action() 里还留着 change_scene_to_file("res://scenes/
## spire_map.tscn")。Godot 在目标文件不存在时**只打一条错误日志然后什么都不做**
## —— 不抛异常、不崩溃、编译也不报。表现是玩家打完 boss 永远卡在结算界面上。
## 整套测试全绿, 因为没有任何一个测试去按那个按钮。
##
## 正则扫源码而不是跑流程: 场景跳转散在胜利/失败/暂停/标题屏各种分支里, 靠测试
## 逐条走到不现实; 而"字符串里写的路径存不存在"是静态就能答的。
func _validate_scene_references() -> int:
	print("\n=== Validating res:// path references ===")
	var bad := 0
	var checked := 0
	var files := _get_files_recursive("res://scripts", "gd")
	files.append_array(_get_files_recursive("res://tools", "gd"))

	var re := RegEx.new()
	re.compile('"(res://[^"]+\\.(tscn|gd))"')

	for f in files:
		var fa := FileAccess.open(f, FileAccess.READ)
		if not fa:
			continue
		var text := fa.get_as_text()
		fa.close()
		# 跳过两类行:
		#   - 注释。注释里提到已删场景的名字是正常的历史记录。
		#   - 自带 ResourceLoader.exists() 守卫的行。那是"这个资源可能不在"的
		#     惯用写法 (配一个 fallback), 是有意为之而不是悬空引用 ——
		#     test_roller_wall_and_stage2_destruction.gd 就是这么用的。
		for line in text.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if line.contains("ResourceLoader.exists("):
				continue
			for m in re.search_all(line):
				var path := m.get_string(1)
				checked += 1
				if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
					print("❌ %s 引用了不存在的资源: %s" % [f, path])
					bad += 1

	if bad == 0:
		print("✓ %d 个 res:// 引用全部指向存在的文件" % checked)
	return bad
