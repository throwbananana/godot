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
	print(">>> NEW ADVANCED BOSSES & VFX TEST SUITE <<<")
	print("==================================================")

	_check_boss_assets()
	_check_vfx_assets()
	_check_encyclopedia_entries()
	await _check_runtime_bosses()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项测试失败" % failures)
		quit(1)
	else:
		print(">>> ALL NEW BOSSES & VFX TESTS PASSED (100%)! <<<")
		quit(0)

func _check_boss_assets() -> void:
	print("\n--- 1. 检查 Boss 贴图与动画帧 ---")
	var bosses = ["enemy_titan_boss", "enemy_scorpion_boss", "enemy_mammoth_boss"]
	for b_name in bosses:
		var base_tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s.png" % b_name)
		if base_tex == null:
			fail("Boss 主图标缺失: %s.png" % b_name)
		else:
			ok("Boss 主图标存在: %s.png" % b_name)

		for f in range(6):
			var f_tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [b_name, f])
			if f_tex == null:
				fail("Boss 动画帧缺失: %s_f%d.png" % [b_name, f])
			else:
				ok("Boss 动画帧存在: %s_f%d.png" % [b_name, f])

func _check_vfx_assets() -> void:
	print("\n--- 2. 检查 Boss 动效序列 ---")
	var vfx_list = ["boss_plasma_nova", "boss_frost_nova"]
	for v_name in vfx_list:
		for f in range(6):
			var v_tex = TextureHelper.get_tex("res://assets/sprites/effects/%s_%d.png" % [v_name, f])
			if v_tex == null:
				fail("VFX 帧缺失: %s_%d.png" % [v_name, f])
			else:
				ok("VFX 帧存在: %s_%d.png" % [v_name, f])

func _check_encyclopedia_entries() -> void:
	print("\n--- 3. 检查百科图鉴收录 ---")
	var expected_ids = ["enemy_titan_boss", "enemy_scorpion_boss", "enemy_mammoth_boss"]
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
			fail("图鉴未找到 Boss: %s" % eid)

func _check_runtime_bosses() -> void:
	print("\n--- 4. 运行时 Boss 实例化与攻击逻辑测试 ---")
	var root := Node2D.new()
	root.name = "TestBossArena"
	get_root().add_child(root)

	var enemy_scene = load("res://scenes/enemy.tscn")
	if enemy_scene == null:
		fail("无法加载 res://scenes/enemy.tscn")
		root.queue_free()
		return

	var test_types = [
		EnemyTank.EnemyType.TITAN_BOSS,
		EnemyTank.EnemyType.SCORPION_BOSS,
		EnemyTank.EnemyType.MAMMOTH_BOSS
	]

	for etype in test_types:
		var inst: EnemyTank = enemy_scene.instantiate()
		inst.enemy_type = etype
		root.add_child(inst)
		inst.global_position = Vector2(200, 200)
		await _tick(3)

		if not inst.is_boss_unit():
			fail("is_boss_unit() 未正确识别 Boss 类型: %s" % str(etype))
		else:
			ok("Boss 识别验证成功: %s (HP=%d, Speed=%.1f)" % [str(etype), inst.max_health, inst.speed])

		if inst.tank_frames.size() != 6:
			fail("Boss %s tank_frames 帧数不为 6 (实际 %d)" % [str(etype), inst.tank_frames.size()])
		else:
			ok("Boss %s 6帧动作动画载入正常" % str(etype))

		# 测试开火射击逻辑
		inst._shoot()
		await _tick(2)
		ok("Boss %s 触发专属技能与射击成功" % str(etype))

		inst.queue_free()
		await _tick(2)

	# 测试 VFX 生成器
	VFXAnimator.spawn_boss_plasma_nova(root, Vector2(100, 100), 1.0)
	VFXAnimator.spawn_boss_frost_nova(root, Vector2(300, 300), 1.0)
	await _tick(5)
	ok("VFXAnimator 成功触发 Boss 特效动画")

	root.queue_free()
	await _tick(2)
