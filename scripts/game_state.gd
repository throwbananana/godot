class_name GameState
extends RefCounted

enum GameMode { CAMPAIGN, ARCADE }

static var mode: GameMode = GameMode.CAMPAIGN
static var player_count: int = 1 # 1=单人, 2=本地双人
static var current_act: int = 1   # 1=Act 1, 2=Act 2, 3=Act 3
static var max_acts: int = 3      # 3 Major Acts in Demo!
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
static var max_hp_lvl: int = 0
static var atk_bonus: int = 0
static var speed_lvl: int = 0
static var fire_rate_lvl: int = 0
static var regen_lvl: int = 0
static var builder_lvl: int = 0

# RPG Branch & Archetype Specialization
static var tank_branch: String = "default" # "default", "speed", "heavy", "train"
static var branch_tier: int = 0            # 0=Unassigned/Base, 1=Tier 1, 2=Tier 2
static var unlocked_perks: Array[String] = []

# P2 Stats (For 2-Player Co-op)
static var p2_tier: int = 0
static var p2_lives: int = 3
static var p2_branch: String = "default"
static var p2_branch_tier: int = 0
static var p2_unlocked_perks: Array[String] = []

# Battle Configuration
static var battle_type: String = "battle"
static var challenge_mode: String = "" # "", "bomb_rain", "night_ops", "vault", "night_bombs"
static var total_enemies_override: int = 15
static var boss_enabled: bool = false

# Map Grid Data
static var spire_nodes: Dictionary = {}
static var spire_connections: Array = []

static func get_act_name(act_idx: int = -1) -> String:
	var a = current_act if act_idx == -1 else act_idx
	match a:
		1: return "ACT 1: 诺曼底平原与河道要塞 (Frontline Plains & Rivers)"
		2: return "ACT 2: 阿塔卡马狂沙与流沙迷宫 (Atacama Quicksand Labyrinth)"
		3: return "ACT 3: 极地冻原与异次元要塞 (Glacial Singularity Citadel)"
		_: return "ACT %d: 未知作战区域" % a

static func get_player_max_hp() -> int:
	var bonus_hp = 0
	if tank_branch == "heavy":
		bonus_hp += 2 + branch_tier * 2
	elif tank_branch == "train":
		bonus_hp += 1 + branch_tier
	return 1 + max_hp_lvl + bonus_hp

static func reset_campaign(p_count: int = 1) -> void:
	mode = GameMode.CAMPAIGN
	player_count = p_count
	current_act = 1
	current_floor = 0
	current_node_id = ""
	visited_node_ids.clear()
	gold = 150
	player_level = 1
	player_xp = 0
	xp_to_next = 100
	player_tier = 0
	player_lives = 3
	tank_branch = "default"
	branch_tier = 0
	unlocked_perks.clear()
	p2_tier = 0
	p2_lives = 3
	p2_branch = "default"
	p2_branch_tier = 0
	p2_unlocked_perks.clear()
	max_hp_lvl = 0
	atk_bonus = 0
	speed_lvl = 0
	fire_rate_lvl = 0
	regen_lvl = 0
	builder_lvl = 0
	battle_type = "battle"
	challenge_mode = ""
	_generate_spire_map()

static func advance_to_next_act() -> void:
	current_act = mini(current_act + 1, max_acts)
	current_floor = 0
	current_node_id = ""
	visited_node_ids.clear()
	_generate_spire_map()

