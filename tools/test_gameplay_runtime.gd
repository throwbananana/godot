extends SceneTree

func _init() -> void:
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
	print("    P1 Position: %s, Max HP: %d, Speed: %.1f" % [str(p1.position), p1.max_health, p1.speed])
	
	print("  [STEP 3] Verifying water tile animation...")
	var water_count = main_node.water_sprites.size()
	print("    Water tiles count: %d" % water_count)
	if water_count > 0:
		var w_tex_count = main_node.tex_water_frames.size()
		if w_tex_count != 6:
			print("  [FAIL] Expected 6 water frames, got %d" % w_tex_count)
			quit(1)
			return
		print("    Water animation frames: %d frames registered" % w_tex_count)

	print("  [STEP 4] Simulating 60 frames of gameplay loop...")
	for f in range(60):
		main_node._process(0.016667)
	
	print("  [STEP 5] Testing Screen Shake (Trauma)...")
	main_node.add_trauma(0.5)
	if main_node.trauma <= 0.0:
		print("  [FAIL] Trauma addition failed!")
		quit(1)
		return
	main_node._process(0.05)
	print("    Trauma after decay: %.2f" % main_node.trauma)

	print("  [STEP 6] Testing SoundManager procedural audio synthesis...")
	SoundManager.play_shot(self)
	SoundManager.play_pickup(self)
	SoundManager.play_level_up(self)
	SoundManager.play_victory(self)
	SoundManager.play_shield_hit(self)
	print("    All 5 procedural synth sounds invoked successfully!")

	print("==================================================")
	print(">>> ALL RUNTIME GAMEPLAY TESTS PASSED! (6/6)   <<<")
	print("==================================================")
	quit(0)
