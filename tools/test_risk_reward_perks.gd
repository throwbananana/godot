extends SceneTree

# Verifies the three new high-risk/high-reward shop perks:
#   ricochet_rounds        -- bullet bounces off obstacles instead of dying,
#                              stack count = bounce count, loses shooter-immunity after bouncing
#   armor_piercing_rounds  -- bullet keeps flying through destructible walls,
#                              stops cancelling opposing bullets on contact
#   amphibious_hull        -- player can enter water tiles, -50% land speed
#
# Bullet collision handlers (_on_body_entered/_on_area_entered) are called
# directly with hand-built fake bodies/areas rather than relying on real
# physics overlap timing in a headless script -- deterministic and avoids
# flaky physics-frame dependent tests.

func _init() -> void:
	# _ready() notifications for nodes added this early (before the engine's
	# first idle frame) don't appear to fire synchronously -- root.add_child()
	# inside plain _init() left player_scene/p1_instance unset even though
	# main.gd's _ready() runs synchronous, non-deferred code. Every other
	# passing test in this repo that boots main.tscn (test_gameplay_runtime.gd,
	# test_act_enemy_theming.gd) defers its body for exactly this reason.
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING RISK/REWARD PERK TEST  <<<")
	print("==================================================")

	_test_ricochet_bounces_and_self_hit_becomes_possible()
	_test_ricochet_exhausted_falls_back_to_normal_destroy()
	_test_armor_piercing_survives_brick_and_steel()
	_test_armor_piercing_stops_cancelling_enemy_bullets()
	_test_normal_bullets_still_cancel_each_other()
	_test_amphibious_water_overlap_and_collision_exception()

	print("\n>>> ALL RISK/REWARD PERK CHECKS PASSED! <<<")
	quit(0)

func _make_bullet(shooter: Node2D, shooter_type: String) -> Node2D:
	var scene = load("res://scenes/bullet.tscn")
	var b = scene.instantiate()
	b.shooter = shooter
	b.shooter_type = shooter_type
	root.add_child(b) # needs to be inside the tree for _ready() to run and read perks
	return b

func _grant(main_node, perk_id: String, player_id: int, stacks: int) -> void:
	for i in range(stacks):
		main_node.rpg_mgr.add_perk(perk_id, player_id)

