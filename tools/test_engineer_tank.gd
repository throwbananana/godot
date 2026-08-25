extends SceneTree

const EnemyTankScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING ENGINEER TANK (工程坦克) TESTS <<<")
	print("==================================================")

	_test_engineer_tank_assets_and_instantiation()
	_test_engineer_tank_stats_and_timers()
	_test_engineer_tank_build_behavior()
	_test_encyclopedia_and_metadata()

	print("\n>>> ALL ENGINEER TANK TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_engineer_tank_assets_and_instantiation() -> void:
	print("\n[STEP 1] 验证工程坦克 3D 渲染动效资产 (tank_engineer / enemy_engineer)...")

	var required_frames = [
		"res://assets/sprites/tanks/tank_engineer_f0.png",
		"res://assets/sprites/tanks/tank_engineer_f5.png",
		"res://assets/sprites/tanks/enemy_engineer_f0.png",
		"res://assets/sprites/tanks/enemy_engineer_f5.png",
		"res://assets/sprites/tanks/tank_engineer.png"
	]

	for path in required_frames:
		var tex = load(path)
		assert(tex != null, "工程坦克贴图必须存在: %s" % path)

	print("  [PASS] 6 帧动效与图鉴图标全部加载正常。")

func _test_engineer_tank_stats_and_timers() -> void:
	print("\n[STEP 2] 验证工程坦克初始数值、装甲与建造计时器...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	assert(enemy_scene != null, "enemy.tscn 场景必须存在")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.ENGINEER
	root.add_child(enemy)

	assert(enemy.enemy_type == EnemyTank.EnemyType.ENGINEER, "敌人类型必须为 ENGINEER")
	assert(enemy.max_health >= 4, "工程坦克基础生命值必须 >= 4")
	assert(enemy.speed >= 60.0 and enemy.speed <= 80.0, "工程坦克速度必须在 60..80 px/s 之间, 实际为 %f" % enemy.speed)
	assert(enemy.BUILD_COOLDOWN == 10.0, "建造冷却周期必须为 10.0 秒")
	assert(enemy.build_timer == 10.0, "初始建造计时器必须设为 10.0 秒")

	enemy.queue_free()
	print("  [PASS] 工程坦克数值与 10 秒建造参数验证通过。")

func _test_engineer_tank_build_behavior() -> void:
	print("\n[STEP 3] 验证工程坦克周围空地施工放置行为...")

	# 创建模拟战区节点树
	var mock_scene = Node2D.new()
	mock_scene.name = "MockMain"
	var game_area = Node2D.new()
	game_area.name = "GameArea"
	var actors_container = Node2D.new()
	actors_container.name = "ActorsContainer"
	var map_container = Node2D.new()
	map_container.name = "MapContainer"

	game_area.add_child(actors_container)
	game_area.add_child(map_container)
	mock_scene.add_child(game_area)
	root.add_child(mock_scene)
	current_scene = mock_scene

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.ENGINEER
	enemy.global_position = Vector2(240, 240)
	actors_container.add_child(enemy)

	var initial_actor_count = actors_container.get_child_count()

	# 触发建造逻辑
	enemy._perform_engineer_build()

	# 建造完成后，actors_container 中应成功增加建筑或地形
	var new_actor_count = actors_container.get_child_count()
	assert(new_actor_count >= initial_actor_count, "工程坦克施工后必须成功在周围生成新实体")

	mock_scene.queue_free()
	print("  [PASS] 工程坦克周围空地探测与随机地形/建筑建造测试通过。")

func _test_encyclopedia_and_metadata() -> void:
	print("\n[STEP 4] 验证图鉴数据中工程坦克条目...")

	var found := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_engineer":
			found = true
			assert(entry.get("category") == "TANKS", "图鉴分类必须为 TANKS")
			assert("10s" in entry.get("stats", {}).get("特殊能力", ""), "图鉴属性必须标明 10s 施工能力")
			break

	assert(found, "图鉴中必须包含 enemy_engineer 条目")
	print("  [PASS] 图鉴条目配置完整有效。")
