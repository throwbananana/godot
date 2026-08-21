extends SceneTree

const MapTemplates = preload("res://scripts/map_templates.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")
const GameState = preload("res://scripts/game_state.gd")

func _init() -> void:
	print("=== Running Multi-Element Maps & Procedural Generation Test ===")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var MainGameScene = load("res://scenes/main.tscn")
	var main_inst = MainGameScene.instantiate()
	root.add_child(main_inst)

	# --------------------------------------------------------------------------
	# Test 1: Verify All Handcrafted Multi-Element Templates (1 to 46)
	# --------------------------------------------------------------------------
	print("1. Testing All 46 Handcrafted Multi-Element Templates...")
	
	var templates = [
		MapTemplates.TEMPLATE_CLASSIC,
		MapTemplates.TEMPLATE_RIVERS,
		MapTemplates.TEMPLATE_JUNGLE,
		MapTemplates.TEMPLATE_CITADEL,
		MapTemplates.TEMPLATE_CHECKERBOARD,
		MapTemplates.TEMPLATE_SPEEDWAY,
		MapTemplates.TEMPLATE_CANYON,
		MapTemplates.TEMPLATE_BOSS_ARENA,
		MapTemplates.TEMPLATE_DESERT_STORM,
		MapTemplates.TEMPLATE_OASIS_DUNES,
		MapTemplates.TEMPLATE_DESERT_LABYRINTH,
		MapTemplates.TEMPLATE_NAVAL_DELTA,
		MapTemplates.TEMPLATE_AIR_NAVAL_STRAITS,
		MapTemplates.TEMPLATE_DEMOLITION_TRENCH,
		MapTemplates.TEMPLATE_GLACIER_ICE,
		MapTemplates.TEMPLATE_WARP_GLACIER,
		MapTemplates.TEMPLATE_COSMIC_WORMHOLES,
		MapTemplates.TEMPLATE_SHIELD_OUTPOST,
		MapTemplates.TEMPLATE_SHIELD_LABYRINTH,
		MapTemplates.TEMPLATE_WIND_TEMPEST,
		MapTemplates.TEMPLATE_CYCLONE_ARENA,
		MapTemplates.TEMPLATE_WARP_TURBINE_VALLEY,
		MapTemplates.TEMPLATE_CONVEYOR_FACTORY,
		MapTemplates.TEMPLATE_CONVEYOR_PINBALL,
		MapTemplates.TEMPLATE_TURBINE_CONVEYOR_LAB,
		MapTemplates.TEMPLATE_JUMP_ARCHIPELAGO,
		MapTemplates.TEMPLATE_VOID_CANAL,
		MapTemplates.TEMPLATE_VOID_FERRY,
		MapTemplates.TEMPLATE_TWIN_ISLANDS,
		MapTemplates.TEMPLATE_DIAMOND_CRYSTAL_MINE,
		MapTemplates.TEMPLATE_MIRAGE_JUNGLE_MAZE,
		MapTemplates.TEMPLATE_ELITE_CITADEL,
		MapTemplates.TEMPLATE_NEO_TITAN_BASTION,
		MapTemplates.TEMPLATE_WARP_CITADEL_APEX,
		MapTemplates.TEMPLATE_APEX_TRI_ARMOR_CITADEL,
		MapTemplates.TEMPLATE_NIGHT_HIGHWAY,
		MapTemplates.TEMPLATE_OIL_REFINERY,
		MapTemplates.TEMPLATE_GLACIER_TESLA,
		MapTemplates.TEMPLATE_INFERNO_REFINERY,
		MapTemplates.TEMPLATE_NIGHTSHADE_WARP,
		MapTemplates.TEMPLATE_MAGNETIC_ARCHIPELAGO,
		MapTemplates.TEMPLATE_QUICKSAND_FOUNDRY,
		MapTemplates.TEMPLATE_HYPERDRIVE_PINBALL,
		MapTemplates.TEMPLATE_TRI_DOMAIN_BIOHAZARD,
		MapTemplates.TEMPLATE_SOLAR_TITAN_SANCTUM
	]

	var checked_count = 0
	for t in templates:
		checked_count += 1
		assert(t.size() == 13, "Template %d must have 13 rows!" % checked_count)
		for r in range(13):
			assert(t[r].size() == 13, "Template %d row %d must have 13 cols!" % [checked_count, r])
		
		# Base Eagle sanctuary check (Row 12 Col 6 must be 0)
		assert(t[12][6] == 0, "Template %d base location must be clear ground!" % checked_count)

	print("   ✓ All %d Templates Validated with 13x13 Grid Integrity!" % templates.size())

	# --------------------------------------------------------------------------
	# Test 2: Verify Stage Routing Across Acts 1, 2, 3
	# --------------------------------------------------------------------------
	print("2. Testing Stage Routing Across Acts 1..3...")
	for act in [1, 2, 3]:
		for btype in ["battle", "elite", "challenge", "boss"]:
			for f in range(1, 6):
				var layout = MapTemplates.get_layout_for_stage(f, btype, act, false)
				assert(layout.size() == 13 and layout[0].size() == 13, "Layout routing failed for Act %d Floor %d [%s]!" % [act, f, btype])
	print("   ✓ Stage Layout Routing OK!")

	# --------------------------------------------------------------------------
	# Test 3: Verify Procedural Generation for All Biomes
	# --------------------------------------------------------------------------
	print("3. Testing Procedural Multi-Element Map Generator...")
	for act in [1, 2, 3]:
		var proc_grid = MapGenerator.generate_map(act)
		assert(proc_grid.size() == 13 and proc_grid[0].size() == 13, "Procedural grid generation failed for Act %d!" % act)
		assert(proc_grid[12][6] == 0, "Procedural base position must be clear!")
	print("   ✓ Procedural Generation OK!")

	main_inst.queue_free()
	print("\n🎉 ALL MULTI-ELEMENT MAP TESTS PASSED! 🎉")
	quit(0)
