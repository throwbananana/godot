extends SceneTree

## 敌方激光坦克 (EnemyType.LASER) 蓄力预警回归测试。
##
## 覆盖的功能: 原来 LASER 一到 fire_timer<=0 就顺发光柱, 玩家在光柱出现的那一
## 帧才知道方向, 完全没有反应时间。现在改成 enemy.gd::LASER_CHARGE_TIME 秒的
## 蓄力窗口——停步锁定目标方向、显示一排格数指示器逐格点亮、蓄满才真正开火,
## 方向在蓄力开始时就已经锁定, 跟最终光柱方向一致。
##
## 用失败计数器 + 单次 quit() 收尾, 不用裸 assert() —— 见
## [[assert-on-random-precondition-hangs]]: 裸 assert 在这种被 _init() 顺序
## 调用的子函数里失败只会打 SCRIPT ERROR 然后照常跑完 quit(0), 不会让
## run_tests.ps1 报红。

const EnemyScript = preload("res://scripts/enemy.gd")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func ok(msg: String) -> void:
	print("  [ok] %s" % msg)

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> LASER CHARGE TELEGRAPH TEST <<<")
	print("==================================================")

	await _test_charge_window_shows_indicator_and_locks_aim()
	_test_indicator_hidden_before_charge_window()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL LASER CHARGE TELEGRAPH CHECKS PASSED! <<<")
		quit(0)

func _make_laser_enemy(pos: Vector2, parent: Node2D) -> Node2D:
	var scene = load("res://scenes/enemy.tscn")
	var e = scene.instantiate()
	parent.add_child(e)
	e.enemy_type = EnemyScript.EnemyType.LASER
	e._setup_tank_type()
	e.global_position = pos
	return e