func _boot_main():
	GameState.reset_campaign(1)
	var main_scene = load("res://scenes/main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	# bullet.gd/player.gd/enemy.gd all locate the battle controller via
	# get_tree().current_scene, which manual root.add_child() does NOT set
	# (only change_scene_to_file()/the initial scene load do). Without this,
	# bullet.gd's _ready() silently finds no rpg_mgr and every perk-derived
	# field defaults to its unarmed value.
	current_scene = main_node
	return main_node

func _test_ricochet_bounces_and_self_hit_becomes_possible() -> void:
	print("\n[STEP] Ricochet: bullet survives a border hit and can then hit its own shooter...")
	var main_node = _boot_main()
	_grant(main_node, "ricochet_rounds", 1, 2)

	var shooter = main_node.p1_instance
	var bullet = _make_bullet(shooter, "player")
	assert(bullet.bounces_remaining == 2, "bullet should read 2 bounces from the perk stack, got %d" % bullet.bounces_remaining)

	var border = StaticBody2D.new()
	border.add_to_group("border")
	root.add_child(border)

	var dir_before = bullet.direction
	bullet._on_body_entered(border)
	assert(not bullet.is_destroyed, "bullet with bounces remaining should survive hitting the border")
	assert(bullet.bounces_remaining == 1, "one bounce should be consumed, got %d remaining" % bullet.bounces_remaining)
	assert(bullet.has_bounced, "has_bounced should be true after ricocheting")

	# Before bouncing, hitting its own shooter is a no-op (early return in
	# _on_body_entered gated on "not has_bounced"). After bouncing, the
	# bullet should actually self-damage the shooter (the risk half of the
	# perk) instead of silently passing through.
	shooter.add_to_group("p1")
	var fresh_bullet = _make_bullet(shooter, "player") # bounces_remaining still 2, has_bounced still false
	fresh_bullet._on_body_entered(shooter)
	# This branch signals destruction via queue_free() directly rather than
	# setting is_destroyed (a pre-existing pattern in the friendly-fire arm,
	# unrelated to this perk) -- is_queued_for_deletion() is the correct check.
	assert(not fresh_bullet.is_queued_for_deletion(), "a fresh (not-yet-bounced) bullet must still be immune to its own shooter")

	bullet._on_body_entered(shooter) # bullet has already bounced once above
	assert(bullet.is_queued_for_deletion(), "a bounced bullet hitting its own shooter should now self-damage and be destroyed")

	border.queue_free()
	bullet.queue_free()
	fresh_bullet.queue_free()
	main_node.queue_free()
	print("  [PASS] Ricochet consumes a bounce on border impact and lifts shooter-immunity after bouncing.")

func _test_ricochet_exhausted_falls_back_to_normal_destroy() -> void:
	print("\n[STEP] Ricochet: bullet dies normally once bounces run out...")
	var main_node = _boot_main()
	_grant(main_node, "ricochet_rounds", 1, 1) # exactly 1 stack

	var bullet = _make_bullet(main_node.p1_instance, "player")
	assert(bullet.bounces_remaining == 1, "expected 1 bounce, got %d" % bullet.bounces_remaining)

	var border = StaticBody2D.new()
	border.add_to_group("border")
	root.add_child(border)

	bullet._on_body_entered(border) # consumes the only bounce
	assert(not bullet.is_destroyed, "first hit should still bounce")
	bullet._on_body_entered(border) # no bounces left
	assert(bullet.is_destroyed, "second hit with no bounces left should destroy the bullet")

	border.queue_free()
	main_node.queue_free()
	print("  [PASS] Ricochet falls back to normal destruction once bounces are exhausted.")

func _test_armor_piercing_survives_brick_and_steel() -> void:
	print("\n[STEP] Armor-piercing: bullet survives brick and destroy-able steel...")
	var main_node = _boot_main()
	_grant(main_node, "armor_piercing_rounds", 1, 1)

	var bullet = _make_bullet(main_node.p1_instance, "player")
	bullet.can_destroy_steel = true # plasma-tier, so it CAN destroy steel too
	assert(bullet.armor_piercing == true, "bullet should read armor_piercing from the perk")

	var brick = StaticBody2D.new()
	brick.add_to_group("brick")
	root.add_child(brick)
	bullet._on_body_entered(brick)
	assert(not bullet.is_destroyed, "armor-piercing bullet should survive hitting brick")

	var steel = StaticBody2D.new()
	steel.add_to_group("steel")
	root.add_child(steel)
	bullet._on_body_entered(steel)
	assert(not bullet.is_destroyed, "armor-piercing + can_destroy_steel bullet should survive hitting steel")

	brick.queue_free()
	steel.queue_free()
	main_node.queue_free()
	print("  [PASS] Armor-piercing bullets pass through brick and destroy-able steel without dying.")

func _test_armor_piercing_stops_cancelling_enemy_bullets() -> void:
	print("\n[STEP] Armor-piercing: no longer cancels opposing bullets on contact...")
	var main_node = _boot_main()
	_grant(main_node, "armor_piercing_rounds", 1, 1)

	var player_bullet = _make_bullet(main_node.p1_instance, "player")
	assert(player_bullet.armor_piercing == true)
	var enemy_bullet_scene = load("res://scenes/bullet.tscn")
	var enemy_bullet = enemy_bullet_scene.instantiate()
	enemy_bullet.shooter_type = "enemy"
	root.add_child(enemy_bullet)

	player_bullet._on_area_entered(enemy_bullet)
	assert(not player_bullet.is_destroyed, "armor-piercing player bullet should not be destroyed by an enemy bullet")
	assert(not enemy_bullet.is_destroyed, "the enemy bullet should also pass through unharmed")

	# Symmetric check: the enemy bullet's OWN handler must also see the
	# player bullet's armor_piercing flag and back off (area_entered fires
	# independently on each side in real physics).
	enemy_bullet._on_area_entered(player_bullet)
	assert(not enemy_bullet.is_destroyed, "enemy bullet's own handler should also skip destruction")
	assert(not player_bullet.is_destroyed)

	player_bullet.queue_free()
	enemy_bullet.queue_free()
	main_node.queue_free()
	print("  [PASS] Armor-piercing suppresses mutual bullet cancellation from both sides.")

func _test_normal_bullets_still_cancel_each_other() -> void:
	print("\n[STEP] Regression: bullets WITHOUT armor-piercing still cancel normally...")
	var main_node = _boot_main() # no perks granted

	var player_bullet = _make_bullet(main_node.p1_instance, "player")
	var enemy_bullet_scene = load("res://scenes/bullet.tscn")
	var enemy_bullet = enemy_bullet_scene.instantiate()
	enemy_bullet.shooter_type = "enemy"
	root.add_child(enemy_bullet)

	assert(player_bullet.armor_piercing == false, "no perk granted -> armor_piercing should be false")
	player_bullet._on_area_entered(enemy_bullet)
	assert(player_bullet.is_destroyed, "plain bullets should still mutually cancel (pre-existing behavior)")

	main_node.queue_free()
	print("  [PASS] Baseline mutual bullet-cancel behavior is unchanged when the perk isn't owned.")

func _test_amphibious_water_overlap_and_collision_exception() -> void:
	print("\n[STEP] Amphibious Hull: water overlap tracking + collision exception grant...")
	var main_node = _boot_main()
	_grant(main_node, "amphibious_hull", 1, 1)

	var fake_water = StaticBody2D.new()
	root.add_child(fake_water)
	main_node.water_bodies.append(fake_water) # can't assign a plain [x] literal to a typed Array[StaticBody2D] property from outside the script

	var p1 = main_node.p1_instance
	assert(not p1.get_collision_exceptions().has(fake_water), "should not have an exception yet before _apply_rpg_stats runs with the perk granted")
	p1._apply_rpg_stats()
	assert(p1.get_collision_exceptions().has(fake_water), "amphibious_hull should add a collision exception against water bodies")

	p1.on_enter_water()
	assert(p1.is_on_water, "on_enter_water() should set is_on_water true")
	p1.on_exit_water()
	assert(not p1.is_on_water, "on_exit_water() should clear is_on_water")

	fake_water.queue_free()
	main_node.queue_free()
	print("  [PASS] Amphibious Hull grants a water collision exception and water-overlap tracking works.")
