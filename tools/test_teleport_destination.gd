extends SceneTree

## 传送落点必须真的落在空地上。
##
## 覆盖的 bug: get_random_empty_tile_position() 用 (c+0.5)*TILE_SIZE 算出的是
## map_container 的**局部**坐标, 但 wormhole.gd 把它直接赋给了 body.global_position。
## GameArea 在 main.tscn 里 position = Vector2(48,48), 于是落点整整偏了一格到
## 左上 —— 这个函数精挑细选的空地, 单位却被放到它左上角那一格, 而那一格完全
## 可能是砖墙或水。
##
## 这里断言的是最终的不变式, 而不是"函数返回了什么数": 把返回值当全局坐标换算
## 回网格下标, 那一格在 layout 里必须是 0。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_teleport_destination.gd

const SAMPLES := 200

var failures: int = 0


func _init() -> void:
	print("==================================================")
	print(">>> TELEPORT DESTINATION REGRESSION TEST <<<")
	print("==================================================")

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		print("[FAIL] 加载不了 main.tscn")
		quit(1)
		return
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if not main.has_method("get_random_empty_tile_position"):
		print("[FAIL] main 没有 get_random_empty_tile_position()")
		quit(1)
		return

	var layout = main.current_map_layout
	if layout == null or layout.size() == 0:
		print("[FAIL] 地图布局为空, 无法验证")
		quit(1)
		return

	var tile_size: float = main.TILE_SIZE
	var map_container: Node2D = main.map_container
	var bad := {}
	var checked := 0

	for i in range(SAMPLES):
		var g: Vector2 = main.get_random_empty_tile_position()
		# 当作全局坐标换算回网格 —— 这正是 wormhole.gd 的用法
		var local: Vector2 = map_container.to_local(g)
		var c := int(floor(local.x / tile_size))
		var r := int(floor(local.y / tile_size))
		checked += 1
		if r < 0 or r >= layout.size() or c < 0 or c >= layout[r].size():
			bad["越界(%d,%d)" % [r, c]] = bad.get("越界(%d,%d)" % [r, c], 0) + 1
			continue
		var t: int = layout[r][c]
		if t != 0:
			var k := "地块类型 %d" % t
			bad[k] = bad.get(k, 0) + 1

	if bad.is_empty():
		print("  [ok] %d 次取样全部落在空地 (layout == 0) 上" % checked)
	else:
		failures += 1
		print("[FAIL] %d 次取样中有落点不是空地:" % checked)
		for k in bad.keys():
			print("         %s  x%d" % [k, bad[k]])

	# 顺带确认返回的确实是全局坐标而不是局部 —— 两者差 GameArea 的偏移
	var probe: Vector2 = main.get_random_empty_tile_position()
	var as_local: Vector2 = map_container.to_local(probe)
	if probe.is_equal_approx(as_local) and map_container.global_position.length() > 0.5:
		failures += 1
		print("[FAIL] 返回值等于局部坐标, 但容器有偏移 %s —— 契约又退回局部了"
			% str(map_container.global_position))
	else:
		print("  [ok] 返回值是全局坐标 (容器偏移 %s)" % str(map_container.global_position))

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL TELEPORT DESTINATION CHECKS PASSED! <<<")
		quit(0)
