extends SceneTree

# Verifies the two new "多海域" (water-heavy) templates and the Drifting
# Supplies pickup:
#   - TEMPLATE_NAVAL_SALVAGE_ROUTE / TEMPLATE_TWIN_LAKES_SALVAGE are valid
#     13x13 grids that differ from their source templates (TEMPLATE_NAVAL_DELTA
#     / TEMPLATE_TWIN_ISLANDS) ONLY by turning some water (3) into Drifting
#     Supplies (29) -- never the reverse, and never touching any other tile.
#     That one-directional constraint is what makes them safe without a full
#     pathfinder: 29 is a strictly more-passable substitute for 3 (see
#     drifting_supplies.gd / main.gd::_spawn_drifting_supplies -- no
#     collision body, "treated as ground"), so every route that was walkable
#     in the source template is still walkable here; nothing was removed.
#   - The DriftingSupplies scene grants gold once on touch and doesn't
#     double-fire.

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING WATER SALVAGE MAP TEST  <<<")
	print("==================================================")

	_test_salvage_route_only_adds_passability(MapTemplates.TEMPLATE_NAVAL_DELTA, MapTemplates.TEMPLATE_NAVAL_SALVAGE_ROUTE, "NAVAL_SALVAGE_ROUTE")
	_test_salvage_route_only_adds_passability(MapTemplates.TEMPLATE_TWIN_ISLANDS, MapTemplates.TEMPLATE_TWIN_LAKES_SALVAGE, "TWIN_LAKES_SALVAGE")
	_test_grid_shape(MapTemplates.TEMPLATE_NAVAL_SALVAGE_ROUTE, "NAVAL_SALVAGE_ROUTE")
	_test_grid_shape(MapTemplates.TEMPLATE_TWIN_LAKES_SALVAGE, "TWIN_LAKES_SALVAGE")
	_test_drifting_supplies_grants_reward_once()
	_test_main_spawn_function_creates_passable_water_tile()

	print("\n>>> ALL WATER SALVAGE MAP CHECKS PASSED! <<<")
	quit(0)

func _test_grid_shape(template: Array, name: String) -> void:
	print("\n[STEP] %s is a valid 13x13 grid..." % name)
	assert(template.size() == 13, "%s should have 13 rows, got %d" % [name, template.size()])
	for row in template:
		assert(row.size() == 13, "%s row should have 13 columns, got %d" % [name, row.size()])
	var has_drift = false
	for row in template:
		if 29 in row:
			has_drift = true
			break
	assert(has_drift, "%s should contain at least one Drifting Supplies (29) tile" % name)
	print("  [PASS] %s is 13x13 and contains Drifting Supplies tiles." % name)

func _test_salvage_route_only_adds_passability(source: Array, salvage: Array, name: String) -> void:
	print("\n[STEP] %s only converts water (3) -> Drifting Supplies (29), nothing else..." % name)
	assert(source.size() == salvage.size(), "%s should have the same row count as its source" % name)
	var diffs = 0
	for r in range(source.size()):
		assert(source[r].size() == salvage[r].size(), "%s row %d should have the same column count as its source" % [name, r])
		for c in range(source[r].size()):
			var src_val = source[r][c]
			var new_val = salvage[r][c]
			if src_val != new_val:
				diffs += 1
				assert(src_val == 3, "%s [%d][%d]: only water (3) cells should be changed, source had %d" % [name, r, c, src_val])
				assert(new_val == 29, "%s [%d][%d]: changed cells should become Drifting Supplies (29), got %d" % [name, r, c, new_val])
	assert(diffs > 0, "%s should differ from its source in at least one cell" % name)
	print("  [PASS] %s changed %d cell(s), all water(3)->DriftingSupplies(29), nothing else touched." % [name, diffs])

func _test_drifting_supplies_grants_reward_once() -> void:
	print("\n[STEP] DriftingSupplies grants gold once and doesn't double-fire...")
	GameState.reset_campaign(1)
	var main_scene = load("res://scenes/main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	current_scene = main_node

	var crate_scene = load("res://scenes/drifting_supplies.tscn")
	var crate = crate_scene.instantiate()
	root.add_child(crate)

	var gold_before = main_node.rpg_mgr.gold

	var fake_player = Node2D.new()
	fake_player.add_to_group("player")
	root.add_child(fake_player)

	crate._on_body_entered(fake_player)
	assert(crate.is_opened, "crate should be marked opened after being touched")
	assert(main_node.rpg_mgr.gold > gold_before, "touching the crate should grant gold")

	var gold_after_first = main_node.rpg_mgr.gold
	crate._on_body_entered(fake_player) # simulate a second overlap signal
	assert(main_node.rpg_mgr.gold == gold_after_first, "a second touch after opening should not grant gold again")

	fake_player.queue_free()
	main_node.queue_free()
	print("  [PASS] DriftingSupplies grants its reward exactly once.")

func _test_main_spawn_function_creates_passable_water_tile() -> void:
	print("\n[STEP] main.gd::_spawn_drifting_supplies() runs cleanly and spawns a non-blocking tile...")
	GameState.reset_campaign(1)
	var main_scene = load("res://scenes/main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	current_scene = main_node

	var water_sprite_count_before = main_node.water_sprites.size()
	var crate_count_before = get_nodes_in_group("drifting_supplies").size()

	main_node._spawn_drifting_supplies(Vector2(300, 300))

	assert(main_node.water_sprites.size() == water_sprite_count_before + 1, "should register one decorative (non-blocking) water sprite")
	var crates = get_nodes_in_group("drifting_supplies")
	assert(crates.size() == crate_count_before + 1, "should spawn one DriftingSupplies pickup")

	# The decorative sprite must NOT have a collision body of its own --
	# confirming this cell is genuinely "treated as ground", not silently
	# blocked the way a real water tile (_spawn_tile("water", ...)) is.
	var new_sprite = main_node.water_sprites[-1]
	assert(new_sprite.get_parent() is Node2D, "sanity: sprite parented under map_container")
	assert(not (new_sprite.get_parent() is StaticBody2D), "the decorative water backdrop must not itself be a blocking StaticBody2D")

	main_node.queue_free()
	print("  [PASS] _spawn_drifting_supplies() integrates cleanly with main.gd's water_sprites tracking.")
