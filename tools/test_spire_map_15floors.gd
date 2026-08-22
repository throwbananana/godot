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

	# 上面的"无孤儿"只保证每个节点有**入边**。真正会卡死一局的是相反的一侧:
	# 有入边、没出边。GameState.is_node_available() 要求存在一条从
	# current_node_id 出发的连线, 所以走进这样的节点之后地图上什么都点不动了 ——
	# 而且不会报错, 玩家只会以为游戏卡住。boss 层 (最后一层) 是唯一合法的终点。
	var outgoing: Dictionary = {}
	for conn in GameState.spire_connections:
		if not outgoing.has(conn["from"]):
			outgoing[conn["from"]] = []
		outgoing[conn["from"]].append(conn["to"])

	var dead_ends: Array[String] = []
	for node_id in GameState.spire_nodes.keys():
		var node2 = GameState.spire_nodes[node_id]
		if int(node2["floor"]) >= GameState.max_floors - 1:
			continue
		if not outgoing.has(node_id) or (outgoing[node_id] as Array).is_empty():
			dead_ends.append("%s (floor %d)" % [node_id, int(node2["floor"])])
	assert(dead_ends.is_empty(),
		"Act %d 有 %d 个死胡同节点, 走进去整局卡死: %s"
		% [act, dead_ends.size(), ", ".join(dead_ends)])

	# 真可达性: "有入边"不等于"从起点走得到" —— 入边可能来自一个本身就走不到
	# 的节点。从所有 floor 0 起点做一次 BFS 才是实际能走到的集合。
	var seen: Dictionary = {}
	var stack: Array = []
	for node_id in GameState.spire_nodes.keys():
		if int(GameState.spire_nodes[node_id]["floor"]) == 0:
			seen[node_id] = true
			stack.append(node_id)
	while not stack.is_empty():
		var cur = stack.pop_back()
		for nxt in outgoing.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = true
				stack.append(nxt)
	var unreached: Array[String] = []
	for node_id in GameState.spire_nodes.keys():
		if not seen.has(node_id):
			unreached.append(node_id)
	assert(unreached.is_empty(),
		"Act %d 有 %d 个节点从 floor 0 根本走不到: %s"
		% [act, unreached.size(), ", ".join(unreached)])

	# 每一个开局选项都必须能通到 boss —— 否则选错起点等于开局就废了。
	for start_id in GameState.spire_nodes.keys():
		if int(GameState.spire_nodes[start_id]["floor"]) != 0:
			continue
		var s2: Dictionary = {start_id: true}
		var st2: Array = [start_id]
		var hit_boss := false
		while not st2.is_empty():
			var cur = st2.pop_back()
			if int(GameState.spire_nodes[cur]["floor"]) == GameState.max_floors - 1:
				hit_boss = true
				break
			for nxt in outgoing.get(cur, []):
				if not s2.has(nxt):
					s2[nxt] = true
					st2.append(nxt)
		assert(hit_boss, "Act %d 的起点 %s 通不到 boss 层" % [act, start_id])

	# 连线只能指向存在的节点, 且只能向前跨一层 (不跳层, 不倒退)。
	for conn in GameState.spire_connections:
		assert(GameState.spire_nodes.has(conn["from"]) and GameState.spire_nodes.has(conn["to"]),
			"Act %d 有连线指向不存在的节点: %s -> %s" % [act, conn["from"], conn["to"]])
		var df = int(GameState.spire_nodes[conn["to"]]["floor"]) - int(GameState.spire_nodes[conn["from"]]["floor"])
		assert(df == 1, "Act %d 的连线 %s -> %s 跨了 %d 层 (只允许 +1)"
			% [act, conn["from"], conn["to"], df])

	print("  [PASS] Act %d: 15 floors, %d nodes, %d connections, 0 orphans, 0 dead ends, boss reachable from every start."
		% [act, GameState.spire_nodes.size(), GameState.spire_connections.size()])
