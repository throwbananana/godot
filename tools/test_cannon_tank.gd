extends SceneTree

const EnemyScript = preload("res://scripts/enemy.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")
const MainScript = preload("res://scripts/main.gd")

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
	print(">>> RUNNING COLOSSUS SIEGE CANNON TANK TESTS <<<")
	print("==================================================")

	await _test_cannon_tank_initialization()
	await _test_cannon_proximity_deployment_and_defense()
	await _test_cannon_siege_shooting()
	await _test_cannon_undeployment()
	_test_encyclopedia_and_gate_integration()

	if failures > 0:
		print("\n[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print("\n>>> ALL CANNON TANK CHECKS PASSED SUCCESSFULLY! <<<")
		quit(0)

## 释放一个只为本步骤造的临时 "player" 分组节点。queue_free() 是延迟释放，节点在
## 帧结束前仍然算在 get_nodes_in_group("player") 里；enemy.gd::_find_player_target()
## 按最近距离从这个分组里挑目标，如果上一步骤的 player 还挂在原位没有真正离场，
## 下一步骤新建的、特意放得很远的 player 就会被完全忽略——这正是本文件曾经的 bug：
## Step 2 的近距离 player 残留到了 Step 4，导致"玩家远遁应收起驻扎"永远测不出来。
## remove_from_group() 是立即生效的，先脱离分组再 queue_free() 就切断了这条污染路径。
func _retire_test_player(player: Node) -> void:
	player.remove_from_group("player")
	player.queue_free()

func _test_cannon_tank_initialization() -> void:
	print("\n[STEP 1] Testing Cannon Tank initialization and dual frame sets...")
	var scene = load("res://scenes/enemy.tscn")
	if not check(scene != null, "Enemy scene should load"):
		return
	var enemy = scene.instantiate()
	enemy.enemy_type = EnemyScript.EnemyType.CANNON
	root.add_child(enemy)
	enemy.global_position = Vector2(240, 240)

	check(enemy.max_health >= 6, "Cannon Tank base HP should be at least 6")
	check(enemy.speed == 65.0, "Cannon Tank mobile speed should be 65.0")
	check(not enemy.is_cannon_deployed, "Should start in mobile mode")
	check(enemy.cannon_mobile_frames.size() == 6, "Should have 6 mobile frames")
	check(enemy.cannon_deploy_frames.size() == 6, "Should have 6 deployed frames")

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

	check(enemy.is_cannon_deployed, "Cannon tank should transform into deployed siege mode when close to player")
	check(enemy.tank_frames == enemy.cannon_deploy_frames, "Active frames should switch to deployed frames")

	# 2. Verify heavy defense damage reduction while deployed
	var initial_hp = enemy.health
	# Normal 4 damage shot: should be reduced by ~65% -> int(ceil(4 * 0.35)) = 2
	enemy.take_damage(4)
	var damage_taken = initial_hp - enemy.health
	check(damage_taken < 4, "Deployed Cannon Tank should absorb majority of damage (got %d taken of 4)" % damage_taken)
	check(damage_taken == 2, "4 damage with 65% reduction should take 2 damage")

	# Normal 1 damage shot: reduced to minimum 1 damage
	initial_hp = enemy.health
	enemy.take_damage(1)
	check(initial_hp - enemy.health == 1, "1 damage should take 1 damage minimum")

	_retire_test_player(player)
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
	check(enemy.is_cannon_deployed, "Should be deployed")

	# Fire bullet. _shoot() also spawns a muzzle flash + shockwave (and SoundManager
	# parks a throwaway AudioStreamPlayer here too) into the same parent right after
	# the bullet, so the bullet is NOT reliably root's last child — and bullet.gd never
	# joins a "bullet" group despite several other scripts checking for one. Identify
	# it by the "damage" property instead, the same duck-typing idiom bunker.gd/enemy.gd
	# already use elsewhere for "is this a bullet".
	var children_before: Array[Node] = root.get_children()
	enemy._shoot()
	var spawned_bullet: Node = null
	for child in root.get_children():
		if child not in children_before and "damage" in child:
			spawned_bullet = child
			break

	if check(spawned_bullet != null, "Should spawn a bullet node"):
		check(spawned_bullet.damage >= 2, "Deployed siege bullet should deal heavy 2+ damage")
		check(spawned_bullet.is_aoe, "Deployed siege bullet should have AoE blast")
		check(spawned_bullet.can_destroy_steel, "Deployed siege shell should destroy steel obstacles")
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
	check(enemy.is_cannon_deployed, "Should be deployed")

	# Create player far away at 400px distance (> 270px CANNON_UNDEPLOY_DIST)
	var player = CharacterBody2D.new()
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = Vector2(200, 600)

	# Process 3.0 seconds (> 2.5s CANNON_UNDEPLOY_DELAY)
	enemy._process_cannon_siege_behavior(3.0)

	check(not enemy.is_cannon_deployed, "Cannon tank should undeploy when player stays far away")
	check(enemy.tank_frames == enemy.cannon_mobile_frames, "Active frames should revert to mobile frames")

	_retire_test_player(player)
	enemy.queue_free()
	print("  [PASS] Undeployment when player retreats verified.")

func _test_encyclopedia_and_gate_integration() -> void:
	print("\n[STEP 5] Testing Encyclopedia and Main gate integration...")
	# 1. Encyclopedia
	var found_in_enc = false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "enemy_cannon":
			found_in_enc = true
			check(ResourceLoader.exists(entry["icon"]), "Encyclopedia icon should exist: %s" % entry["icon"])
			break
	check(found_in_enc, "Encyclopedia should have 'enemy_cannon'")

	# 2. Main gate
	check(MainScript.ENEMY_MIN_FLOOR.has(EnemyScript.EnemyType.CANNON), "Main ENEMY_MIN_FLOOR should contain CANNON")
	check(MainScript.GATE_FALLBACK_POOL.has(EnemyScript.EnemyType.CANNON), "Main GATE_FALLBACK_POOL should contain CANNON")

	print("  [PASS] Encyclopedia and Main gate integration verified.")
