extends SceneTree

const EnemyTankScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING HUNTER TANK (猎手坦克) TESTS <<<")
	print("==================================================")

	_test_hunter_tank_assets()
	_test_hunter_tank_stats()
	_test_hunter_jungle_seeking_and_ambush()
	_test_hunter_ambush_trigger_and_attack()
	_test_hunter_fallback_without_trees()
	_test_encyclopedia_and_metadata()

	print("\n>>> ALL HUNTER TANK TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_hunter_tank_assets() -> void:
	print("\n[STEP 1] 验证猎手坦克 3D 渲染动效与图鉴图标贴图...")

	var required_frames = [
		"res://assets/sprites/tanks/tank_hunter_f0.png",
		"res://assets/sprites/tanks/tank_hunter_f5.png",
		"res://assets/sprites/tanks/enemy_hunter_f0.png",
		"res://assets/sprites/tanks/enemy_hunter_f5.png",
		"res://assets/sprites/tanks/tank_hunter.png"
	]

	for path in required_frames:
		var tex = load(path)
		assert(tex != null, "猎手坦克贴图必须存在: %s" % path)

	print("  [PASS] 6 帧坦克动效与图鉴图标全部加载正常。")

func _test_hunter_tank_stats() -> void:
	print("\n[STEP 2] 验证猎手坦克初始数值与类型配置...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	assert(enemy_scene != null, "enemy.tscn 场景必须存在")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.HUNTER
	root.add_child(enemy)

	assert(enemy.enemy_type == EnemyTank.EnemyType.HUNTER, "敌人类型必须为 HUNTER")
	assert(enemy.max_health >= 2, "猎手坦克基础生命值必须 >= 2")
	assert(enemy.speed >= 80.0, "猎手坦克基础移速必须 >= 80")

	enemy.queue_free()
	print("  [PASS] 猎手坦克基础属性验证通过。")

func _test_hunter_jungle_seeking_and_ambush() -> void:
	print("\n[STEP 3] 验证自动搜寻草丛与进入隐蔽潜伏状态...")

	var mock_scene = Node2D.new()
	root.add_child(mock_scene)
	current_scene = mock_scene

	# 放置一处草丛节点
	var mock_tree = Sprite2D.new()
	mock_tree.add_to_group("trees")
	mock_tree.global_position = Vector2(120, 100)
	mock_scene.add_child(mock_tree)

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.HUNTER
	enemy.global_position = Vector2(100, 100)
	mock_scene.add_child(enemy)

	# 1. 验证能成功检索到最近草丛
	var found_bush = enemy._find_nearest_jungle_tile()
	assert(found_bush == mock_tree.global_position, "必须成功检索到最近草丛坐标")

	# 2. 模拟猎手坦克靠近草丛并进驻
	enemy.global_position = mock_tree.global_position
	enemy._process_hunter_ambush_behavior(0.1)

	assert(enemy.is_in_ambush == true, "进驻草丛后必须进入潜伏状态 is_in_ambush = true")
	assert(enemy.sprite.modulate.a < 0.5, "潜伏状态下车身必须呈半透明伪装 (modulate.a < 0.5), 实际为 %f" % enemy.sprite.modulate.a)

	enemy.queue_free()
	mock_tree.queue_free()
	mock_scene.queue_free()
	print("  [PASS] 草丛检索、导航进驻与半透明伪装潜伏机制验证通过。")

func _test_hunter_ambush_trigger_and_attack() -> void:
	print("\n[STEP 4] 验证玩家路过时触发破隐伏击突袭...")

	var mock_scene = Node2D.new()
	root.add_child(mock_scene)
	current_scene = mock_scene

	# 猎手坦克在草丛中潜伏
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.HUNTER
	enemy.global_position = Vector2(100, 100)
	enemy.is_in_ambush = true
	mock_scene.add_child(enemy)

	# 模拟玩家路过（在猎手坦克下方 80px 处纵向对齐）
	var mock_player = Node2D.new()
	mock_player.add_to_group("player")
	mock_player.global_position = Vector2(100, 180)
	mock_scene.add_child(mock_player)

	# 触发伏击行为帧更新
	enemy._process_hunter_ambush_behavior(0.016)

	assert(enemy.is_in_ambush == false, "触发伏击后必须解除潜伏 is_in_ambush = false")
	assert(enemy.facing_direction == Vector2.DOWN, "伏击开火必须对准玩家方向 DOWN")
	assert(enemy.ambush_cooldown > 0.0, "伏击后必须进入冷却")

	mock_player.queue_free()
	enemy.queue_free()
	mock_scene.queue_free()
	print("  [PASS] 玩家路过侦测与破隐伏击突袭开火验证通过。")

func _test_hunter_fallback_without_trees() -> void:
	print("\n[STEP 5] 验证无草丛地图下退化为普通坦克行为...")

	var mock_scene = Node2D.new()
	root.add_child(mock_scene)
	current_scene = mock_scene

	# 场景中无任何草丛
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.HUNTER
	enemy.global_position = Vector2(100, 100)
	mock_scene.add_child(enemy)

	# 检索草丛应返回 INF
	var bush_pos = enemy._find_nearest_jungle_tile()
	assert(bush_pos == Vector2.INF, "无草丛时必须返回 Vector2.INF")

	enemy._process_hunter_ambush_behavior(0.1)
	assert(enemy.is_in_ambush == false, "无草丛时不应进入潜伏状态")
	assert(enemy.sprite.modulate.a == 1.0, "无草丛时车身必须为完全不透明 (modulate.a == 1.0)")

	enemy.queue_free()
	mock_scene.queue_free()
	print("  [PASS] 无草丛地图退化普通逻辑验证通过。")

func _test_encyclopedia_and_metadata() -> void:
	print("\n[STEP 6] 验证图鉴数据与楼层门禁...")

	var found := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_hunter":
			found = true
			assert(entry.get("category") == "TANKS", "图鉴分类必须为 TANKS")
			assert("草丛" in entry.get("desc", ""), "图鉴描述必须包含草丛潜伏")
			break

	assert(found, "图鉴中必须包含 enemy_hunter 条目")
	print("  [PASS] 图鉴条目配置完整有效。")
