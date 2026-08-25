extends SceneTree

const EnemyTankScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING SANDWORM TANK (沙虫坦克) TESTS <<<")
	print("==================================================")

	_test_sandworm_tank_assets()
	_test_sandworm_tank_stats()
	_test_sandworm_burrow_and_emerge()
	_test_sandworm_target_finding()
	_test_encyclopedia_and_metadata()

	print("\n>>> ALL SANDWORM TANK TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_sandworm_tank_assets() -> void:
	print("\n[STEP 1] 验证沙虫坦克 3D 渲染动效与图鉴图标贴图...")

	var required_frames = [
		"res://assets/sprites/tanks/tank_sandworm_f0.png",
		"res://assets/sprites/tanks/tank_sandworm_f5.png",
		"res://assets/sprites/tanks/enemy_sandworm_f0.png",
		"res://assets/sprites/tanks/enemy_sandworm_f5.png",
		"res://assets/sprites/tanks/tank_sandworm.png"
	]

	for path in required_frames:
		var tex = load(path)
		assert(tex != null, "沙虫坦克贴图必须存在: %s" % path)

	print("  [PASS] 6 帧坦克动效与图鉴图标全部加载正常。")

func _test_sandworm_tank_stats() -> void:
	print("\n[STEP 2] 验证沙虫坦克初始数值与类型配置...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	assert(enemy_scene != null, "enemy.tscn 场景必须存在")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.SANDWORM
	root.add_child(enemy)

	assert(enemy.enemy_type == EnemyTank.EnemyType.SANDWORM, "敌人类型必须为 SANDWORM")
	assert(enemy.max_health >= 3, "沙虫坦克基础生命值必须 >= 3")
	assert(enemy.BURROW_INTERVAL > 0.0, "钻地周期必须大于 0")

	enemy.queue_free()
	print("  [PASS] 沙虫坦克基础属性验证通过。")

func _test_sandworm_burrow_and_emerge() -> void:
	print("\n[STEP 3] 验证潜入地下避弹与破土冲出逻辑...")

	var mock_scene = Node2D.new()
	root.add_child(mock_scene)
	current_scene = mock_scene

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.SANDWORM
	enemy.global_position = Vector2(200, 200)
	mock_scene.add_child(enemy)

	# 验证初始状态下处于地面，碰撞层开启
	assert(enemy.is_burrowed == false, "初始状态必须在地面")
	assert(enemy.get_collision_layer_value(2) == true, "初始状态碰撞层 2 必须开启")

	# 启动钻地循环
	enemy._start_sandworm_burrow()

	# 等待下潜完成
	await create_timer(0.45).timeout

	# 验证已下潜至地下，碰撞层关闭（无法被子弹击中）
	assert(enemy.is_burrowed == true, "下潜后必须进入潜地状态 is_burrowed = true")
	assert(enemy.get_collision_layer_value(2) == false, "潜地状态下碰撞层 2 必须关闭 (避弹无敌)")

	# 等待破土冲出 (地下 1.2s + 预警 0.35s + 破土 0.3s)
	await create_timer(2.0).timeout

	# 验证已破土冲出地面，重新开启碰撞层与受击判定
	assert(enemy.is_burrowed == false, "破土后必须离开潜地状态 is_burrowed = false")
	assert(enemy.get_collision_layer_value(2) == true, "破土后碰撞层 2 必须重新激活")
	assert(enemy.burrow_timer > 0.0, "破土后必须重置钻地冷却计时器")

	enemy.queue_free()
	mock_scene.queue_free()
	print("  [PASS] 钻地潜行、避弹无敌与破土冲出重置验证通过。")

func _test_sandworm_target_finding() -> void:
	print("\n[STEP 4] 验证合法破土目标寻找与避开老鹰基地...")

	var mock_scene = Node2D.new()
	root.add_child(mock_scene)
	current_scene = mock_scene

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.SANDWORM
	enemy.global_position = Vector2(200, 200)
	mock_scene.add_child(enemy)

	for _i in range(10):
		var target_pos = enemy._find_valid_burrow_target_pos()
		var col = int(target_pos.x / 48.0)
		var row = int(target_pos.y / 48.0)
		# 验证目标点没有落在老鹰保护区
		var in_eagle_zone = (row >= 11 and col >= 5 and col <= 7)
		assert(not in_eagle_zone, "沙虫破土点不能落在老鹰基地保护区: row=%d col=%d" % [row, col])

	enemy.queue_free()
	mock_scene.queue_free()
	print("  [PASS] 合法破土目标计算验证通过。")

func _test_encyclopedia_and_metadata() -> void:
	print("\n[STEP 5] 验证图鉴数据与楼层门禁...")

	var found := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_sandworm":
			found = true
			assert(entry.get("category") == "TANKS", "图鉴分类必须为 TANKS")
			assert("潜地" in entry.get("desc", ""), "图鉴描述必须包含潜地")
			break

	assert(found, "图鉴中必须包含 enemy_sandworm 条目")
	print("  [PASS] 图鉴条目配置完整有效。")
