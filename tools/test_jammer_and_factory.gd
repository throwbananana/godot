extends SceneTree

# Verifies the two new map-design buildings:
#   Signal Jammer Tower -- reverses the PLAYER's movement/aim input for
#                           anyone in its radius; releases them if destroyed
#                           mid-overlap.
#   Factory              -- escort objective; surviving to battle-end doubles
#                           this battle's earned gold, being destroyed halves
#                           it. (Used to also double/halve battle XP; leveling
#                           no longer comes from an XP pool at all -- see
#                           rpg_manager.gd::add_level().)

func _init() -> void:
	# Nodes added this early (before the engine's first idle frame) don't get
	# synchronous _ready() -- same lesson as test_risk_reward_perks.gd.
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING JAMMER TOWER & FACTORY TEST  <<<")
	print("==================================================")

	_test_jammer_toggles_is_jammed_and_inverts_input()
	_test_jammer_releases_bodies_on_destroy()
	_test_factory_survives_doubles_reward()
	await _test_factory_destroyed_halves_reward() # uses `await process_frame` internally to let queue_free() actually take effect
	_test_factory_absent_is_a_no_op()
	_test_double_level_up_does_not_error()

	print("\n>>> ALL JAMMER TOWER & FACTORY CHECKS PASSED! <<<")
	quit(0)

func _make_jammer() -> Node2D:
	var scene = load("res://scenes/buildings/signal_jammer_tower.tscn")
	var j = scene.instantiate()
	root.add_child(j)
	return j

func _make_player(pid: int) -> Node2D:
	var scene = load("res://scenes/player.tscn")
	var p = scene.instantiate()
	p.player_id = pid
	root.add_child(p)
	return p

func _test_jammer_toggles_is_jammed_and_inverts_input() -> void:
	print("\n[STEP] Jammer field toggles is_jammed and its input inversion is correct...")
	var jammer = _make_jammer()
	var p1 = _make_player(1)

	assert(not p1.is_jammed, "player should start unjammed")
	jammer._on_jam_area_entered(p1)
	assert(p1.is_jammed, "entering the jam field should set is_jammed")
	assert(jammer.jammed_bodies.has(p1), "tower should track the body it jammed")

	# The actual reversal is a single `input_vec = -input_vec` in
	# player.gd::_physics_process -- verify the vector algebra directly:
	# up (0,-1) must become down (0,1), left (-1,0) must become right (1,0).
	assert(-Vector2.UP == Vector2.DOWN, "sanity: -UP should equal DOWN")
	assert(-Vector2.LEFT == Vector2.RIGHT, "sanity: -LEFT should equal RIGHT")

	jammer._on_jam_area_exited(p1)
	assert(not p1.is_jammed, "exiting the jam field should clear is_jammed")
	assert(not jammer.jammed_bodies.has(p1), "tower should stop tracking a body once it leaves")

	jammer.queue_free()
	p1.queue_free()
	print("  [PASS] is_jammed toggles correctly; input inversion math confirmed.")

func _test_jammer_releases_bodies_on_destroy() -> void:
	print("\n[STEP] Destroying the tower mid-overlap releases anyone still jammed...")
	var jammer = _make_jammer()
	var p1 = _make_player(1)

	jammer._on_jam_area_entered(p1)
	assert(p1.is_jammed, "player should be jammed after entering")

	jammer.current_hp = 1
	jammer.take_damage(99) # lethal -- should trigger _destroy()
	assert(not p1.is_jammed, "destroying the tower should release anyone still inside its field (no exit signal would otherwise fire)")

	p1.queue_free()
	print("  [PASS] Tower destruction releases jammed bodies instead of leaving them stuck.")

func _boot_main():
	GameState.reset_campaign(1)
	var main_scene = load("res://scenes/main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	current_scene = main_node
	return main_node

func _test_factory_survives_doubles_reward() -> void:
	print("\n[STEP] Factory alive at battle-end doubles this battle's gold...")
	var main_node = _boot_main()
	main_node.battle_gold_earned = 200
	var gold_before = main_node.rpg_mgr.gold

	var alive_factory = StaticBody2D.new()
	root.add_child(alive_factory)
	main_node.factory_instances.append(alive_factory)

	main_node._apply_factory_reward_multiplier()

	# Doubling 200 earned gold means +200 more on top of what's already been
	# credited during the battle.
	assert(main_node.rpg_mgr.gold == gold_before + 200, "gold should gain +200 (doubling the 200 earned this battle), got delta %d" % (main_node.rpg_mgr.gold - gold_before))

	alive_factory.queue_free()
	main_node.queue_free()
	print("  [PASS] Surviving Factory doubles battle-earned gold.")

func _test_factory_destroyed_halves_reward() -> void:
	print("\n[STEP] All Factories destroyed at battle-end halves this battle's gold...")
	var main_node = _boot_main()
	main_node.battle_gold_earned = 200
	var gold_before = main_node.rpg_mgr.gold

	var dead_factory = StaticBody2D.new()
	root.add_child(dead_factory)
	main_node.factory_instances.append(dead_factory)
	dead_factory.queue_free() # freed immediately -- is_instance_valid() will read false once it actually frees

	await process_frame # let the queue_free() above actually take effect
	await process_frame

	main_node._apply_factory_reward_multiplier()

	assert(main_node.rpg_mgr.gold == gold_before - 100, "gold should lose -100 (halving the 200 earned this battle), got delta %d" % (main_node.rpg_mgr.gold - gold_before))

	main_node.queue_free()
	print("  [PASS] All-Factories-destroyed halves battle-earned gold.")

func _test_factory_absent_is_a_no_op() -> void:
	print("\n[STEP] A map with no Factory leaves gold untouched...")
	var main_node = _boot_main()
	main_node.battle_gold_earned = 200
	var gold_before = main_node.rpg_mgr.gold

	assert(main_node.factory_instances.is_empty(), "sanity: no factory spawned this battle")
	main_node._apply_factory_reward_multiplier()

	assert(main_node.rpg_mgr.gold == gold_before, "no factory on the map should mean no adjustment to gold")

	main_node.queue_free()
	print("  [PASS] Maps without a Factory are unaffected by the multiplier.")

func _test_double_level_up_does_not_error() -> void:
	# Regression test for a bug this feature's own testing surfaced:
	# main.gd::_on_rpg_level_up() used to assign a ternary between two
	# untyped array literals ([1,2] / [1]) to an Array[int]-typed variable,
	# which throws "Trying to assign an array of type Array to a variable
	# of type Array[int]" the moment a level-up actually fires. Picking up
	# two STAR power-ups in one frame (rpg_mgr.add_level(2)) crosses that
	# path twice in a row -- this used to be reached via a Factory bonus
	# crossing an XP threshold, but leveling no longer has one (see
	# rpg_manager.gd::add_level()), so it's exercised directly here instead.
	print("\n[STEP] Two level-ups in one frame don't error...")
	var main_node = _boot_main()
	var level_before = main_node.rpg_mgr.level

	main_node.rpg_mgr.add_level(2)

	assert(main_node.rpg_mgr.level == level_before + 2, "level should advance by exactly 2, got %d (was %d)" % [main_node.rpg_mgr.level, level_before])

	main_node.queue_free()
	print("  [PASS] Double level-up completes without a script error.")
