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
		{"name": "CITADEL", "grid": MapTemplates.TEMPLATE_CITADEL},
		{"name": "JUNGLE", "grid": MapTemplates.TEMPLATE_JUNGLE},
		{"name": "CHECKERBOARD", "grid": MapTemplates.TEMPLATE_CHECKERBOARD},
		{"name": "SPEEDWAY", "grid": MapTemplates.TEMPLATE_SPEEDWAY},
		{"name": "CANYON", "grid": MapTemplates.TEMPLATE_CANYON},
		{"name": "BOSS_ARENA", "grid": MapTemplates.TEMPLATE_BOSS_ARENA},
	]

	print(">>> 1. Validating all 8 Map Templates...")
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
