extends SceneTree

# Verifies GameState._generate_spire_map() actually produces a 15-floor act
# (max_floors was bumped from 6 to 15) with a sane, fully-connected node
# graph -- not just that it doesn't crash. Runs across all 3 acts since each
# has its own band-pool overrides (game_state.gd::_band_pool).

func _init() -> void:
	print("==================================================")
	print(">>> RUNNING 15-FLOOR SPIRE MAP TEST  <<<")
	print("==================================================")

	assert(GameState.max_floors == 15, "GameState.max_floors should be 15, got %d" % GameState.max_floors)

	for act in [1, 2, 3]:
		_check_act(act)

	print("\n>>> ALL 15-FLOOR SPIRE MAP CHECKS PASSED! <<<")
	quit(0)

func _check_act(act: int) -> void:
	print("\n[STEP] Generating Act %d map..." % act)
	GameState.current_act = act
	GameState._generate_spire_map()

	var floors_seen: Dictionary = {}
	for node_id in GameState.spire_nodes.keys():
		var node = GameState.spire_nodes[node_id]
		floors_seen[node["floor"]] = true

	assert(floors_seen.size() == 15, "Act %d should have 15 distinct floors, got %d" % [act, floors_seen.size()])
	for f in range(15):
		assert(floors_seen.has(f), "Act %d missing floor %d entirely" % [act, f])

	# Floor 0 always the 3-way start, last floor always a single boss node.
	var f0_count = 0
	var boss_count = 0
	for node_id in GameState.spire_nodes.keys():
		var node = GameState.spire_nodes[node_id]
		if node["floor"] == 0:
			f0_count += 1
			assert(node["type"] == "battle", "Floor 0 node should be battle, got %s" % node["type"])
		elif node["floor"] == 14:
			boss_count += 1
			assert(node["type"] == "boss", "Floor 14 node should be boss, got %s" % node["type"])
	assert(f0_count == 3, "Act %d floor 0 should have 3 nodes, got %d" % [act, f0_count])
	assert(boss_count == 1, "Act %d floor 14 should have exactly 1 boss node, got %d" % [act, boss_count])

	# Every node from floor 1 onward must be reachable by at least one
	# connection from the previous floor (no orphaned/unreachable node).
	var incoming: Dictionary = {}
	for conn in GameState.spire_connections:
		incoming[conn["to"]] = true
	var orphans = 0
	for node_id in GameState.spire_nodes.keys():
		var node = GameState.spire_nodes[node_id]
		if node["floor"] > 0 and not incoming.has(node_id):
			orphans += 1
			print("    [FAIL] Orphaned node with no incoming connection: %s (floor %d)" % [node_id, node["floor"]])
	assert(orphans == 0, "Act %d has %d unreachable node(s)" % [act, orphans])

	print("  [PASS] Act %d: 15 floors, %d nodes, %d connections, 0 orphans." % [act, GameState.spire_nodes.size(), GameState.spire_connections.size()])
