extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const DarknessFog = preload("res://scripts/darkness_fog.gd")
const FallingBombHazard = preload("res://scripts/falling_bomb_hazard.gd")

func _init() -> void:
	print("=== Running Challenge Modes & Hazards Runtime Test ===")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var MainGameScene = load("res://scenes/main.tscn")

	# Test 1: Spire Map Generation with Challenge Modes
	print("1. Testing Spire Map Challenge Node Generation...")
	GameState.reset_campaign(1)
	var found_challenges = 0
	for k in GameState.spire_nodes.keys():
		var node = GameState.spire_nodes[k]
		if node["type"] == "challenge":
			found_challenges += 1
			print("   Found challenge node [%s] mode: %s" % [k, node.get("challenge_mode", "N/A")])
			assert(node.get("challenge_mode", "") in ["bomb_rain", "night_ops", "vault", "night_bombs"], "Invalid challenge mode!")
	assert(found_challenges > 0, "No challenge nodes found in spire map generation!")
	print("   ✓ Spire Map Challenge Node Generation OK!")

	# Test 2: Night Mode (DarknessFog) Initialization and Real-time Tracking
	print("2. Testing DarknessFog Night Mode...")
	GameState.mode = GameState.GameMode.CAMPAIGN
	GameState.battle_type = "challenge"
	GameState.challenge_mode = "night_ops"

	var main_inst = MainGameScene.instantiate()
	root.add_child(main_inst)
	
	assert(main_inst.is_night_mode_active == true, "Night mode should be active!")
	assert(main_inst.darkness_fog_instance != null, "DarknessFog instance should be created!")
	assert(is_instance_valid(main_inst.darkness_fog_instance), "DarknessFog instance should be valid in scene tree!")

	# Test dynamic light flashes
	main_inst.darkness_fog_instance.add_flash(Vector2(200, 200), 180.0, 0.3)
	assert(main_inst.darkness_fog_instance.flashes.size() == 1, "Flash should be registered!")
	print("   ✓ DarknessFog Night Mode OK!")

	main_inst.queue_free()

	# Test 3: Bomb Rain Hazard Spawning and Detonation
	print("3. Testing Bomb Rain (Falling Bomb Hazard)...")
	GameState.challenge_mode = "bomb_rain"
	var main_inst_bomb = MainGameScene.instantiate()
	root.add_child(main_inst_bomb)

	assert(main_inst_bomb.is_bomb_rain_active == true, "Bomb rain should be active!")
	
	# Manually trigger a falling bomb spawn
	main_inst_bomb._spawn_falling_bomb()
	var found_hazard = false
	for child in main_inst_bomb.actors_container.get_children():
		if child is FallingBombHazard:
			found_hazard = true
			# Advance and land the bomb immediately
			child._land()
			break
	assert(found_hazard, "FallingBombHazard should be spawned in actors container!")
	
	# Verify TimedBomb was placed on landing
	var found_timed_bomb = false
	for child in main_inst_bomb.actors_container.get_children():
		if child.is_in_group("timed_bomb"):
			found_timed_bomb = true
			# Trigger instant detonation test
			child.detonate()
			break
	assert(found_timed_bomb, "TimedBomb should be spawned upon bomb landing!")
	print("   ✓ Bomb Rain Falling Bomb & Detonation OK!")

	main_inst_bomb.queue_free()

	# Test 4: Campaign Persistence with Challenge Mode
	print("4. Testing Campaign Persistence for Challenge Mode...")
	GameState.challenge_mode = "night_bombs"
	GameState.save_campaign()
	GameState.challenge_mode = ""
	var loaded = GameState.load_campaign()
	assert(loaded, "Failed to load campaign save!")
	assert(GameState.challenge_mode == "night_bombs", "Challenge mode was not restored correctly!")
	GameState.delete_saved_game()
	print("   ✓ Campaign Persistence OK!")

	print("\n🎉 ALL CHALLENGE TESTS PASSED PERFECTLY! 🎉")
	quit(0)
