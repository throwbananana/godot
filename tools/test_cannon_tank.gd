extends SceneTree

const EnemyScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")
const MainScript = preload("res://scripts/main.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING COLOSSUS SIEGE CANNON TANK TESTS <<<")
	print("==================================================")

	await _test_cannon_tank_initialization()
	await _test_cannon_proximity_deployment_and_defense()
	await _test_cannon_siege_shooting()
	await _test_cannon_undeployment()
	_test_encyclopedia_and_gate_integration()

	print("\n>>> ALL CANNON TANK CHECKS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_cannon_tank_initialization() -> void:
	print("\n[STEP 1] Testing Cannon Tank initialization and dual frame sets...")
	var scene = load("res://scenes/enemy.tscn")
	assert(scene != null, "Enemy scene should load")
	var enemy = scene.instantiate()
	enemy.enemy_type = EnemyScript.EnemyType.CANNON
	root.add_child(enemy)
	enemy.global_position = Vector2(240, 240)

	assert(enemy.max_health >= 6, "Cannon Tank base HP should be at least 6")
	assert(enemy.speed == 65.0, "Cannon Tank mobile speed should be 65.0")
	assert(not enemy.is_cannon_deployed, "Should start in mobile mode")
	assert(enemy.cannon_mobile_frames.size() == 6, "Should have 6 mobile frames")
	assert(enemy.cannon_deploy_frames.size() == 6, "Should have 6 deployed frames")

	enemy.queue_free()
	print("  [PASS] Initialization and dual frame loading verified.")

func _test_cannon_proximity_deployment_and_defense() -> void:
	print("\n[STEP 2] Testing proximity transformation and huge defense boost...")
	var scene = load("res://scenes/enemy.tscn")
	var enemy = scene.instantiate()
	enemy.enemy_type = EnemyScript.EnemyType.CANNON
	root.add_child(enemy)
	enemy.global_position = Vector2(300, 300)

	# 1. Create a dummy player in the player group at distance 120px (<= 192px CANNON_DEPLOY_DIST)
	var player = CharacterBody2D.new()
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = Vector2(300, 180) # 120px distance

	# Process 1 tick to trigger siege behavior
	enemy._process_cannon_siege_behavior(0.016)

	assert(enemy.is_cannon_deployed, "Cannon tank should transform into deployed siege mode when close to player")
	assert(enemy.tank_frames == enemy.cannon_deploy_frames, "Active frames should switch to deployed frames")

	# 2. Verify heavy defense damage reduction while deployed
	var initial_hp = enemy.health
	# Normal 4 damage shot: should be reduced by ~65% -> int(ceil(4 * 0.35)) = 2
	enemy.take_damage(4)
	var damage_taken = initial_hp - enemy.health
	assert(damage_taken < 4, "Deployed Cannon Tank should absorb majority of damage (got %d taken of 4)" % damage_taken)
	assert(damage_taken == 2, "4 damage with 65% reduction should take 2 damage")

	# Normal 1 damage shot: reduced to minimum 1 damage
	initial_hp = enemy.health
	enemy.take_damage(1)
	assert(initial_hp - enemy.health == 1, "1 damage should take 1 damage minimum")

	player.queue_free()
	enemy.queue_free()
	print("  [PASS] Proximity transformation and high defense boost verified.")

func _test_cannon_siege_shooting() -> void:
	print("\n[STEP 3] Testing deployed siege artillery bombardment...")
	var scene = load("res://scenes/enemy.tscn")
	var enemy = scene.instantiate()
	enemy.enemy_type = EnemyScript.EnemyType.CANNON
	root.add_child(enemy)
	enemy.global_position = Vector2(200, 200)

	# Deploy cannon
	enemy._deploy_cannon_siege_mode()
	assert(enemy.is_cannon_deployed, "Should be deployed")

	# Fire bullet
	var child_count_before = root.get_child_count()
	enemy._shoot()
	var child_count_after = root.get_child_count()

	# Verify bullet was instantiated
	assert(child_count_after > child_count_before, "Should spawn a bullet node")
	var spawned_bullet = root.get_child(child_count_after - 1)
	assert(spawned_bullet.is_in_group("bullet") or spawned_bullet.get_script() != null, "Spawned node should be a bullet")
	if "damage" in spawned_bullet:
		assert(spawned_bullet.damage >= 2, "Deployed siege bullet should deal heavy 2+ damage")
		assert(spawned_bullet.is_aoe, "Deployed siege bullet should have AoE blast")
		assert(spawned_bullet.can_destroy_steel, "Deployed siege shell should destroy steel obstacles")
	spawned_bullet.queue_free()

	enemy.queue_free()
	print("  [PASS] Heavy siege artillery bombardment verified.")

func _test_cannon_undeployment() -> void:
	print("\n[STEP 4] Testing undeployment when player retreats...")
	var scene = load("res://scenes/enemy.tscn")
	var enemy = scene.instantiate()
	enemy.enemy_type = EnemyScript.EnemyType.CANNON
	root.add_child(enemy)
	enemy.global_position = Vector2(200, 200)

	enemy._deploy_cannon_siege_mode()
	assert(enemy.is_cannon_deployed, "Should be deployed")

	# Create player far away at 400px distance (> 270px CANNON_UNDEPLOY_DIST)
	var player = CharacterBody2D.new()
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = Vector2(200, 600)

	# Process 3.0 seconds (> 2.5s CANNON_UNDEPLOY_DELAY)
	enemy._process_cannon_siege_behavior(3.0)

	assert(not enemy.is_cannon_deployed, "Cannon tank should undeploy when player stays far away")
	assert(enemy.tank_frames == enemy.cannon_mobile_frames, "Active frames should revert to mobile frames")

	player.queue_free()
	enemy.queue_free()
	print("  [PASS] Undeployment when player retreats verified.")

func _test_encyclopedia_and_gate_integration() -> void:
	print("\n[STEP 5] Testing Encyclopedia and Main gate integration...")
	# 1. Encyclopedia
	var found_in_enc = false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_cannon":
			found_in_enc = true
			assert(ResourceLoader.exists(entry["icon"]), "Encyclopedia icon should exist: %s" % entry["icon"])
			break
	assert(found_in_enc, "Encyclopedia should have 'enemy_cannon'")

	# 2. Main gate
	assert(MainScript.ENEMY_MIN_FLOOR.has(EnemyScript.EnemyType.CANNON), "Main ENEMY_MIN_FLOOR should contain CANNON")
	assert(MainScript.GATE_FALLBACK_POOL.has(EnemyScript.EnemyType.CANNON), "Main GATE_FALLBACK_POOL should contain CANNON")

	print("  [PASS] Encyclopedia and Main gate integration verified.")
