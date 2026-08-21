extends SceneTree

const MapTemplates = preload("res://scripts/map_templates.gd")
const GameState = preload("res://scripts/game_state.gd")

func _init() -> void:
	print("=== Running Map Templates and Base Alignment Tests ===")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var templates = [
		{"name": "CLASSIC", "grid": MapTemplates.TEMPLATE_CLASSIC},
		{"name": "RIVERS", "grid": MapTemplates.TEMPLATE_RIVERS},
		{"name": "DESERT_STORM", "grid": MapTemplates.TEMPLATE_DESERT_STORM},
		{"name": "OASIS_DUNES", "grid": MapTemplates.TEMPLATE_OASIS_DUNES},
		{"name": "CITADEL", "grid": MapTemplates.TEMPLATE_CITADEL},
		{"name": "JUNGLE", "grid": MapTemplates.TEMPLATE_JUNGLE},
		{"name": "CHECKERBOARD", "grid": MapTemplates.TEMPLATE_CHECKERBOARD},
		{"name": "SPEEDWAY", "grid": MapTemplates.TEMPLATE_SPEEDWAY},
		{"name": "CANYON", "grid": MapTemplates.TEMPLATE_CANYON},
		{"name": "BOSS_ARENA", "grid": MapTemplates.TEMPLATE_BOSS_ARENA},
		{"name": "GLACIER_ICE", "grid": MapTemplates.TEMPLATE_GLACIER_ICE},
		{"name": "VOID_FERRY", "grid": MapTemplates.TEMPLATE_VOID_FERRY},
		{"name": "COSMIC_WORMHOLES", "grid": MapTemplates.TEMPLATE_COSMIC_WORMHOLES},
		{"name": "WARP_GLACIER", "grid": MapTemplates.TEMPLATE_WARP_GLACIER},
		{"name": "VOID_CANAL", "grid": MapTemplates.TEMPLATE_VOID_CANAL},
		{"name": "DESERT_LABYRINTH", "grid": MapTemplates.TEMPLATE_DESERT_LABYRINTH},
		{"name": "METEOR_CRATER", "grid": MapTemplates.TEMPLATE_METEOR_CRATER},
		{"name": "TWIN_ISLANDS", "grid": MapTemplates.TEMPLATE_TWIN_ISLANDS},
		{"name": "ELITE_CITADEL", "grid": MapTemplates.TEMPLATE_ELITE_CITADEL},
		{"name": "WIND_TEMPEST", "grid": MapTemplates.TEMPLATE_WIND_TEMPEST},
		{"name": "SHIELD_OUTPOST", "grid": MapTemplates.TEMPLATE_SHIELD_OUTPOST},
		{"name": "CYCLONE_ARENA", "grid": MapTemplates.TEMPLATE_CYCLONE_ARENA},
		{"name": "SHIELD_LABYRINTH", "grid": MapTemplates.TEMPLATE_SHIELD_LABYRINTH},
		{"name": "WARP_TURBINE_VALLEY", "grid": MapTemplates.TEMPLATE_WARP_TURBINE_VALLEY},
		{"name": "CONVEYOR_FACTORY", "grid": MapTemplates.TEMPLATE_CONVEYOR_FACTORY},
		{"name": "JUMP_ARCHIPELAGO", "grid": MapTemplates.TEMPLATE_JUMP_ARCHIPELAGO},
		{"name": "TURBINE_CONVEYOR_LAB", "grid": MapTemplates.TEMPLATE_TURBINE_CONVEYOR_LAB},
		{"name": "NEO_TITAN_BASTION", "grid": MapTemplates.TEMPLATE_NEO_TITAN_BASTION},
		{"name": "CONVEYOR_PINBALL", "grid": MapTemplates.TEMPLATE_CONVEYOR_PINBALL},
		{"name": "WARP_CITADEL_APEX", "grid": MapTemplates.TEMPLATE_WARP_CITADEL_APEX},
		{"name": "NAVAL_DELTA", "grid": MapTemplates.TEMPLATE_NAVAL_DELTA},
		{"name": "MIRAGE_JUNGLE_MAZE", "grid": MapTemplates.TEMPLATE_MIRAGE_JUNGLE_MAZE},
		{"name": "AIR_NAVAL_STRAITS", "grid": MapTemplates.TEMPLATE_AIR_NAVAL_STRAITS},
		{"name": "DEMOLITION_TRENCH", "grid": MapTemplates.TEMPLATE_DEMOLITION_TRENCH},
		{"name": "DIAMOND_CRYSTAL_MINE", "grid": MapTemplates.TEMPLATE_DIAMOND_CRYSTAL_MINE},
		{"name": "APEX_TRI_ARMOR_CITADEL", "grid": MapTemplates.TEMPLATE_APEX_TRI_ARMOR_CITADEL}
	]

	print(">>> 1. Validating all 36 Map Templates...")
	for t in templates:
		var g = t["grid"]
		assert(g.size() == 13, "Template %s must have 13 rows, got %d" % [t["name"], g.size()])
		for r in range(g.size()):
			assert(g[r].size() == 13, "Template %s row %d must have 13 columns, got %d" % [t["name"], r, g[r].size()])
		
		# Ensure Base area (Row 11 & 12, cols 5, 6, 7) is empty for base bunker placement
		assert(g[12][5] == 0 and g[12][6] == 0 and g[12][7] == 0, "Base row 12 in %s must be empty" % t["name"])
		assert(g[11][5] == 0 and g[11][6] == 0 and g[11][7] == 0, "Base bunker top row 11 in %s must be empty" % t["name"])
		
		# Ensure Player spawn points (Row 12 col 4, col 8) are empty
		assert(g[12][4] == 0, "P1 spawn in %s must be empty" % t["name"])
		assert(g[12][8] == 0, "P2 spawn in %s must be empty" % t["name"])
		
		# Ensure Enemy spawn points (Row 0 col 0, 6, 12) are empty
		assert(g[0][0] == 0 and g[0][6] == 0 and g[0][12] == 0, "Enemy spawns in %s must be empty" % t["name"])
		print("  ✓ Template %s (13x13) verified with clear spawn zones" % t["name"])

	print(">>> 2. Verifying Main scene Map & Base Eagle placement (0-gap bottom alignment)...")
	var main_scene = load("res://scenes/main.tscn")
	var main_inst = main_scene.instantiate()
	root.add_child(main_inst)

	var base_inst = main_inst.get("base_instance")
	assert(base_inst != null, "Base eagle instance should exist")
	print("  ✓ Base Eagle position: %s (y=%.1f)" % [str(base_inst.position), base_inst.position.y])

	# Check base y center is row 12 (12.5 * 48 = 600.0)
	var tile_size = 48.0
	var expected_base_y = 12.5 * tile_size
	assert(abs(base_inst.position.y - expected_base_y) < 0.1, "Base y should be %f, got %f" % [expected_base_y, base_inst.position.y])

	# Check border walls in map_container
	var map_container = main_inst.get_node("GameArea/MapContainer")
	var borders = map_container.get_children().filter(func(c): return c.is_in_group("border"))
	assert(borders.size() == 4, "Should have 4 border walls, got %d" % borders.size())

	# Find bottom border wall
	var bottom_border: StaticBody2D = null
	for b in borders:
		if b.position.y > 600:
			bottom_border = b
			break
	assert(bottom_border != null, "Bottom border wall should exist")
	print("  ✓ Bottom border wall position: %s (y=%.1f)" % [str(bottom_border.position), bottom_border.position.y])

	# Bottom border center should be at map_pixel_h + TILE_SIZE/2 = 624 + 24 = 648
	var expected_bottom_border_y = (13 * tile_size) + (tile_size / 2.0)
	assert(abs(bottom_border.position.y - expected_bottom_border_y) < 0.1, "Bottom border y should be %f, got %f" % [expected_bottom_border_y, bottom_border.position.y])

	print("\n🎉 ALL MAP TEMPLATES & BASE ZERO-GAP ALIGNMENT TESTS PASSED! 🎉\n")
	quit(0)
