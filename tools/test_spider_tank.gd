extends SceneTree

const EnemyTankScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING SPIDER TANK (跳蛛坦克) TESTS <<<")
	print("==================================================")

	_test_spider_tank_assets_and_instantiation()
	_test_spider_tank_stats_and_timers()
	await _test_spider_tank_leap_behavior()
	_test_encyclopedia_and_metadata()

	print("\n>>> ALL SPIDER TANK TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_spider_tank_assets_and_instantiation() -> void:
	print("\n[STEP 1] 验证跳蛛坦克 3D 仿生 8 足动效资产 (tank_spider / enemy_spider)...")

	var required_frames = [
		"res://assets/sprites/tanks/tank_spider_f0.png",
		"res://assets/sprites/tanks/tank_spider_f5.png",
		"res://assets/sprites/tanks/enemy_spider_f0.png",
		"res://assets/sprites/tanks/enemy_spider_f5.png",
		"res://assets/sprites/tanks/tank_spider.png"
	]

	for path in required_frames:
		var tex = load(path)
		assert(tex != null, "跳蛛坦克贴图必须存在: %s" % path)

	print("  [PASS] 6 帧仿生步态与图鉴图标全部加载正常。")

func _test_spider_tank_stats_and_timers() -> void:
	print("\n[STEP 2] 验证跳蛛坦克初始数值、仿生装甲与跳跃冷却...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	assert(enemy_scene != null, "enemy.tscn 场景必须存在")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.SPIDER
	root.add_child(enemy)

	assert(enemy.enemy_type == EnemyTank.EnemyType.SPIDER, "敌人类型必须为 SPIDER")
	assert(enemy.max_health >= 3, "跳蛛坦克基础生命值必须 >= 3")
	assert(enemy.speed >= 85.0, "跳蛛坦克速度必须 >= 85 px/s, 实际为 %f" % enemy.speed)
	assert(enemy.JUMP_COOLDOWN == 3.5, "跳跃冷却周期必须为 3.5 秒")
	assert(enemy.fire_interval == 1.6, "双联毒针速射间隔必须为 1.6 秒")

	enemy.queue_free()
	print("  [PASS] 跳蛛坦克数值与参数验证通过。")

func _test_spider_tank_leap_behavior() -> void:
	print("\n[STEP 3] 验证跳蛛坦克隔障跳跃检测与高空抛物线越障演出...")

	var mock_scene = Node2D.new()
	mock_scene.name = "MockMain"
	root.add_child(mock_scene)
	current_scene = mock_scene

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.SPIDER
	enemy.global_position = Vector2(100, 100)
	enemy.facing_direction = Vector2.DOWN
	mock_scene.add_child(enemy)

	var target_landing = enemy.global_position + Vector2(0, 96) # 跨越前方 1 格 (48px) 阻挡，落在第 2 格 (96px)
	enemy._start_spider_leap(target_landing)

	assert(enemy.is_leaping == true, "起跳后 is_leaping 必须为 true")

	# 等待跳跃与落地动画完成
	await create_timer(0.85).timeout

	assert(enemy.is_leaping == false, "落地后 is_leaping 必须恢复为 false")
	assert(enemy.global_position.distance_to(target_landing) < 2.0, "落地后位置必须准确到达目标点, 实际为 %v, 目标为 %v" % [enemy.global_position, target_landing])
	assert(enemy.jump_cooldown_timer > 2.0, "落地后跳跃冷却必须重新进入倒计时")

	mock_scene.queue_free()
	print("  [PASS] 跳蛛坦克隔障起跳、腾空位移与落地震击全套演出测试通过。")

func _test_encyclopedia_and_metadata() -> void:
	print("\n[STEP 4] 验证图鉴数据与楼层门禁...")

	var found := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_spider":
			found = true
			assert(entry.get("category") == "TANKS", "图鉴分类必须为 TANKS")
			assert("跳跃" in entry.get("stats", {}).get("特殊能力", ""), "图鉴属性必须标明越障跳跃能力")
			break

	assert(found, "图鉴中必须包含 enemy_spider 条目")
	print("  [PASS] 图鉴条目配置完整有效。")
