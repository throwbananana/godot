extends SceneTree

const EnemyScript = preload("res://scripts/enemy.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING DIFFERENTIATED ENEMY ARCHETYPES TESTS <<<")
	print("==================================================")

	_test_sniper_properties_and_firing()
	_test_gatling_properties_and_firing()
	_test_shotgun_properties_and_firing()
	_test_all_frame_assets_exist()

	print("\n>>> ALL DIFFERENTIATED ENEMY ARCHETYPE CHECKS PASSED! <<<")
	quit(0)

func _test_sniper_properties_and_firing() -> void:
	print("\n[STEP 1] Testing SNIPER (High speed, long interval, high-power snipe)...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.SNIPER
	enemy._setup_tank_type()

	# Assert stat contracts
	assert(enemy.speed >= 130.0, "Sniper must be fast (>130 speed, got %f)" % enemy.speed)
	assert(enemy.fire_interval >= 4.5, "Sniper fire interval must be long (>4.5s, got %f)" % enemy.fire_interval)
	assert(enemy.max_health == 2, "Sniper health should be 2 (fragile scout)")

	# Test aim charge deceleration
	enemy.fire_timer = 0.5 # Under 0.6s threshold
	enemy._physics_process(0.016)
	assert(enemy.velocity == Vector2.ZERO, "Sniper must stop moving while aiming and charging shot")

	# Test sniper bullet properties
	var prev_bullet_count = get_nodes_in_group("bullet").size()
	enemy.facing_direction = Vector2.UP
	enemy._shoot()
	var bullets = get_nodes_in_group("bullet")
	assert(bullets.size() > prev_bullet_count, "Sniper must spawn a bullet")
	var spawned_b = bullets[-1]
	assert(spawned_b.speed >= 600.0, "Sniper bullet must be ultra-high speed (>=600, got %f)" % spawned_b.speed)
	assert(spawned_b.damage >= 2, "Sniper bullet must deal at least 2 damage")
	assert(spawned_b.can_destroy_steel == true, "Sniper bullet must pierce/destroy steel")

	spawned_b.queue_free()
	enemy.queue_free()
	print("  [PASS] SNIPER high-speed + long interval + rail shot verified.")

func _test_gatling_properties_and_firing() -> void:
	print("\n[STEP 2] Testing GATLING (Slow speed, high fire rate, suppression barrage)...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.GATLING
	enemy._setup_tank_type()

	# Assert stat contracts
	assert(enemy.speed <= 45.0, "Gatling must be slow (<=45 speed, got %f)" % enemy.speed)
	assert(enemy.fire_interval <= 0.50, "Gatling fire interval must be rapid (<=0.5s, got %f)" % enemy.fire_interval)
	assert(enemy.max_health >= 5, "Gatling must be sturdy (>=5 hp, got %d)" % enemy.max_health)

	var prev_bullet_count = get_nodes_in_group("bullet").size()
	enemy.facing_direction = Vector2.DOWN
	enemy._shoot()
	var bullets = get_nodes_in_group("bullet")
	assert(bullets.size() > prev_bullet_count, "Gatling must spawn bullet")
	var spawned_b = bullets[-1]
	assert(spawned_b.damage == 1, "Gatling bullet deals rapid 1 damage")

	spawned_b.queue_free()
	enemy.queue_free()
	print("  [PASS] GATLING slow move + ultra rapid fire verified.")

func _test_shotgun_properties_and_firing() -> void:
	print("\n[STEP 3] Testing SHOTGUN (Medium-fast speed, 3-way spread burst)...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.SHOTGUN
	enemy._setup_tank_type()

	# Assert stat contracts
	assert(enemy.speed >= 90.0, "Shotgun must have solid rush speed (>=90, got %f)" % enemy.speed)
	assert(enemy.max_health == 3, "Shotgun health should be 3")

	# Test 3-way spread firing
	var prev_bullet_count = get_nodes_in_group("bullet").size()
	enemy.facing_direction = Vector2.RIGHT
	enemy._shoot()
	var bullets = get_nodes_in_group("bullet")
	var new_bullets = bullets.size() - prev_bullet_count
	assert(new_bullets == 3, "Shotgun must fire 3 spread pellets per volley (got %d)" % new_bullets)

	for b in bullets.slice(bullets.size() - 3):
		if is_instance_valid(b):
			b.queue_free()
	enemy.queue_free()
	print("  [PASS] SHOTGUN 3-way spread volley verified.")

func _test_all_frame_assets_exist() -> void:
	print("\n[STEP 4] Testing 6-frame animations for all new enemy types...")
	var types_to_check = [
		EnemyScript.EnemyType.SNIPER,
		EnemyScript.EnemyType.GATLING,
		EnemyScript.EnemyType.SHOTGUN
	]

	for t in types_to_check:
		var enemy = EnemyScript.new()
		root.add_child(enemy)
		enemy.enemy_type = t
		enemy._setup_tank_type()
		assert(enemy.tank_frames.size() == 6, "Type %d must load 6 frames, got %d" % [t, enemy.tank_frames.size()])
		for i in range(6):
			assert(enemy.tank_frames[i] != null, "Frame %d for type %d must not be null" % [i, t])
		enemy.queue_free()

	print("  [PASS] All 6-frame sets loaded correctly.")
