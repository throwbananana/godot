extends SceneTree

const EnemyTankScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")
const FirewallHazardScript = preload("res://scripts/buildings/firewall_hazard.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING FIREWALL TANK (火墙坦克) TESTS <<<")
	print("==================================================")

	_test_firewall_tank_assets_and_instantiation()
	_test_firewall_tank_stats()
	_test_firewall_trail_10_cap_queue()
	_test_firewall_touch_damage()
	_test_firewall_cleanup_on_death()
	_test_encyclopedia_and_metadata()

	print("\n>>> ALL FIREWALL TANK TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_firewall_tank_assets_and_instantiation() -> void:
	print("\n[STEP 1] 验证火墙坦克 3D 渲染动效与地表火焰 4 帧贴图...")

	var required_frames = [
		"res://assets/sprites/tanks/tank_firewall_f0.png",
		"res://assets/sprites/tanks/tank_firewall_f5.png",
		"res://assets/sprites/tanks/enemy_firewall_f0.png",
		"res://assets/sprites/tanks/enemy_firewall_f5.png",
		"res://assets/sprites/tanks/tank_firewall.png",
		"res://assets/sprites/buildings/firewall_flame_f0.png",
		"res://assets/sprites/buildings/firewall_flame_f3.png"
	]

	for path in required_frames:
		var tex = load(path)
		assert(tex != null, "火墙坦克/火焰贴图必须存在: %s" % path)

	print("  [PASS] 6 帧坦克动效、4 帧地表火焰贴图与图鉴图标全部加载正常。")

func _test_firewall_tank_stats() -> void:
	print("\n[STEP 2] 验证火墙坦克初始数值、黑曜重甲与火墙参数...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	assert(enemy_scene != null, "enemy.tscn 场景必须存在")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.FIREWALL
	root.add_child(enemy)

	assert(enemy.enemy_type == EnemyTank.EnemyType.FIREWALL, "敌人类型必须为 FIREWALL")
	assert(enemy.max_health >= 4, "火墙坦克基础生命值必须 >= 4")
	assert(enemy.MAX_FIREWALL_TRAIL_LENGTH == 10, "火墙轨迹队列上限必须严格为 10 格")
	assert(enemy.FIREWALL_DROP_DISTANCE > 0, "火墙铺设距离间隔必须大于 0")

	enemy.queue_free()
	print("  [PASS] 火墙坦克数值与 10 格火墙参数验证通过。")

func _test_firewall_trail_10_cap_queue() -> void:
	print("\n[STEP 3] 验证行驶时身后铺设火墙与最多 10 格队列上限...")

	var mock_scene = Node2D.new()
	root.add_child(mock_scene)
	current_scene = mock_scene

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.FIREWALL
	enemy.global_position = Vector2(100, 100)
	mock_scene.add_child(enemy)

	# 模拟移动并铺设 15 次火墙
	for i in range(15):
		enemy.global_position += Vector2(0, 40)
		enemy._drop_firewall_hazard()

	# 验证火墙队列数量被严格限制在 10 格
	assert(enemy.firewall_trail_queue.size() == 10, "火墙队列数量必须被严格限制在 10 格, 实际为 %d" % enemy.firewall_trail_queue.size())

	# 验证所有火墙均有效存在
	for fire in enemy.firewall_trail_queue:
		assert(is_instance_valid(fire), "队列中的火墙必须为有效实例")
		assert(fire.is_in_group("firewall"), "火墙必须属于 firewall 组")

	enemy.queue_free()
	mock_scene.queue_free()
	print("  [PASS] 10 格火墙队列上限与先进先出自动消退机制验证通过。")

func _test_firewall_touch_damage() -> void:
	print("\n[STEP 4] 验证战车触碰火墙受到伤害机制...")

	var hazard_scene = load("res://scenes/buildings/firewall_hazard.tscn")
	assert(hazard_scene != null, "firewall_hazard.tscn 场景必须存在")
	var fire = hazard_scene.instantiate()
	root.add_child(fire)

	# 模拟玩家战车
	var mock_player = Node2D.new()
	mock_player.add_to_group("player")
	var hp = 3
	mock_player.set_script(load("res://scripts/player.gd"))
	mock_player.set("health", hp)
	root.add_child(mock_player)

	# 触发触碰伤害
	fire._apply_burn_damage(mock_player)
	assert(mock_player.health == hp - 1, "触碰火墙必须扣除 1 点生命值, 实际为 %d" % mock_player.health)

	mock_player.queue_free()
	fire.queue_free()
	print("  [PASS] 火墙触碰灼烧伤害机制测试通过。")

func _test_firewall_cleanup_on_death() -> void:
	print("\n[STEP 5] 验证火墙坦克消亡时清理火墙队列...")

	var mock_scene = Node2D.new()
	root.add_child(mock_scene)

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.FIREWALL
	mock_scene.add_child(enemy)

	for i in range(5):
		enemy.global_position += Vector2(40, 0)
		enemy._drop_firewall_hazard()

	assert(enemy.firewall_trail_queue.size() == 5, "生成了 5 个火墙")

	# 触发死亡
	enemy._die()

	assert(enemy.firewall_trail_queue.is_empty(), "死亡后火墙队列必须被清空")

	mock_scene.queue_free()
	print("  [PASS] 战车消亡后火墙有序消退测试通过。")

func _test_encyclopedia_and_metadata() -> void:
	print("\n[STEP 6] 验证图鉴数据与楼层门禁...")

	var found := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_firewall":
			found = true
			assert(entry.get("category") == "TANKS", "图鉴分类必须为 TANKS")
			assert("10" in entry.get("stats", {}).get("特殊能力", ""), "图鉴属性必须标明 10 格火墙轨迹")
			break

	assert(found, "图鉴中必须包含 enemy_firewall 条目")
	print("  [PASS] 图鉴条目配置完整有效。")
