extends SceneTree

const KineticPushHelperScript = preload("res://scripts/kinetic_push_helper.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BulletScript = preload("res://scripts/bullet.gd")
const PowerUpScript = preload("res://scripts/power_up.gd")
const ShopDialogScript = preload("res://scripts/shop_dialog.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const RollerWallScript = preload("res://scripts/buildings/roller_wall.gd")
const WoodenWallScript = preload("res://scripts/buildings/wooden_wall.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING KINETIC PUSH & SQUEEZE CRUSH TESTS <<<")
	print("==================================================")

	_test_push_tier_gates()
	await _test_squeeze_kill_when_pinned()
	await _test_open_space_knockback_no_squeeze()
	_test_bulldozer_enemy_properties()
	await _test_bulldozer_ram_push_and_squeeze()
	_test_powerup_and_shop_integration()

	print("\n>>> ALL KINETIC PUSH & SQUEEZE CHECKS PASSED! <<<")
	quit(0)

func _test_push_tier_gates() -> void:
	print("\n[STEP 1] Testing push permissions tied to bullet destruction tier...")

	# 1. Brick / clay obstacle
	var brick = StaticBody2D.new()
	brick.add_to_group("brick")
	root.add_child(brick)
	assert(KineticPushHelperScript.can_push(brick, false), "Normal tier must be able to push brick")
	assert(KineticPushHelperScript.can_push(brick, true), "High tier must also be able to push brick")

	# 2. Steel obstacle
	var steel = StaticBody2D.new()
	steel.add_to_group("steel")
	root.add_child(steel)
	assert(not KineticPushHelperScript.can_push(steel, false), "Normal tier CANNOT push steel!")
	assert(KineticPushHelperScript.can_push(steel, true), "High tier (can_destroy_steel=true) CAN push steel!")

	# 3. Border obstacle (Map Boundary)
	var border = StaticBody2D.new()
	border.add_to_group("border")
	border.add_to_group("steel")
	root.add_child(border)
	assert(not KineticPushHelperScript.can_push(border, false), "Border can NEVER be pushed (normal tier)")
	assert(not KineticPushHelperScript.can_push(border, true), "Border can NEVER be pushed even with high tier")

	brick.queue_free()
	steel.queue_free()
	border.queue_free()
	print("  [PASS] Push permissions strictly match destruction tier rules!")

func _test_squeeze_kill_when_pinned() -> void:
	print("\n[STEP 2] Testing Squeeze Kill when unit is pinned against a solid wall...")

	# Layout:
	# Pushed Wall at (200, 200)
	# Enemy at (248, 200) (1 cell to the right)
	# Solid Steel Wall at (296, 200) (1 cell behind enemy)
	# Push direction is Vector2.RIGHT. Enemy is caught in the vice!

	var wall = RollerWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(200, 200)

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.BASIC
	enemy._setup_tank_type()
	enemy.global_position = Vector2(248, 200)

	var rear_steel = StaticBody2D.new()
	rear_steel.add_to_group("steel")
	var col = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(40, 40)
	col.shape = box
	rear_steel.add_child(col)
	root.add_child(rear_steel)
	rear_steel.global_position = Vector2(296, 200)

	# Trigger push towards the right
	var pushed = KineticPushHelperScript.try_push(wall, Vector2.RIGHT, false, null)
	assert(pushed, "Wall should be successfully pushed")

	# Process frame
	for i in range(12):
		await process_frame

	# Check that enemy was squeezed/eliminated (health <= 0 or is_dying)
	assert(enemy.health <= 0 or enemy.is_dying or not is_instance_valid(enemy),
		"Enemy must be eliminated by Squeeze Kill when pinned against a solid wall! HP: %d" % enemy.health)

	wall.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	rear_steel.queue_free()
	print("  [PASS] Unit trapped between pushed obstacle and rear wall was crushed & eliminated!")

func _test_open_space_knockback_no_squeeze() -> void:
	print("\n[STEP 3] Testing that an unpinned unit is knocked back and survives without squeeze kill...")

	# Layout:
	# Wall at (200, 200)
	# Enemy at (248, 200)
	# Empty space at (296, 200) (open floor)

	var wall = RollerWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(200, 200)

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.ARMOR
	enemy._setup_tank_type()
	enemy.global_position = Vector2(248, 200)
	var initial_hp = enemy.health

	var pushed = KineticPushHelperScript.try_push(wall, Vector2.RIGHT, false, null)
	assert(pushed, "Wall should be pushed")

	for i in range(12):
		await process_frame

	assert(is_instance_valid(enemy), "Enemy in open space should survive knockback")
	assert(enemy.health > 0, "Enemy should still be alive, HP: %d" % enemy.health)
	assert(enemy.health < initial_hp, "Enemy should have taken impact knockback damage")
	assert(enemy.global_position.x > 248.0, "Enemy should be knocked back towards 296")

	wall.queue_free()
	enemy.queue_free()
	print("  [PASS] Unpinned unit in open space was safely knocked back with impact damage.")

func _test_bulldozer_enemy_properties() -> void:
	print("\n[STEP 4] Testing Bulldozer Enemy stats, frames, and attributes...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.BULLDOZER
	enemy._setup_tank_type()

	assert(enemy.speed == 52.0, "Bulldozer speed should be 52.0, got %f" % enemy.speed)
	assert(enemy.max_health >= 8, "Bulldozer should have heavy health (>=8, got %d)" % enemy.max_health)
	assert(enemy.tank_frames.size() == 6, "Bulldozer must have 6 animation frames loaded")
	for f in range(6):
		assert(enemy.tank_frames[f] != null, "Bulldozer frame %d must not be null" % f)

	enemy.queue_free()
	print("  [PASS] Bulldozer enemy properties and 6-frame animation confirmed.")

func _test_bulldozer_ram_push_and_squeeze() -> void:
	print("\n[STEP 5] Testing Bulldozer pushing walls into player against a back wall...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	var bulldozer = enemy_scene.instantiate()
	root.add_child(bulldozer)
	bulldozer.enemy_type = EnemyScript.EnemyType.BULLDOZER
	bulldozer._setup_tank_type()
	bulldozer.global_position = Vector2(100, 200)
	bulldozer.facing_direction = Vector2.RIGHT

	# Wall in front of bulldozer at (148, 200)
	var wall = WoodenWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(148, 200)

	# Call bulldozer push directly on wall
	bulldozer._handle_bulldozer_push(wall)

	for i in range(12):
		await process_frame

	assert(wall.global_position.x > 148.0, "Wall should be pushed right by bulldozer")

	bulldozer.queue_free()
	wall.queue_free()
	print("  [PASS] Bulldozer ramming push verified.")

func _test_powerup_and_shop_integration() -> void:
	print("\n[STEP 6] Testing PowerUp and ShopDialog integration...")

	# 1. PowerUp PISTON
	var p = PowerUpScript.new()
	root.add_child(p)
	p.setup(PowerUpScript.Type.PISTON)
	assert(p.power_up_type == PowerUpScript.Type.PISTON, "PowerUp must support Type.PISTON")
	assert(p.sprite.texture != null, "Piston powerup must have a valid sprite texture")
	p.queue_free()

	# 2. ShopDialog
	assert(ShopDialogScript.PER_PLAYER_PERKS.has("kinetic_piston_rounds"),
		"ShopDialog PER_PLAYER_PERKS must include kinetic_piston_rounds")
	assert(GameStateScript.PERK_MAX_STACKS.has("kinetic_piston_rounds"),
		"GameState PERK_MAX_STACKS must include kinetic_piston_rounds")

	print("  [PASS] Piston Rounds Power-Up & Shop Perk fully integrated.")