static func _generate_spire_map() -> void:
	spire_nodes.clear()
	spire_connections.clear()

	var pool_f1 = [["battle", "challenge", "battle"], ["event", "battle", "challenge"], ["battle", "shop", "battle"]]
	var pool_f2 = [["elite", "challenge", "shop"], ["battle", "elite", "rest"], ["challenge", "elite", "event"]]
	var pool_f3 = [["battle", "elite", "challenge"], ["elite", "shop", "battle"], ["challenge", "elite", "rest"]]
	var pool_f4 = [["rest", "shop"], ["shop", "rest"], ["rest", "event"]]

	if current_act == 2:
		pool_f2 = [["elite", "challenge", "shop"], ["battle", "elite", "shop"], ["challenge", "elite", "rest"]]
		pool_f3 = [["elite", "shop", "challenge"], ["challenge", "elite", "elite"], ["event", "elite", "shop"]]
	elif current_act == 3:
		pool_f1 = [["battle", "challenge", "elite"], ["elite", "battle", "challenge"], ["battle", "shop", "elite"]]
		pool_f2 = [["elite", "challenge", "shop"], ["elite", "event", "rest"], ["shop", "elite", "challenge"]]
		pool_f3 = [["elite", "shop", "challenge"], ["challenge", "elite", "elite"], ["elite", "event", "shop"]]

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
		["boss"]                                    # Floor 5 (Act Boss)
	]

	for f_idx in range(floor_types.size()):
		var types = floor_types[f_idx]
		var count = types.size()
		for c_idx in range(count):
			var node_id = "f%d_n%d" % [f_idx, c_idx]
			var x_ratio = (c_idx + 1.0) / (count + 1.0)
			var y_ratio = 1.0 - (f_idx / float(floor_types.size() - 1)) * 0.78 - 0.11
			
			var c_mode = ""
			if types[c_idx] == "challenge":
				var c_modes = ["bomb_rain", "night_ops", "vault", "night_bombs"]
				if current_act == 1:
					c_modes = ["bomb_rain", "night_ops", "vault"]
				elif current_act == 2:
					c_modes = ["night_ops", "bomb_rain", "night_bombs"]
				else:
					c_modes = ["night_bombs", "bomb_rain", "night_ops"]
				c_mode = c_modes[randi() % c_modes.size()]

			spire_nodes[node_id] = {
				"id": node_id,
				"floor": f_idx,
				"col": c_idx,
				"type": types[c_idx],
				"challenge_mode": c_mode,
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
		challenge_mode = str(spire_nodes[node_id].get("challenge_mode", ""))
	save_campaign()

# ==================== CAMPAIGN SAVE / LOAD SYSTEM ====================

const SAVE_PATH = "user://campaign_save.json"

static func has_saved_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func save_campaign() -> void:
	# Serialize spire_nodes ensuring pos_ratio is saved as dict
	var nodes_copy = {}
	for k in spire_nodes.keys():
		var node = spire_nodes[k].duplicate()
		if node.has("pos_ratio") and node["pos_ratio"] is Vector2:
			node["pos_ratio"] = {"x": node["pos_ratio"].x, "y": node["pos_ratio"].y}
		nodes_copy[k] = node

	var save_dict = {
		"mode": int(mode),
		"player_count": player_count,
		"current_act": current_act,
		"current_floor": current_floor,
		"current_node_id": current_node_id,
		"visited_node_ids": visited_node_ids,
		"gold": gold,
		"player_level": player_level,
		"player_xp": player_xp,
		"xp_to_next": xp_to_next,
		"player_tier": player_tier,
		"player_lives": player_lives,
		"tank_branch": tank_branch,
		"branch_tier": branch_tier,
		"unlocked_perks": unlocked_perks,
		"p2_tier": p2_tier,
		"p2_lives": p2_lives,
		"p2_branch": p2_branch,
		"p2_branch_tier": p2_branch_tier,
		"p2_unlocked_perks": p2_unlocked_perks,
		"max_hp_lvl": max_hp_lvl,
		"atk_bonus": atk_bonus,
		"speed_lvl": speed_lvl,
		"fire_rate_lvl": fire_rate_lvl,
		"regen_lvl": regen_lvl,
		"builder_lvl": builder_lvl,
		"battle_type": battle_type,
		"challenge_mode": challenge_mode,
		"spire_nodes": nodes_copy,
		"spire_connections": spire_connections
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_dict, "\t"))
		file.close()

static func load_campaign() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK or not (json.data is Dictionary):
		return false
	var d: Dictionary = json.data
	mode = int(d.get("mode", GameMode.CAMPAIGN)) as GameMode
	player_count = int(d.get("player_count", 1))
	current_act = int(d.get("current_act", 1))
	current_floor = int(d.get("current_floor", 0))
	current_node_id = str(d.get("current_node_id", ""))
	visited_node_ids.clear()
	for v in d.get("visited_node_ids", []):
		visited_node_ids.append(str(v))
	gold = int(d.get("gold", 150))
	player_level = int(d.get("player_level", 1))
	player_xp = int(d.get("player_xp", 0))
	xp_to_next = int(d.get("xp_to_next", 100))
	player_tier = int(d.get("player_tier", 0))
	player_lives = int(d.get("player_lives", 3))
	tank_branch = str(d.get("tank_branch", "default"))
	branch_tier = int(d.get("branch_tier", 0))
	unlocked_perks.clear()
	for p in d.get("unlocked_perks", []):
		unlocked_perks.append(str(p))
	p2_tier = int(d.get("p2_tier", 0))
	p2_lives = int(d.get("p2_lives", 3))
	p2_branch = str(d.get("p2_branch", "default"))
	p2_branch_tier = int(d.get("p2_branch_tier", 0))
	p2_unlocked_perks.clear()
	for p in d.get("p2_unlocked_perks", []):
		p2_unlocked_perks.append(str(p))
	max_hp_lvl = int(d.get("max_hp_lvl", 0))
	atk_bonus = int(d.get("atk_bonus", 0))
	speed_lvl = int(d.get("speed_lvl", 0))
	fire_rate_lvl = int(d.get("fire_rate_lvl", 0))
	regen_lvl = int(d.get("regen_lvl", 0))
	builder_lvl = int(d.get("builder_lvl", 0))
	battle_type = str(d.get("battle_type", "battle"))
	challenge_mode = str(d.get("challenge_mode", ""))
	spire_nodes = d.get("spire_nodes", {})
	for k in spire_nodes.keys():
		var n_data = spire_nodes[k]
		if n_data.has("pos_ratio") and n_data["pos_ratio"] is Dictionary:
			n_data["pos_ratio"] = Vector2(float(n_data["pos_ratio"].get("x", 0.0)), float(n_data["pos_ratio"].get("y", 0.0)))
		if n_data.has("floor"):
			n_data["floor"] = int(n_data["floor"])
		if n_data.has("col"):
			n_data["col"] = int(n_data["col"])
	spire_connections = d.get("spire_connections", [])
	return true

static func delete_saved_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
