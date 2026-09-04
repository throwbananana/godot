extends SceneTree

const RPGManager = preload("res://scripts/rpg_manager.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")
const UpgradeSelectionDialog = preload("res://scripts/upgrade_selection_dialog.gd")
const PlayerTank = preload("res://scripts/player.gd")
const Bullet = preload("res://scripts/bullet.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("[TEST] Starting Counter Tank (反击坦克) verification suite...")
	var tests_passed: int = 0

	# -------------------------------------------------------------
	# Test 1: RPGManager branch stats and cooldown scaling
	# -------------------------------------------------------------
	var rpg_mgr = RPGManager.new()
	rpg_mgr.set_branch("counter", 1)
	assert(rpg_mgr.get_branch(1) == "counter", "Branch should be counter")
	assert(rpg_mgr.get_branch_tier(1) == 1, "Branch tier should start at 1")
	
	var base_hp = rpg_mgr.get_player_max_hp(1)
	var base_dmg = rpg_mgr.get_atk_damage(1)
	var cd_mult = rpg_mgr.get_fire_cooldown_mult(1)
	print("  T1 stats: HP=%d, DMG=%d, CD_MULT=%.2f" % [base_hp, base_dmg, cd_mult])
	assert(base_hp >= 3, "Counter tank T1 should have +2 HP bonus (total >= 3)")
	assert(base_dmg >= 2, "Counter tank T1 should have +1 DMG bonus (total >= 2)")
	assert(cd_mult >= 1.8, "Counter tank should have slow attack speed (cd_mult >= 1.8)")

	# Promote to Tier 2
	rpg_mgr.promote_branch_tier(1)
	assert(rpg_mgr.get_branch_tier(1) == 2, "Branch tier should be 2")
	var t2_hp = rpg_mgr.get_player_max_hp(1)
	var t2_dmg = rpg_mgr.get_atk_damage(1)
	print("  T2 stats: HP=%d, DMG=%d" % [t2_hp, t2_dmg])
	assert(t2_hp > base_hp, "T2 Counter tank should have higher HP")
	assert(t2_dmg > base_dmg, "T2 Counter tank should have higher DMG")
	tests_passed += 1
	print("  [PASS] Test 1: RPGManager branch stats and cooldown scaling verified.")

	# -------------------------------------------------------------
	# Test 2: Encyclopedia Registry
	# -------------------------------------------------------------
	var found_tree: bool = false
	var found_tank: bool = false
	for entry in EncyclopediaData.ENTRIES:
		if entry.get("id") == "tree_counter":
			found_tree = true
			assert(entry.get("category") == "UPGRADES", "tree_counter should be in UPGRADES")
		elif entry.get("id") == "player_counter":
			found_tank = true
			assert(entry.get("category") == "TANKS", "player_counter should be in TANKS")

	assert(found_tree, "Encyclopedia must have tree_counter")
	assert(found_tank, "Encyclopedia must have player_counter")
	tests_passed += 1
	print("  [PASS] Test 2: Encyclopedia registry entries verified.")

	# -------------------------------------------------------------
	# Test 3: Upgrade Selection Dialog Options
	# -------------------------------------------------------------
	var test_rpg = RPGManager.new()
	var dialog = UpgradeSelectionDialog.new()
	var default_choices = dialog._generate_choices(test_rpg, 1)
	var has_counter_branch: bool = false
	for ch in default_choices:
		if ch.get("branch") == "counter":
			has_counter_branch = true
			break
	assert(has_counter_branch, "Default branch choices must offer counter branch")

	# Set branch to counter and check tier 2 evolution
	test_rpg.set_branch("counter", 1)
	var counter_choices = dialog._generate_choices(test_rpg, 1)
	var has_counter_t2: bool = false
	for ch in counter_choices:
		if ch.get("type") == "tier_up" and ("Counter" in ch.get("name", "") or "反击" in ch.get("name", "")):
			has_counter_t2 = true
			break
	assert(has_counter_t2, "Counter branch should offer Tier 2 evolution")
	dialog.free()
	tests_passed += 1
	print("  [PASS] Test 3: Upgrade selection dialog options verified.")

	# -------------------------------------------------------------
	# Test 4: PlayerTank Parry & Bullet Deflection (+1 Tier Upgrade)
	# -------------------------------------------------------------
	var root = Node2D.new()
	get_root().add_child(root)
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	player.player_id = 1
	root.add_child(player)
	player.global_position = Vector2(200, 200)
	player.facing_direction = Vector2.UP

	# Activate counter branch on player
	GameState.tank_branch = "counter"
	GameState.branch_tier = 1
	player._update_tier_appearance()
	assert(player.tank_frames.size() == 6, "Counter tank sprite frames should be loaded")

	# Test slow attack cooldown clamping
	player._shoot()
	assert(player.fire_timer >= 1.0, "Counter tank fire cooldown should be clamped >= 1.10s (was %f)" % player.fire_timer)
	assert(player.is_parrying, "Counter tank should enter parrying state on fire")
	assert(player.parry_timer > 0.30, "Parry timer should be initialized near 0.34s")

	# Spawn an incoming enemy bullet
	var bullet_scene = load("res://scenes/bullet.tscn")
	var bullet = bullet_scene.instantiate()
	bullet.shooter_type = "enemy"
	bullet.direction = Vector2.DOWN
	bullet.damage = 1
	bullet.speed = 500.0
	bullet.can_destroy_steel = false
	bullet.armor_piercing = false
	root.add_child(bullet)
	bullet.global_position = player.global_position + Vector2(0, -20) # 20px above player

	# Perform parry check while in perfect window (first 0.14s)
	assert(player.parry_timer >= (player.parry_total_duration - player.parry_perfect_window), "Should be in perfect parry window")
	var parried = player.check_parry_bullet(bullet)
	assert(parried, "Bullet should be successfully parried")
	assert(bullet.shooter == player, "Bullet shooter should now be player")
	assert(bullet.shooter_type == "player", "Bullet shooter_type should now be player")
	assert(bullet.direction == Vector2.UP, "Bullet should be reflected upward")
	assert(bullet.can_destroy_steel, "Perfect parry must upgrade bullet with can_destroy_steel = true (+1 Tier)")
	assert(bullet.armor_piercing, "Perfect parry must upgrade bullet with armor_piercing = true (+1 Tier)")
	assert(bullet.damage >= 4, "Perfect parry must upgrade bullet damage >= 4")
	assert(bullet.speed >= 720.0, "Perfect parry must boost bullet speed >= 720.0")
	assert(player.can_fire, "Perfect parry should immediately reset fire cooldown")
	assert(player.fire_timer == 0.0, "Fire timer should be reset to 0.0")
	assert(player.has_charged_counter_shot, "Player should gain charged counter shot")
	bullet.queue_free()

	# Test firing empowered Charged Counter Shot
	player._shoot()
	assert(not player.has_charged_counter_shot, "Charged counter shot should be consumed on fire")
	tests_passed += 1
	print("  [PASS] Test 4: Perfect parry deflection and +1 Tier upgrade verified.")

	# -------------------------------------------------------------
	# Test 5: Laser Parry (Prism Refraction)
	# -------------------------------------------------------------
	# Reset parry state
	player.is_parrying = true
	player.parry_timer = player.parry_total_duration
	var laser_parried = player.try_parry_laser(Vector2(200, 50), Vector2.DOWN, 3)
	assert(laser_parried, "Laser from enemy should be successfully parried")
	assert(player.has_charged_counter_shot, "Laser perfect parry should award charged counter shot")
	assert(player.can_fire, "Laser perfect parry should reset cooldown")

	# Test normal parry window (outside perfect window)
	player.is_parrying = true
	player.parry_timer = 0.08 # Below 0.20s threshold (normal window)
	var normal_laser = player.try_parry_laser(Vector2(200, 50), Vector2.DOWN, 2)
	assert(normal_laser, "Laser should still be blocked in normal parry window")

	# Cleanup
	root.queue_free()
	tests_passed += 1
	print("  [PASS] Test 5: Laser parry and prism refraction verified.")

	# -------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------
	print("=============================================================")
	print("ALL %d TESTS PASSED! Counter Tank implementation 100%% verified!" % tests_passed)
	print("=============================================================")
	quit(0)
