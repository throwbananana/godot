extends SceneTree

## 激光光束的绘制位置回归测试。
##
## 覆盖的 bug: _spawn_laser_visual() 用的是 beam_spr.position (局部坐标), 而传进来
## 的 start/end 是全局坐标。激光的父节点是 ActorsContainer, 它挂在 GameArea 下,
## 而 GameArea 在 main.tscn 里 position = Vector2(48, 48) —— 于是光束被整体平移了
## 一整格 (48,48)。伤害判定走的是全局坐标的射线, 所以完全正确, 只有画面偏了:
## 枪口闪光和冲击波 (都经 VFXAnimator, 用 global_position) 在正确位置, 光束却
## 差一格。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_laser_origin.gd

const LaserPiercer = preload("res://scripts/laser_piercer.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> LASER ORIGIN REGRESSION TEST <<<")
	print("==================================================")

	# 复刻 main.tscn 的层级: GameArea 偏移 (48,48), 演员挂在它下面
	var game_area := Node2D.new()
	game_area.position = Vector2(48, 48)
	root.add_child(game_area)
	var actors := Node2D.new()
	game_area.add_child(actors)

	var shooter := Node2D.new()
	actors.add_child(shooter)
	shooter.global_position = Vector2(200, 300)

	var start := Vector2(226, 300)          # 枪口 = 中心 + 朝向 * 26
	var dir := Vector2.RIGHT

	# 等一帧: _init() 里刚 add_child 的节点当帧还没真正入树,
	# fire_linear_laser 第一件事就是 get_world_2d(), 那时会拿到 null。
	await process_frame
	LaserPiercer.fire_linear_laser(actors, start, dir, shooter, "enemy", 2)
	await process_frame

	var beam: Sprite2D = null
	for c in actors.get_children():
		if c is Sprite2D:
			beam = c
			break

	if beam == null:
		fail("没有生成光束精灵")
		_finish()
		return
	ok("光束精灵已生成")

	# 光束是居中精灵, 长度沿局部 Y。它的中心必须落在 起点与终点的中点 上,
	# 而且必须是*全局*中点 —— 这正是老 bug 差掉的那一格。
	var half_len: float = beam.texture.get_height() * beam.scale.y * 0.5
	var beam_start: Vector2 = beam.global_position - dir * half_len
	var offset: float = beam_start.distance_to(start)

	print("  枪口(全局) %s, 光束端点(全局) %s, 偏差 %.1fpx"
		% [str(start), str(beam_start), offset])

	if offset > 4.0:
		fail("光束起点偏离枪口 %.1fpx —— 48px 左右说明用了局部坐标而非全局" % offset)
	else:
		ok("光束起点与枪口对齐 (偏差 %.1fpx)" % offset)

	# 父节点没有偏移时也必须正确 —— 防止有人"修复"成硬减一个 (48,48)
	var flat := Node2D.new()
	root.add_child(flat)
	var shooter2 := Node2D.new()
	flat.add_child(shooter2)
	shooter2.global_position = Vector2(100, 100)
	await process_frame
	LaserPiercer.fire_linear_laser(flat, Vector2(126, 100), Vector2.RIGHT, shooter2, "enemy", 2)
	await process_frame

	var beam2: Sprite2D = null
	for c in flat.get_children():
		if c is Sprite2D:
			beam2 = c
			break
	if beam2 == null:
		fail("父节点无偏移时没有生成光束")
	else:
		var hl2: float = beam2.texture.get_height() * beam2.scale.y * 0.5
		var off2: float = (beam2.global_position - Vector2.RIGHT * hl2).distance_to(Vector2(126, 100))
		if off2 > 4.0:
			fail("父节点无偏移时光束仍差 %.1fpx" % off2)
		else:
			ok("父节点无偏移时同样对齐 (偏差 %.1fpx)" % off2)

	_finish()


func _finish() -> void:
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL LASER ORIGIN CHECKS PASSED! <<<")
		quit(0)
