extends SceneTree

const RPGManager = preload("res://scripts/rpg_manager.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")
const UpgradeSelectionDialog = preload("res://scripts/upgrade_selection_dialog.gd")
const PlayerTank = preload("res://scripts/player.gd")
const EnemyTank = preload("res://scripts/enemy.gd")
const LaserRingCutter = preload("res://scripts/laser_ring_cutter.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("[TEST] Starting Trench Tank (壕沟战坦克) verification suite...")
	print("  current_scene is: ", current_scene)
	var tests_passed: int = 0

	# -------------------------------------------------------------
	# Test 1: RPGManager branch stats and tier promotions
	# -------------------------------------------------------------
	var rpg_mgr = RPGManager.new()
	rpg_mgr.set_branch("trench", 1)
	assert(rpg_mgr.get_branch(1) == "trench", "Branch should be trench")
	assert(rpg_mgr.get_branch_tier(1) == 1, "Branch tier should start at 1")

	var t1_hp = rpg_mgr.get_player_max_hp(1)
	var t1_dmg = rpg_mgr.get_atk_damage(1)
	print("  T1 Trench stats: HP=%d, DMG=%d" % [t1_hp, t1_dmg])
	assert(t1_hp >= 3, "Trench tank T1 should have HP bonus (base + 2 >= 3)")
	assert(t1_dmg >= 2, "Trench tank T1 should have DMG bonus (base + 1 >= 2)")

	# Promote to Tier 2
	rpg_mgr.promote_branch_tier(1)
	assert(rpg_mgr.get_branch_tier(1) == 2, "Branch tier should be 2")
	var t2_hp = rpg_mgr.get_player_max_hp(1)
	var t2_dmg = rpg_mgr.get_atk_damage(1)
	print("  T2 Trench stats: HP=%d, DMG=%d" % [t2_hp, t2_dmg])
	assert(t2_hp > t1_hp, "T2 Trench tank should have higher HP than T1")
	assert(t2_dmg > t1_dmg, "T2 Trench tank should have higher DMG than T1")
	tests_passed += 1
	print("  [PASS] Test 1: RPGManager branch stats verified.")

	# -------------------------------------------------------------
	# Test 2: Encyclopedia Registry (UPGRADES & TANKS)
	# -------------------------------------------------------------
	var found_tree: bool = false
	var found_player: bool = false
	var found_enemy: bool = false
	for entry in EncyclopediaData.ENTRIES:
		var eid = entry.get("id", "")
		if eid == "tree_trench":
			found_tree = true
			assert(entry.get("category") == "UPGRADES", "tree_trench should be in UPGRADES")
		elif eid == "player_trench":
			found_player = true
			assert(entry.get("category") == "TANKS", "player_trench should be in TANKS")
		elif eid == "enemy_trench":
			found_enemy = true
			assert(entry.get("category") == "TANKS", "enemy_trench should be in TANKS")

	assert(found_tree, "Encyclopedia must have tree_trench entry")
	assert(found_player, "Encyclopedia must have player_trench entry")
	assert(found_enemy, "Encyclopedia must have enemy_trench entry")
	tests_passed += 1
	print("  [PASS] Test 2: Encyclopedia registry verified.")

	# -------------------------------------------------------------
	# Test 3: Upgrade Selection Dialog Options & UI Icon
	# -------------------------------------------------------------
	var test_rpg = RPGManager.new()
	var dialog = UpgradeSelectionDialog.new()
	var default_choices = dialog._generate_choices(test_rpg, 1)
	var has_trench_branch: bool = false
	for ch in default_choices:
		if ch.get("branch") == "trench":
			has_trench_branch = true
			break
	assert(has_trench_branch, "Default branch choices must offer trench branch")

	# Set branch to trench and check tier 2 evolution
	test_rpg.set_branch("trench", 1)
	var trench_choices = dialog._generate_choices(test_rpg, 1)
	var has_trench_t2: bool = false
	for ch in trench_choices:
		if ch.get("type") == "tier_up" and ("Trench" in ch.get("name", "") or "战壕" in ch.get("name", "") or "壕沟" in ch.get("name", "")):
			has_trench_t2 = true
			break
	assert(has_trench_t2, "Trench branch should offer Tier 2 evolution")
	dialog.free()

	# Check UI icon
	var icon = UIThemeHelper.get_perk_icon({"type": "branch", "branch": "trench"})
	assert(icon != null, "Perk icon for trench branch must exist")
	tests_passed += 1
	print("  [PASS] Test 3: Upgrade selection dialog and UI icon verified.")

	# -------------------------------------------------------------
	# Test 4: LaserRingCutter Bullet Slicing / Interception
	# -------------------------------------------------------------
	var root = Node2D.new()
	get_root().add_child(root)

	var cutter = LaserRingCutter.create_cut(root, Vector2(200, 200), Vector2.UP, null, "player", 2, false, 48.0)
	assert(cutter != null, "LaserRingCutter should be instantiated")
	assert(cutter.team == "player", "Cutter team should be player")
	assert(cutter.can_destroy_steel == false, "T1 cutter should not destroy steel by default")

	# Spawn an enemy bullet within the cut zone
	var bullet_scene = load("res://scenes/bullet.tscn")
	var enemy_bullet = bullet_scene.instantiate()
	enemy_bullet.shooter_type = "enemy"
	enemy_bullet.direction = Vector2.DOWN
	root.add_child(enemy_bullet)
	enemy_bullet.global_position = Vector2(200, 180) # 20px above player, within cut zone

	# Spawn a friendly player bullet in the zone
	var player_bullet = bullet_scene.instantiate()
	player_bullet.shooter_type = "player"
	player_bullet.direction = Vector2.UP
	root.add_child(player_bullet)
	player_bullet.global_position = Vector2(200, 185)

	# Execute sweep
	cutter._perform_slice_sweep()

	assert(enemy_bullet.is_queued_for_deletion(), "Enemy bullet in cutting arc must be sliced/destroyed")
	assert(not player_bullet.is_queued_for_deletion(), "Friendly bullet must NOT be destroyed by own cutter")
	player_bullet.queue_free()
	cutter.queue_free()
	tests_passed += 1
	print("  [PASS] Test 4: LaserRingCutter bullet slicing and friend-or-foe protection verified.")

	# -------------------------------------------------------------
	# Test 5: Cutting Tier Parity with Terrain (Steel vs Brick)
	# -------------------------------------------------------------
	# Create a dummy brick static body
	var brick_body = StaticBody2D.new()
	brick_body.add_to_group("brick")
	root.add_child(brick_body)
	brick_body.global_position = Vector2(200, 180)

	# Create a dummy steel static body
	var steel_body = StaticBody2D.new()
	steel_body.add_to_group("steel")
	root.add_child(steel_body)
	steel_body.global_position = Vector2(200, 175)

	# Normal cutter (cannot destroy steel)
	var normal_cutter = LaserRingCutter.create_cut(root, Vector2(200, 200), Vector2.UP, null, "player", 1, false, 48.0)
	normal_cutter._perform_slice_sweep()

	assert(brick_body.is_queued_for_deletion(), "Normal cutter should slice brick terrain")
	assert(not steel_body.is_queued_for_deletion(), "Normal cutter should NOT slice steel terrain")
	normal_cutter.queue_free()

	# Steel-cutting cutter (can_destroy_steel == true)
	var steel_cutter = LaserRingCutter.create_cut(root, Vector2(200, 200), Vector2.UP, null, "player", 3, true, 54.0)
	steel_cutter._perform_slice_sweep()

	assert(steel_body.is_queued_for_deletion(), "Steel-cutting tier cutter MUST slice steel terrain")
	steel_cutter.queue_free()
	tests_passed += 1
	print("  [PASS] Test 5: Cutting tier parity (brick vs steel destruction) verified.")

	# -------------------------------------------------------------
	# Test 6: Enemy Trench Tank Stats & Firing
	# -------------------------------------------------------------
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	enemy.enemy_type = EnemyTank.EnemyType.TRENCH
	root.add_child(enemy)
	enemy.global_position = Vector2(400, 400)
	enemy.facing_direction = Vector2.RIGHT

	assert(enemy.max_health == 4, "Enemy Trench tank should have 4 HP")
	assert(enemy.speed == 72.0, "Enemy Trench tank should have 72 speed")

	# Trigger shoot
	enemy._shoot()
	var found_enemy_cutter: bool = false
	for child in root.get_children():
		if child.is_in_group("laser_ring_cutter") and child.get("team") == "enemy":
			found_enemy_cutter = true
			child.queue_free()
			break
	assert(found_enemy_cutter, "Enemy Trench tank _shoot() must spawn LaserRingCutter with team 'enemy'")
	enemy.queue_free()
	tests_passed += 1
	print("  [PASS] Test 6: Enemy Trench tank stats and cutting attack verified.")

	# -------------------------------------------------------------
	# Test 7: Player Trench Branch Firing & Scaling
	# -------------------------------------------------------------
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	player.player_id = 1
	root.add_child(player)
	player.global_position = Vector2(500, 500)
	player.facing_direction = Vector2.UP

	# Activate trench branch on player (Tier 1)
	GameState.tank_branch = "trench"
	GameState.branch_tier = 1
	player._update_tier_appearance()
	assert(player.tank_frames.size() == 6, "Player T1 trench tank sprite frames should be loaded")

	# Shoot at Tier 1
	player._shoot()
	var player_cutter_t1: Node2D = null
	for child in root.get_children():
		if child.is_in_group("laser_ring_cutter") and child.get("team") == "player":
			player_cutter_t1 = child
			break
	assert(player_cutter_t1 != null, "Player with trench branch must shoot LaserRingCutter")
	assert(player_cutter_t1.get("can_destroy_steel") == false, "Player T1 trench cutter should not cut steel by default")
	root.remove_child(player_cutter_t1)
	player_cutter_t1.free()

	# Upgrade player to Tier 2 branch
	GameState.branch_tier = 2
	player._update_tier_appearance()
	assert(player.tank_frames.size() == 6, "Player T2 trench tank sprite frames should be loaded")

	player.can_fire = true
	player.fire_timer = 0.0
	player._shoot()

	var player_cutter_t2: Node2D = null
	for c in root.get_children():
		if c.is_in_group("laser_ring_cutter") and c.get("team") == "player" and not c.is_queued_for_deletion():
			player_cutter_t2 = c
	assert(player_cutter_t2 != null, "Player T2 branch must shoot LaserRingCutter")
	assert(player_cutter_t2.get("can_destroy_steel") == true, "Player T2 branch cutter MUST have can_destroy_steel == true")
	assert(float(player_cutter_t2.get("cutting_radius")) >= 50.0, "Player T2 branch cutter should have larger cutting radius (>= 50px)")
	player_cutter_t2.queue_free()
	player.queue_free()

	# Reset GameState
	GameState.tank_branch = "default"
	GameState.branch_tier = 1

	tests_passed += 1
	print("  [PASS] Test 7: Player Trench branch firing and tier scaling verified.")

	root.queue_free()

	print("\n============================================================")
	print("ALL %d TESTS PASSED SUCCESSFULLY! Trench Tank is fully operational!" % tests_passed)
	print("============================================================\n")
	quit(0)
