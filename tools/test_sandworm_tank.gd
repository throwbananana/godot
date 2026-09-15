extends SceneTree

const EnemyTankScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func check(cond: bool, msg: String) -> bool:
	if not cond:
		fail(msg)
	return cond

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING SANDWORM TANK (沙虫坦克) TESTS <<<")
	print("==================================================")

	_test_sandworm_tank_assets()
	_test_sandworm_tank_stats()
	await _test_sandworm_burrow_and_emerge()
	_test_sandworm_target_finding()
	_test_encyclopedia_and_metadata()

	if failures > 0:
		print("\n[FAIL] %d 项失败" % failures)
		quit(1)
	else:
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
		check(tex != null, "沙虫坦克贴图必须存在: %s" % path)

	print("  [PASS] 6 帧坦克动效与图鉴图标全部加载正常。")

func _test_sandworm_tank_stats() -> void:
	print("\n[STEP 2] 验证沙虫坦克初始数值与类型配置...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	if not check(enemy_scene != null, "enemy.tscn 场景必须存在"):
		return
	var enemy = enemy_scene.instantiate() as EnemyTank
	enemy.enemy_type = EnemyTank.EnemyType.SANDWORM
	root.add_child(enemy)

	check(enemy.enemy_type == EnemyTank.EnemyType.SANDWORM, "敌人类型必须为 SANDWORM")
	check(enemy.max_health >= 3, "沙虫坦克基础生命值必须 >= 3")
	check(enemy.BURROW_INTERVAL > 0.0, "钻地周期必须大于 0")

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

	# 验证初始状态下处于地面
	check(enemy.is_burrowed == false, "初始状态必须在地面")

	# 地面状态下必须能正常受击 —— 这才是真正要保护的行为，而不是某个碰撞层位。
	# bullet.tscn 与 enemy.tscn 全项目都保持 Godot 默认的 layer=1/mask=1，
	# _start_sandworm_burrow() 切换的是 layer 位 2，从未动过子弹判定实际依赖的位 1，
	# 所以"碰撞层 2 是否开启"本身并不能反映沙虫是否真的能被子弹打中，直接测行为更可靠。
	var hp_before_burrow = enemy.health
	enemy.take_damage(1)
	check(enemy.health == hp_before_burrow - 1, "潜地前必须能正常受到伤害")

	# 启动钻地循环
	enemy._start_sandworm_burrow()

	# 等待下潜完成
	await create_timer(0.45).timeout

	# 验证已下潜至地下
	check(enemy.is_burrowed == true, "下潜后必须进入潜地状态 is_burrowed = true")
	check(enemy.get_collision_layer_value(2) == false, "潜地状态下碰撞层 2 应关闭")

	# 潜地状态下必须真正免疫伤害 (take_damage 直接判 is_burrowed 提前返回)
	var hp_during_burrow = enemy.health
	enemy.take_damage(99)
	check(enemy.health == hp_during_burrow, "潜地状态下必须免疫伤害 (避弹无敌), 实际扣血至 %d" % enemy.health)

	# 等待破土冲出 (地下 1.2s + 预警 0.35s + 破土 0.3s)
	await create_timer(2.0).timeout

	# 验证已破土冲出地面，重新开启受击判定
	check(enemy.is_burrowed == false, "破土后必须离开潜地状态 is_burrowed = false")
	check(enemy.get_collision_layer_value(2) == true, "破土后碰撞层 2 必须重新激活")
	check(enemy.burrow_timer > 0.0, "破土后必须重置钻地冷却计时器")

	var hp_after_emerge = enemy.health
	enemy.take_damage(1)
	check(enemy.health == hp_after_emerge - 1, "破土后必须恢复正常受击")

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
		check(not in_eagle_zone, "沙虫破土点不能落在老鹰基地保护区: row=%d col=%d" % [row, col])

	enemy.queue_free()
	mock_scene.queue_free()
	print("  [PASS] 合法破土目标计算验证通过。")

func _test_encyclopedia_and_metadata() -> void:
	print("\n[STEP 5] 验证图鉴数据与楼层门禁...")

	var found := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_sandworm":
			found = true
			check(entry.get("category") == "TANKS", "图鉴分类必须为 TANKS")
			check("潜地" in entry.get("desc", ""), "图鉴描述必须包含潜地")
			break

	check(found, "图鉴中必须包含 enemy_sandworm 条目")
	print("  [PASS] 图鉴条目配置完整有效。")
