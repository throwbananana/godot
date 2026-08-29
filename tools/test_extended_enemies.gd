extends SceneTree

const TextureHelper = preload("res://scripts/texture_helper.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const EnemyTank = preload("res://scripts/enemy.gd")
const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")
const GameState = preload("res://scripts/game_state.gd")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func ok(msg: String) -> void:
	print("  [ok] %s" % msg)

func _tick(n: int) -> void:
	for i in range(n):
		await physics_frame

func _init() -> void:
	print("==================================================")
	print(">>> EXTENDED ENEMIES & VFX INTEGRATION TEST <<<")
	print("==================================================")

	_check_tank_assets()
	_check_vfx_assets()
	_check_encyclopedia_entries()
	await _check_runtime_spawns()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项测试失败" % failures)
		quit(1)
	else:
		print(">>> ALL EXTENDED ENEMIES & VFX TESTS PASSED! <<<")
		quit(0)

func _check_tank_assets() -> void:
	print("\n--- 1. 检查新敌人贴图与 6 帧动画 ---")
	var tanks = ["enemy_tesla", "enemy_toxic", "enemy_drone_carrier", "enemy_drone_mini"]
	for t_name in tanks:
		var base_tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s.png" % t_name)
		if base_tex == null:
			fail("坦克主图标缺失: %s.png" % t_name)
		else:
			ok("坦克主图标存在: %s.png" % t_name)

		for f in range(6):
			var f_tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [t_name, f])
			if f_tex == null:
				fail("坦克动画帧缺失: %s_f%d.png" % [t_name, f])
			else:
				ok("坦克动画帧存在: %s_f%d.png" % [t_name, f])

func _check_vfx_assets() -> void:
	print("\n--- 2. 检查新 VFX 动画序列 ---")
	var vfx_list = ["tesla_arc_spark", "toxic_splash"]
	for v_name in vfx_list:
		for f in range(6):
			var v_tex = TextureHelper.get_tex("res://assets/sprites/effects/%s_%d.png" % [v_name, f])
			if v_tex == null:
				fail("VFX 帧缺失: %s_%d.png" % [v_name, f])
			else:
				ok("VFX 帧存在: %s_%d.png" % [v_name, f])

func _check_encyclopedia_entries() -> void:
	print("\n--- 3. 检查百科图鉴收录 ---")
	var expected_ids = ["enemy_tesla", "enemy_toxic", "enemy_drone_carrier", "enemy_drone_mini"]
	for eid in expected_ids:
		var found = false
		for item in EncyclopediaData.ENTRIES:
			if item.get("id") == eid:
				found = true
				if item.get("category") != "TANKS":
					fail("%s 分类错误: %s" % [eid, item.get("category")])
				if not item.has("stats") or item["stats"].is_empty():
					fail("%s 缺少属性 stats" % eid)
				if not item.has("tactics") or item["tactics"].is_empty():
					fail("%s 缺少应对策略 tactics" % eid)
				ok("图鉴已收录 %s: %s" % [eid, item.get("name")])
				break
		if not found:
			fail("图鉴未找到敌人: %s" % eid)

func _check_runtime_spawns() -> void:
	print("\n--- 4. 运行时实例化与武器技能测试 ---")
	var root := Node2D.new()
	root.name = "TestExtendedArena"
	get_root().add_child(root)

	var enemy_scene = load("res://scenes/enemy.tscn")
	if enemy_scene == null:
		fail("无法加载 res://scenes/enemy.tscn")
		root.queue_free()
		return

	var test_types = [
		EnemyTank.EnemyType.TESLA,
		EnemyTank.EnemyType.TOXIC,
		EnemyTank.EnemyType.DRONE_CARRIER,
		EnemyTank.EnemyType.DRONE_MINI
	]

	for etype in test_types:
		var inst: EnemyTank = enemy_scene.instantiate()
		inst.enemy_type = etype
		root.add_child(inst)
		inst.global_position = Vector2(200, 200)
		await _tick(3)

		if inst.tank_frames.size() != 6:
			fail("敌人 %s tank_frames 帧数不为 6 (实际 %d)" % [str(etype), inst.tank_frames.size()])
		else:
			ok("敌人 %s 6帧动作动画载入成功 (HP=%d, Speed=%.1f)" % [str(etype), inst.max_health, inst.speed])

		# 测试开火/武器逻辑
		inst._shoot()
		await _tick(2)
		ok("敌人 %s 触发武器/技能测试通过" % str(etype))

		inst.queue_free()
		await _tick(2)

	# 测试 VFX 触发
	VFXAnimator.spawn_tesla_arc_spark(root, Vector2(100, 100), 1.0)
	VFXAnimator.spawn_toxic_splash(root, Vector2(200, 200), 1.0)
	await _tick(5)
	ok("VFXAnimator 播放特斯拉电弧与生化酸液特效成功")

	root.queue_free()
	await _tick(2)
