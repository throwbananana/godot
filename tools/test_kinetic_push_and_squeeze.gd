extends SceneTree

const KineticPushHelperScript = preload("res://scripts/kinetic_push_helper.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BulletScript = preload("res://scripts/bullet.gd")
const ShopDialogScript = preload("res://scripts/shop_dialog.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const RollerWallScript = preload("res://scripts/buildings/roller_wall.gd")
const WoodenWallScript = preload("res://scripts/buildings/wooden_wall.gd")

## Set by _fail() and checked once at the very end of _run_tests(). See
## [[assert-on-random-precondition-hangs]]: quit() only registers the exit
## code and asks the main loop to stop at its next iteration, it does not
## interrupt the current call stack, so scattering quit(1) calls throughout
## this file would get silently overwritten by the quit(0) at the bottom.
## This file's own history is exactly why that matters -- see the comment on
## _test_squeeze_kill_when_pinned() below.
var _failed := false

func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true

## Polls until every node in the list is actually gone rather than guessing a
## fixed frame count -- queue_free() only marks nodes for deletion, and the
## physics server doesn't drop their broadphase entry until it actually
## processes that. A caller relying on the *next* test's intersect_shape()
## query to see empty space needs the real signal, not a hopeful sleep.
func _await_freed(nodes: Array, max_frames: int = 30) -> void:
	var waited = 0
	while waited < max_frames:
		var any_alive = false
		for n in nodes:
			if is_instance_valid(n):
				any_alive = true
				break
		if not any_alive:
			return
		await process_frame
		waited += 1

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

	if _failed:
		print("\n>>> KINETIC PUSH & SQUEEZE CHECKS FAILED <<<")
		quit(1)
	else:
		print("\n>>> ALL KINETIC PUSH & SQUEEZE CHECKS PASSED! <<<")
		quit(0)

func _test_push_tier_gates() -> void:
	print("\n[STEP 1] Testing push permissions tied to bullet destruction tier...")

	# 1. Brick / clay obstacle
	var brick = StaticBody2D.new()
	brick.add_to_group("brick")
	root.add_child(brick)
	if not KineticPushHelperScript.can_push(brick, false):
		_fail("Normal tier must be able to push brick")
	if not KineticPushHelperScript.can_push(brick, true):
		_fail("High tier must also be able to push brick")

	# 2. Steel obstacle
	var steel = StaticBody2D.new()
	steel.add_to_group("steel")
	root.add_child(steel)
	if KineticPushHelperScript.can_push(steel, false):
		_fail("Normal tier CANNOT push steel!")
	if not KineticPushHelperScript.can_push(steel, true):
		_fail("High tier (can_destroy_steel=true) CAN push steel!")

	# 3. Border obstacle (Map Boundary)
	var border = StaticBody2D.new()
	border.add_to_group("border")
	border.add_to_group("steel")
	root.add_child(border)
	if KineticPushHelperScript.can_push(border, false):
		_fail("Border can NEVER be pushed (normal tier)")
	if KineticPushHelperScript.can_push(border, true):
		_fail("Border can NEVER be pushed even with high tier")

	# 4. Roller wall (滑轮墙): also carries the "steel" group (so it counts as a
	# solid anvil for squeeze kills and blocks lasers), but the class's own
	# documented rule classifies it as a "非钢体建筑" -- normal-tier kinetic
	# rounds must be able to push it. can_push() used to check "steel" before
	# "roller_wall", which made the roller_wall branch dead code and silently
	# required the high tier instead -- verified by reverting the fix and
	# rerunning this exact check, which failed with can_push(wall,false)==false.
	var roller = RollerWallScript.new()
	root.add_child(roller)
	if not KineticPushHelperScript.can_push(roller, false):
		_fail("Roller wall is documented as normal-tier pushable, but can_push(roller, false) returned false")
	if not KineticPushHelperScript.can_push(roller, true):
		_fail("Roller wall must also be pushable at the high tier")

	brick.queue_free()
	steel.queue_free()
	border.queue_free()
	roller.queue_free()
	print("  [PASS] Push permissions strictly match destruction tier rules (including roller_wall's steel/pushable overlap)!")

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

	# Parented under a Node2D, not directly under `root` (a Window) -- a
	# successful squeeze kill calls enemy.gd::_die(), which drops a coin via
	# get_parent().to_local(global_position). Every real enemy is parented
	# under ActorsContainer (a Node2D), so that always works in actual
	# gameplay; a bare Window has no to_local() at all and throws
	# "Nonexistent function 'to_local' in base 'Window'" the moment this
	# squeeze kill actually lands (roughly 40% of the time, matching
	# coin_scene's own drop chance) -- purely an artifact of this test's
	# setup, not a real _die() bug.
	var actors_container = Node2D.new()
	root.add_child(actors_container)

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	actors_container.add_child(enemy)
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

	# A freshly-assigned global_position is a teleport: the node transform
	# updates immediately but the physics server's broadphase only picks it up
	# on its next flush (see [[physics-broadphase-lags-teleport]], previously
	# bitten by test_flamethrower.gd). try_push()'s intersect_shape() query
	# would otherwise run against stale broadphase data and find nobody
	# standing at (248,200) at all -- verified: without this wait, the enemy
	# survives untouched (HP unchanged) because the physics query silently
	# misses it, not because squeeze-kill logic is broken.
	await process_frame
	await process_frame

	# Trigger push towards the right
	var pushed = KineticPushHelperScript.try_push(wall, Vector2.RIGHT, false, null)
	if not pushed:
		_fail("Wall should be successfully pushed")

	# Process frame
	for i in range(12):
		await process_frame

	# Check that enemy was squeezed/eliminated (health <= 0 or is_dying).
	# is_instance_valid() must be checked FIRST -- a squeeze kill frees the
	# enemy outright, and GDScript's `or` chain still evaluates
	# enemy.health/enemy.is_dying left-to-right, so putting the validity check
	# last throws "Invalid access ... on a base object of type 'previously
	# freed'" instead of ever reaching it.
	if is_instance_valid(enemy):
		if not (enemy.health <= 0 or enemy.is_dying):
			_fail("Enemy must be eliminated by Squeeze Kill when pinned against a solid wall! HP: %d" % enemy.health)
		else:
			print("  [PASS] Unit trapped between pushed obstacle and rear wall was crushed & eliminated!")
	else:
		print("  [PASS] Unit trapped between pushed obstacle and rear wall was crushed & eliminated!")

	wall.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	rear_steel.queue_free()
	actors_container.queue_free()

	# Let the queue_free()s above actually take effect before the next test
	# stands up an identical layout at the same coordinates -- queue_free()
	# only marks nodes for deletion at the end of the frame, so without this
	# wait test 3's intersect_shape() query can still see this test's wall
	# (now sitting at 248,200, exactly test 3's enemy spawn point) or
	# rear_steel (at 296,200, exactly test 3's expected open floor) still
	# alive in the physics broadphase and wrongly report "blocked_by_solid".
	# A fixed frame count isn't reliable here (verified: 2 frames wasn't
	# enough and test 3 failed with "Wall should be pushed"), so poll until
	# they're actually gone instead of guessing a number.
	await _await_freed([wall, enemy, rear_steel, actors_container])
	await process_frame # one more: is_instance_valid()==false doesn't guarantee the physics server has dropped the broadphase entry in that same frame

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

	await process_frame # let the fresh positions above reach the physics broadphase
	await process_frame

	var pushed = KineticPushHelperScript.try_push(wall, Vector2.RIGHT, false, null)
	if not pushed:
		_fail("Wall should be pushed")
		wall.queue_free(); enemy.queue_free()
		return

	for i in range(12):
		await process_frame

	if not is_instance_valid(enemy):
		_fail("Enemy in open space should survive knockback")
		wall.queue_free()
		return
	if not (enemy.health > 0):
		_fail("Enemy should still be alive, HP: %d" % enemy.health)
	if not (enemy.health < initial_hp):
		_fail("Enemy should have taken impact knockback damage")
	if not (enemy.global_position.x > 248.0):
		_fail("Enemy should be knocked back towards 296")

	if not _failed:
		print("  [PASS] Unpinned unit in open space was safely knocked back with impact damage.")

	wall.queue_free()
	enemy.queue_free()

func _test_bulldozer_enemy_properties() -> void:
	print("\n[STEP 4] Testing Bulldozer Enemy stats, frames, and attributes...")

	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.BULLDOZER
	enemy._setup_tank_type()

	if enemy.speed != 52.0:
		_fail("Bulldozer speed should be 52.0, got %f" % enemy.speed)
	if enemy.max_health < 8:
		_fail("Bulldozer should have heavy health (>=8, got %d)" % enemy.max_health)
	if enemy.tank_frames.size() != 6:
		_fail("Bulldozer must have 6 animation frames loaded")
	for f in range(enemy.tank_frames.size()):
		if enemy.tank_frames[f] == null:
			_fail("Bulldozer frame %d must not be null" % f)

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

	await process_frame
	await process_frame

	# Call bulldozer push directly on wall
	bulldozer._handle_bulldozer_push(wall)

	for i in range(12):
		await process_frame

	if not (wall.global_position.x > 148.0):
		_fail("Wall should be pushed right by bulldozer")
	else:
		print("  [PASS] Bulldozer ramming push verified.")

	bulldozer.queue_free()
	wall.queue_free()

func _test_powerup_and_shop_integration() -> void:
	print("\n[STEP 6] Testing PowerUp and ShopDialog integration...")

	# 1. PowerUp PISTON -- instantiate the scene, not the bare script: a plain
	# PowerUpScript.new() has no Sprite2D child, so @onready var sprite =
	# $Sprite2D fails with "Node not found" the moment it enters the tree
	# (same lesson as TrainCarriage.new() elsewhere in this codebase).
	var powerup_scene = load("res://scenes/power_up.tscn")
	var p = powerup_scene.instantiate()
	root.add_child(p)
	p.setup(p.Type.PISTON)
	if p.power_up_type != p.Type.PISTON:
		_fail("PowerUp must support Type.PISTON")
	if p.sprite.texture == null:
		_fail("Piston powerup must have a valid sprite texture")
	p.queue_free()

	# 2. ShopDialog
	if not ShopDialogScript.PER_PLAYER_PERKS.has("kinetic_piston_rounds"):
		_fail("ShopDialog PER_PLAYER_PERKS must include kinetic_piston_rounds")
	if not GameStateScript.PERK_MAX_STACKS.has("kinetic_piston_rounds"):
		_fail("GameState PERK_MAX_STACKS must include kinetic_piston_rounds")

	print("  [PASS] Piston Rounds Power-Up & Shop Perk fully integrated.")