func _test_charge_window_shows_indicator_and_locks_aim() -> void:
	print("\n[STEP 1] Charge window shows the segment indicator, freezes movement, locks aim, then fires...")

	# 独立的 Node2D 父容器, 不是裸 root(Window) —— LaserPiercer.fire_linear_laser()
	# 需要一个 Node2D 父节点来挂光束精灵, 同一坑见
	# tools/test_kinetic_push_and_squeeze.gd 里 _die() 掉金币的那次修复。
	var actors = Node2D.new()
	root.add_child(actors)

	var enemy = _make_laser_enemy(Vector2(400.0, 400.0), actors)

	var player = load("res://scenes/player.tscn").instantiate()
	player.player_id = 1
	actors.add_child(player)
	player.global_position = Vector2(600.0, 400.0) # 敌人正右方

	await process_frame # 让新位置进物理 broadphase, 避免 physics-broadphase-lags-teleport 那个坑
	await process_frame

	# 蓄力窗口开始前一瞬间: fire_timer 刚好卡在 LASER_CHARGE_TIME 之上,
	# 此时指示器不该显示。
	enemy.fire_timer = enemy.LASER_CHARGE_TIME + 0.05
	enemy._physics_process(0.016)
	if is_instance_valid(enemy.laser_charge_container) and enemy.laser_charge_container.visible:
		fail("蓄力窗口开始前指示器就已经显示了")
	else:
		ok("蓄力窗口开始前指示器保持隐藏")

	# 进入蓄力窗口起点: 指示器应该出现, 格数应该还很少(甚至 0), 且坦克锁定
	# 面朝玩家方向 (正右方), 移动速度归零。
	enemy.fire_timer = enemy.LASER_CHARGE_TIME
	enemy.velocity = Vector2(999.0, 0.0) # 故意先设一个非零值, 确认下面真的被清零而不是本来就是零
	enemy._physics_process(0.016)

	if not (is_instance_valid(enemy.laser_charge_container) and enemy.laser_charge_container.visible):
		fail("进入蓄力窗口后指示器应该显示")
	else:
		ok("进入蓄力窗口后指示器已显示")

	if enemy.facing_direction != Vector2.RIGHT:
		fail("蓄力开始时应锁定朝向正右方的玩家, 实际是 %s" % enemy.facing_direction)
	else:
		ok("蓄力开始时正确锁定瞄准方向 (RIGHT)")

	if enemy.velocity != Vector2.ZERO:
		fail("蓄力期间坦克应该停止移动, 实际 velocity=%s" % enemy.velocity)
	else:
		ok("蓄力期间坦克正确停止移动")

	var lit_early = _count_lit_segments(enemy)

	# 推进到蓄力窗口末尾附近 (只剩一点点), 格数应该比刚开始时更多 (单调递增,
	# 不要求具体数字, 只要求"越接近开火, 点亮的格数越多")。
	enemy.fire_timer = 0.05
	enemy._physics_process(0.016)
	var lit_late = _count_lit_segments(enemy)

	if not (lit_late >= lit_early):
		fail("越接近开火, 点亮格数应该不减少, 实际从 %d 变成了 %d" % [lit_early, lit_late])
	else:
		ok("点亮格数随蓄力推进单调不减 (%d -> %d, 满格 %d)" % [lit_early, lit_late, enemy.LASER_CHARGE_SEGMENTS])

	# 方向必须在整个蓄力过程中保持一致 (玩家没有移动), 这样蓄力时看到的格数
	# 指示器方向才是最终光柱真正打出来的方向, 指示器才有意义。
	if enemy.facing_direction != Vector2.RIGHT:
		fail("蓄力接近尾声时朝向不该漂移, 实际是 %s" % enemy.facing_direction)
	else:
		ok("蓄力全程朝向保持锁定 (RIGHT)")

	# 蓄力结束: fire_timer 归零应该真正开火 (LaserPiercer 生成一个 Sprite2D
	# 光束), 且方向必须和蓄力期间锁定的方向一致。
	enemy.fire_timer = 0.0
	var beams_before = _count_beam_sprites(actors)
	enemy._physics_process(0.016)
	await process_frame
	var beams_after = _count_beam_sprites(actors)

	if not (beams_after > beams_before):
		fail("蓄力结束应该真正开火生成光束精灵, 实际光束数量 %d -> %d" % [beams_before, beams_after])
	else:
		ok("蓄力结束正确开火, 光束精灵已生成 (%d -> %d)" % [beams_before, beams_after])

	# 开火之后立刻进入下一轮冷却 (fire_timer 被重设为一个远大于
	# LASER_CHARGE_TIME 的随机值), 指示器应该在下一帧就重新隐藏。
	await process_frame
	if is_instance_valid(enemy.laser_charge_container) and enemy.laser_charge_container.visible:
		fail("开火之后指示器应该重新隐藏, 实际仍然显示")
	else:
		ok("开火之后指示器正确隐藏, 直到下一次蓄力窗口")

	enemy.queue_free()
	player.queue_free()
	actors.queue_free()

func _test_indicator_hidden_before_charge_window() -> void:
	print("\n[STEP 2] A freshly spawned laser tank outside its charge window has no visible indicator...")

	var actors = Node2D.new()
	root.add_child(actors)
	var enemy = _make_laser_enemy(Vector2(200.0, 200.0), actors)

	# 冷却刚开始 (远大于 LASER_CHARGE_TIME), 指示器不该被创建或显示。
	enemy.fire_timer = enemy.fire_interval
	enemy._physics_process(0.016)

	if is_instance_valid(enemy.laser_charge_container) and enemy.laser_charge_container.visible:
		fail("冷却期间 (远未进入蓄力窗口) 指示器不该显示")
	else:
		ok("冷却期间指示器保持隐藏, 只在蓄力窗口内出现")

	enemy.queue_free()
	actors.queue_free()

func _count_lit_segments(enemy: Node2D) -> int:
	var n = 0
	for seg in enemy.laser_charge_segment_sprites:
		if seg.texture == enemy.laser_segment_tex_lit:
			n += 1
	return n

func _count_beam_sprites(container: Node2D) -> int:
	var n = 0
	for c in container.get_children():
		if c is Sprite2D:
			n += 1
	return n
