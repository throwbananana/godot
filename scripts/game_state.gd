class_name GameState
extends RefCounted

enum GameMode { CAMPAIGN, ARCADE }

static var mode: GameMode = GameMode.CAMPAIGN
static var player_count: int = 1 # 1=单人, 2=本地双人
static var current_floor: int = 0
static var max_floors: int = 6
static var current_node_id: String = ""
static var visited_node_ids: Array[String] = []

# RPG Persistent Stats
static var gold: int = 150
static var player_level: int = 1
static var player_xp: int = 0
static var xp_to_next: int = 100
static var player_tier: int = 0
static var player_lives: int = 3
static var max_hp: int = 1
static var max_hp_lvl: int = 0
static var atk_bonus: int = 0
static var speed_bonus: int = 0
static var speed_lvl: int = 0
static var fire_rate_lvl: int = 0
static var regen_lvl: int = 0
static var builder_lvl: int = 0

# P2 Stats (For 2-Player Co-op)
static var p2_tier: int = 0
static var p2_lives: int = 3

# Battle Configuration
static var battle_type: String = "battle"
static var total_enemies_override: int = 15
static var boss_enabled: bool = false

# Map Grid Data
static var spire_nodes: Dictionary = {}
static var spire_connections: Array = []

static func reset_campaign(p_count: int = 1) -> void:
	mode = GameMode.CAMPAIGN
	player_count = p_count
	current_floor = 0
	current_node_id = ""
	visited_node_ids.clear()
	gold = 150
	player_level = 1
	player_xp = 0
	xp_to_next = 100
	player_tier = 0
	player_lives = 3
	p2_tier = 0
	p2_lives = 3
	max_hp = 1
	max_hp_lvl = 0
	atk_bonus = 0
	speed_bonus = 0
	speed_lvl = 0
	fire_rate_lvl = 0
	regen_lvl = 0
	builder_lvl = 0
	battle_type = "battle"
	_generate_spire_map()

static func _generate_spire_map() -> void:
	spire_nodes.clear()
	spire_connections.clear()

	var pool_f1 = [["battle", "event", "battle"], ["event", "battle", "event"], ["battle", "shop", "battle"]]
	var pool_f2 = [["elite", "rest", "shop"], ["battle", "elite", "rest"], ["shop", "elite", "event"]]
	var pool_f3 = [["battle", "elite", "event"], ["elite", "shop", "battle"], ["event", "elite", "rest"]]
	var pool_f4 = [["rest", "shop"], ["shop", "rest"], ["rest", "event"]]

	pool_f1.shuffle()
	pool_f2.shuffle()
	pool_f3.shuffle()
	pool_f4.shuffle()

	var floor_types = [
		["battle", "battle", "battle"],             # Floor 0
		pool_f1[0],                                 # Floor 1
		pool_f2[0],                                 # Floor 2
		pool_f3[0],                                 # Floor 3
		pool_f4[0],                                 # Floor 4
		["boss"]                                    # Floor 5
	]

	for f_idx in range(floor_types.size()):
		var types = floor_types[f_idx]
		var count = types.size()
		for c_idx in range(count):
			var node_id = "f%d_n%d" % [f_idx, c_idx]
			var x_ratio = (c_idx + 1.0) / (count + 1.0)
			var y_ratio = 1.0 - (f_idx / float(floor_types.size() - 1)) * 0.78 - 0.11
			
			spire_nodes[node_id] = {
				"id": node_id,
				"floor": f_idx,
				"col": c_idx,
				"type": types[c_idx],
				"pos_ratio": Vector2(x_ratio, y_ratio),
				"status": "locked"
			}

	for f_idx in range(floor_types.size() - 1):
		var curr_count = floor_types[f_idx].size()
		var next_count = floor_types[f_idx + 1].size()
		
		for c_idx in range(curr_count):
			var from_id = "f%d_n%d" % [f_idx, c_idx]
			if next_count == 1:
				spire_connections.append({"from": from_id, "to": "f%d_n0" % (f_idx + 1)})
			elif curr_count == next_count:
				spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, c_idx]})
				if c_idx > 0:
					spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, c_idx - 1]})
				if c_idx < next_count - 1:
					spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, c_idx + 1]})
			elif curr_count > next_count:
				var target_col = mini(c_idx, next_count - 1)
				spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, target_col]})
				if c_idx > 0 and (target_col - 1) >= 0:
					spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, target_col - 1]})
			else:
				spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, c_idx]})
				if c_idx + 1 < next_count:
					spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, c_idx + 1]})

	for c_idx in range(floor_types[0].size()):
		var n_id = "f0_n%d" % c_idx
		if spire_nodes.has(n_id):
			spire_nodes[n_id]["status"] = "available"

static func is_node_available(node_id: String) -> bool:
	if not spire_nodes.has(node_id):
		return false
	if visited_node_ids.has(node_id):
		return false
	if current_node_id == "":
		return spire_nodes[node_id]["floor"] == 0
	
	for conn in spire_connections:
		if conn["from"] == current_node_id and conn["to"] == node_id:
			return true
	return false

static func visit_node(node_id: String) -> void:
	current_node_id = node_id
	visited_node_ids.append(node_id)
	if spire_nodes.has(node_id):
		spire_nodes[node_id]["status"] = "visited"
		current_floor = spire_nodes[node_id]["floor"]
