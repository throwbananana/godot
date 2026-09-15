extends SceneTree

const EnemyScript = preload("res://scripts/enemy.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BaseEagleScript = preload("res://scripts/base_eagle.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print("RUNNING ENEMY CRUSHER TESTS")
	print("==================================================")

	_test_crusher_properties_and_frames()
	_test_crusher_crushes_brick_and_hard_clay()
	_test_crusher_crushes_steel_wall()
	_test_crusher_preserves_border_steel()
	await _test_crusher_crushes_buildings()
	_test_crusher_crushes_player_tank()
	_test_crusher_crushes_base_eagle()
	_test_crusher_no_bullet_firing()

	print("\nALL ENEMY CRUSHER CHECKS PASSED!")
	quit(0)

func _test_crusher_properties_and_frames() -> void:
	print("\n[STEP 1] Checking Crusher stats, scale, and animation frames...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	assert(enemy.speed == 40.0, "Crusher must be slow (speed=40.0, got %f)" % enemy.speed)
	assert(enemy.max_health >= 10, "Crusher must have high health (>=10, got %d)" % enemy.max_health)
	assert(enemy.fire_interval >= 900.0, "Crusher must not shoot (fire_interval>=900, got %f)" % enemy.fire_interval)
	# is_equal_approx 而不是 == : Vector2 存的是 float32, Vector2(0.24, 0.24).x
	# 实际是 0.2399999946, 而字面量 0.24 是 float64 —— == 恒为假。
	# 这条断言一直在失败, 只是整个文件因为别处的解析错误从来没跑起来过。
	assert(is_equal_approx(enemy.sprite.scale.x, 0.24) and is_equal_approx(enemy.sprite.scale.y, 0.24),
		"Crusher must have large sprite scale (0.24, 0.24), got %s" % str(enemy.sprite.scale))
	assert(enemy.tank_frames.size() == 6, "Crusher must have 6 rendered frames loaded, got %d" % enemy.tank_frames.size())

	for i in range(6):
		assert(enemy.tank_frames[i] != null, "Crusher frame %d must be non-null" % i)

	enemy.queue_free()
	print("  [PASS] Crusher base attributes, scale, and 6-frame animations verified.")

func _test_crusher_crushes_brick_and_hard_clay() -> void:
	print("\n[STEP 2] Checking Crusher crushing brick and hard clay...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	# 1. Brick obstacle
	var brick = StaticBody2D.new()
	brick.add_to_group("brick")
	root.add_child(brick)
	brick.global_position = Vector2(100, 100)

	var result = enemy._crush_target(brick)
	assert(result == true, "_crush_target must return true for brick")
	assert(brick.is_queued_for_deletion(), "Brick obstacle must be queued for deletion")

	# 2. Hard clay block
	var clay = StaticBody2D.new()
	clay.add_to_group("brick")
	clay.add_to_group("hard_clay")
	clay.set_script(load("res://scripts/hard_clay_block.gd"))
	root.add_child(clay)
	clay.global_position = Vector2(150, 100)

	result = enemy._crush_target(clay)
	assert(result == true, "_crush_target must return true for hard clay")
	assert(clay.is_queued_for_deletion(), "Hard clay must be destroyed by Crusher take_hit(99)")

	enemy.queue_free()
	print("  [PASS] Brick and hard clay terrain crushed successfully.")

func _test_crusher_crushes_steel_wall() -> void:
	print("\n[STEP 3] Checking Crusher crushing steel walls (non-border)...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	var steel = StaticBody2D.new()
	steel.add_to_group("steel")
	root.add_child(steel)
	steel.global_position = Vector2(200, 100)

	var result = enemy._crush_target(steel)
	assert(result == true, "_crush_target must return true for steel wall")
	assert(steel.is_queued_for_deletion(), "Steel wall must be crushed by Crusher")

	enemy.queue_free()
	print("  [PASS] Steel wall crushed successfully.")

func _test_crusher_preserves_border_steel() -> void:
	print("\n[STEP 4] Checking Crusher preserves map boundary border steel...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	var border = StaticBody2D.new()
	border.add_to_group("steel")
	border.add_to_group("border")
	root.add_child(border)
	border.global_position = Vector2(0, 0)

	var result = enemy._crush_target(border)
	assert(result == false, "_crush_target must NOT crush border steel")
	assert(not border.is_queued_for_deletion(), "Border steel must NOT be deleted")

	border.queue_free()
	enemy.queue_free()
	print("  [PASS] Map border steel safety preserved.")

func _test_crusher_crushes_buildings() -> void:
	print("\n[STEP 5] Checking Crusher crushing player and map buildings...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	var bld_scenes = [
		"res://scenes/buildings/fortified_wall.tscn",
		"res://scenes/buildings/defense_turret.tscn",
		"res://scenes/buildings/electric_wall.tscn",
		"res://scenes/buildings/repair_station.tscn",
		"res://scenes/buildings/shield_station.tscn",
		"res://scenes/buildings/wind_blower.tscn",
		"res://scenes/buildings/street_lamp.tscn",
		"res://scenes/buildings/oil_barrel.tscn",
		"res://scenes/buildings/roller_wall.tscn"
	]

	for b_path in bld_scenes:
		var sc = load(b_path)
		var b_inst = sc.instantiate()
		root.add_child(b_inst)
		b_inst.global_position = Vector2(250, 250)

		# 不能直接把场景根节点交给 _crush_target。有些建筑 (fortified_wall)
		# 根节点是个纯容器 Node2D, 真正带碰撞体并挂 buildings/steel 组的是
		# 它拆成四块的 Piece 子节点 —— 根节点本身不在任何组里。游戏里碰撞
		# 查询返回的也是 Piece, 所以拿根节点去试是测试错了对象, 不是粉碎者坏了。
		# (tools/test_roller_wall_and_stage2_destruction.gd 早就是这么处理的。)
		var target: Node2D = b_inst
		if not (b_inst is CollisionObject2D):
			for child in b_inst.get_children():
				if child is CollisionObject2D:
					target = child
					break

		var result = enemy._crush_target(target)
		assert(result == true, "Crusher must crush building: %s" % b_path)
		await process_frame
		# 验的是 **target** 而不是 b_inst: 容器型建筑被撞掉一块 Piece 之后,
		# 容器本身当然还在 (它还有另外三块)。
		assert(target.is_queued_for_deletion() or not is_instance_valid(target)
			or (target == b_inst and b_inst.get_child_count() == 0),
			"Building %s must be destroyed/queued for deletion" % b_path)
		if is_instance_valid(b_inst):
			b_inst.queue_free()

	enemy.queue_free()
	print("  [PASS] All building types crushed successfully.")

func _test_crusher_crushes_player_tank() -> void:
	print("\n[STEP 6] Checking Crusher crushing player tank (damage + stun)...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	root.add_child(player)
	player.global_position = Vector2(300, 300)
	player.is_invulnerable = false

	var initial_hp = player.current_health
	var result = enemy._crush_target(player)
	assert(result == true, "Crusher must hit player tank")
	assert(player.current_health < initial_hp, "Player HP must be reduced by crush attack")
	assert(player.is_stunned == true, "Player tank must be stunned by crush attack")

	player.queue_free()
	enemy.queue_free()
	print("  [PASS] Player tank received heavy crushing damage and stun.")

func _test_crusher_crushes_base_eagle() -> void:
	print("\n[STEP 7] Checking Crusher crushing Base Eagle...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	var eagle_scene = load("res://scenes/base_eagle.tscn")
	var eagle = eagle_scene.instantiate()
	root.add_child(eagle)
	eagle.global_position = Vector2(350, 350)

	var result = enemy._crush_target(eagle)
	assert(result == true, "Crusher must crush Base Eagle")
	assert(eagle.is_destroyed == true or eagle.is_queued_for_deletion(), "Base Eagle must be destroyed")

	eagle.queue_free()
	enemy.queue_free()
	print("  [PASS] Base Eagle crushed and destroyed successfully.")

func _test_crusher_no_bullet_firing() -> void:
	print("\n[STEP 8] Checking Crusher does not fire bullets during physics process...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.CRUSHER
	enemy._setup_tank_type()

	for i in range(10):
		enemy._physics_process(0.016)

	var bullets = get_nodes_in_group("bullet")
	for b in bullets:
		if is_instance_valid(b) and ("shooter" in b) and b.shooter == enemy:
			assert(false, "Crusher must NEVER fire bullets!")

	enemy.queue_free()
	print("  [PASS] Crusher strictly refrains from shooting bullets.")
