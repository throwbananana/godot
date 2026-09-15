extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING GAMEPLAY RUNTIME INTEGRATION TEST  <<<")
	print("==================================================")
	
	var main_scene = load("res://scenes/main.tscn")
	if not main_scene:
		print("  [FAIL] Failed to load main.tscn!")
		quit(1)
		return
	
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	
	print("  [STEP 1] Main scene instantiated and added to root")
	
	# Verify essential nodes
	var game_area = main_node.get_node_or_null("GameArea")
	if not game_area:
		print("  [FAIL] GameArea node missing!")
		quit(1)
		return
	
	print("  [STEP 2] Verifying player instance...")
	var p1 = main_node.p1_instance
	if not p1 or not is_instance_valid(p1):
		print("  [FAIL] Player 1 was not spawned properly!")
		quit(1)
		return
	print("    P1 Position: %s, Max HP: %d, Base Speed: %.1f" % [str(p1.position), p1.max_health, p1.base_speed])
	
	print("  [STEP 3] Verifying water tile animation...")
	var water_count = main_node.water_sprites.size()
	print("    Water tiles registered: %d" % water_count)
	
	print("  [STEP 4] Testing builder controller...")
	var builder = main_node.builder_ctrl
	if not builder:
		print("  [FAIL] BuilderController node missing!")
		quit(1)
		return
	GameState.add_structure_stock("turret", 1) # structures are shop-stock gated now, not gold-priced
	builder.select_structure(BuilderController.StructureType.TURRET, 1)
	if builder.selection_by_pid.get(1, BuilderController.StructureType.NONE) != BuilderController.StructureType.TURRET:
		print("  [FAIL] Builder selection failed!")
		quit(1)
		return
	print("    Builder selection OK: TURRET")
	
	print("  [STEP 5] Testing sound manager synth generation...")
	SoundManager.play_shot(self)
	SoundManager.play_hit_steel(self)
	SoundManager.play_hit_brick(self)
	SoundManager.play_explosion(self)
	print("    Sound manager synth streams initialized cleanly")
	
	print(">>> ALL GAMEPLAY RUNTIME INTEGRATION CHECKS PASSED! <<<")
	quit(0)
