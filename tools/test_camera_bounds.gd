extends SceneTree

const GameState = preload("res://scripts/game_state.gd")

## RoomCamera (第一次给这个项目加摄像机) 的数学验收。
##
## 目标是证明两件事:
##  1. 普通 13x13 房间下, 摄像机的 offset/position 组合复现的屏幕坐标跟
##     "改造前直接挪 GameArea.position" 逐像素一致 -- 也就是"视角视野还是
##     原来的大小"的字面验证, 不是靠肉眼截图去看。
##  2. 26x26 (large)/52x52 (huge) 房间下, 摄像机跟随目标点永远被夹在
##     [visible/2, room_size-visible/2] 区间内, 不会露出房间边界外的虚空,
##     也不会出现 NaN/越界。
##
## 这个测试只摸 main.gd 已经是 var 的 GRID_W/GRID_H 和摄像机相关的几个新
## 函数, 不依赖 Stage 1/2 的房间图/合成关卡逻辑 -- 那些留给
## test_composite_room_builder.gd 和 test_room_flow.gd 里新增的大房间用例。

const EPS := 0.5

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> ROOM CAMERA BOUNDS TEST <<<")
	print("==================================================")

	GameState.reset_campaign(1)
	var main_inst = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame
	await process_frame

	_test_normal_room_pixel_identical(main_inst)
	_test_clamp_axis_formula(main_inst)
	await _test_large_room_clamp(main_inst, 26)
	await _test_large_room_clamp(main_inst, 52)

	main_inst.queue_free()
	await process_frame

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL CAMERA BOUNDS CHECKS PASSED! <<<")
		quit(0)


## 普通 13x13 房间: 摄像机必须钉在房间正中心, 且对任意本地点 L 算出来的
## 屏幕坐标要等于改造前的 base_game_area_pos + L (这是 _update_camera_bounds()
## 那条推导要证明的东西)。
func _test_normal_room_pixel_identical(main_inst) -> void:
	print("\n--- 普通房间: 逐像素一致 ---")
	main_inst.GRID_W = 13
	main_inst.GRID_H = 13
	main_inst._update_camera_bounds()

	var expected_center: Vector2 = Vector2(6.5, 6.5) * main_inst.TILE_SIZE
	if not main_inst.room_camera.position.is_equal_approx(expected_center):
		fail("13x13 房间摄像机应钉在 %s, 实际 %s" % [str(expected_center), str(main_inst.room_camera.position)])
	else:
		ok("13x13 摄像机钉在房间中心 %s" % str(expected_center))

	var vp: Vector2 = main_inst.get_viewport_rect().size
	var base: Vector2 = main_inst.base_game_area_pos
	var samples: Array[Vector2] = [Vector2.ZERO, Vector2(624.0, 624.0), Vector2(312.0, 100.0)]
	var bad := 0
	for l in samples:
		var screen: Vector2 = vp / 2.0 + l - main_inst.room_camera.position - main_inst.room_camera.offset
		var expected: Vector2 = base + l
		if screen.distance_to(expected) > EPS:
			bad += 1
			fail("本地点 %s 应映射到屏幕 %s, 实际算出 %s" % [str(l), str(expected), str(screen)])
	if bad == 0:
		ok("%d 个采样点的屏幕坐标跟改造前公式 (base_game_area_pos + L) 完全一致" % samples.size())


## _camera_clamp_axis 本身的边界值检查, 不依赖场景状态。
func _test_clamp_axis_formula(main_inst) -> void:
	print("\n--- _camera_clamp_axis 边界值 ---")
	var visible := 688.0
	# 房间比可视区小或相等: 钉死在房间中心, 不跟随。
	var pinned: float = main_inst._camera_clamp_axis(9999.0, 624.0, visible)
	if not is_equal_approx(pinned, 312.0):
		fail("房间(624)小于可视区(688)时应钉在 312, 实际 %s" % str(pinned))
	else:
		ok("房间小于可视区时摄像机钉死不动: %s" % str(pinned))

	# 房间比可视区大: 目标落在合法范围内时原样返回。
	var mid: float = main_inst._camera_clamp_axis(600.0, 1248.0, visible)
	if not is_equal_approx(mid, 600.0):
		fail("目标在合法范围内时不该被夹, 应为 600, 实际 %s" % str(mid))
	else:
		ok("合法范围内的目标原样返回: %s" % str(mid))

	# 目标超出房间左/上边界: 夹到 visible/2。
	var lo: float = main_inst._camera_clamp_axis(-500.0, 1248.0, visible)
	if not is_equal_approx(lo, visible / 2.0):
		fail("目标越过左边界时应夹到 %s, 实际 %s" % [str(visible / 2.0), str(lo)])
	else:
		ok("越过左边界被夹到 %s" % str(lo))

	# 目标超出房间右/下边界: 夹到 room_size - visible/2。
	var hi: float = main_inst._camera_clamp_axis(9999.0, 1248.0, visible)
	var expected_hi := 1248.0 - visible / 2.0
	if not is_equal_approx(hi, expected_hi):
		fail("目标越过右边界时应夹到 %s, 实际 %s" % [str(expected_hi), str(hi)])
	else:
		ok("越过右边界被夹到 %s" % str(hi))


## 大/超大房间: 把玩家逐一传送到四角, 摄像机永远不能滚出房间边界。
func _test_large_room_clamp(main_inst, size: int) -> void:
	print("\n--- %dx%d 房间: 摄像机跟随夹在边界内 ---" % [size, size])
	main_inst.GRID_W = size
	main_inst.GRID_H = size
	main_inst._update_camera_bounds()

	if main_inst.p1_instance == null or not is_instance_valid(main_inst.p1_instance):
		fail("场景里没有 p1_instance, 没法驱动摄像机跟随测试")
		return

	var room_px: float = float(size) * main_inst.TILE_SIZE
	var corners: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(room_px, 0.0),
		Vector2(0.0, room_px),
		Vector2(room_px, room_px),
	]
	var vis: Vector2 = main_inst.CAMERA_VISIBLE_SIZE
	var bad := 0
	for corner in corners:
		main_inst.p1_instance.global_position = main_inst.map_container.to_global(corner)
		await process_frame
		var cam: Vector2 = main_inst.room_camera.position
		var lo_x: float = vis.x / 2.0
		var hi_x: float = room_px - vis.x / 2.0
		var lo_y: float = vis.y / 2.0
		var hi_y: float = room_px - vis.y / 2.0
		if is_nan(cam.x) or is_nan(cam.y):
			bad += 1
			fail("玩家在角落 %s 时摄像机出现 NaN: %s" % [str(corner), str(cam)])
			continue
		if cam.x < lo_x - EPS or cam.x > hi_x + EPS or cam.y < lo_y - EPS or cam.y > hi_y + EPS:
			bad += 1
			fail("玩家在角落 %s 时摄像机 %s 越出允许范围 x[%.1f,%.1f] y[%.1f,%.1f]"
				% [str(corner), str(cam), lo_x, hi_x, lo_y, hi_y])
	if bad == 0:
		ok("%d 个角落测试全部通过, 摄像机始终夹在房间边界内" % corners.size())
