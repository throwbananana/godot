class_name GameState
extends RefCounted

enum GameMode { CAMPAIGN, ARCADE, DAILY_CHALLENGE }

static var mode: GameMode = GameMode.CAMPAIGN
static var player_count: int = 1 # 1=单人, 2=本地双人
static var current_act: int = 1   # 1..max_acts
static var max_acts: int = 8      # 8 Major Acts -- only 3 unique visual themes exist
                                   # (Plains/Desert/Glacial), so acts beyond 3 cycle back
                                   # through them at escalating difficulty. See
                                   # get_visual_act() / get_difficulty_cycle().
static var current_floor: int = 0
static var max_floors: int = 15
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

# perk_id -> stack count (was Array[String] of unique unlocks; a single run
# now spans 15 floors instead of the original 6, so the fixed "10 unique
# perks then nothing but the gold_heal filler" pool ran out around floor
# 5-7. Perks are stackable now (see PERK_MAX_STACKS) so the level-up screen
# keeps offering real choices for the rest of a 15-floor act.
static var unlocked_perks: Dictionary = {}
static var p2_unlocked_perks: Dictionary = {}

# How many times each perk can be picked. Perks with an existing numeric
# hook (HP/damage/rate/range/duration) scale per stack via
# RPGManager.get_perk_value(); perks that are pass/fail mechanical gates
# (full ice control, one-shot hard clay, platform damage buff) don't have a
# meaningful "3rd tier" without inventing a new threshold, so they stay
# single-unlock. Unlisted perks default to 1 (see max_stacks_for_perk).
const PERK_MAX_STACKS := {
	"titan_plating": 3,
	"rapid_loader": 3,
	"nitro_booster": 3,
	"nano_repair": 3,
	"high_explosive": 3,
	"magnetic_salvage": 3,
	"warp_drive": 3,
	"frost_cleats": 1,
	"ferry_artillery": 1,
	"clay_crusher": 1,
	# High-risk/high-reward shop-only perks (bullet.gd mechanics) --
	# ricochet_rounds stacks (each stack = +1 bounce before the bullet
	# finally dies); armor_piercing_rounds is a binary trade like the other
	# mechanical gates above, not a magnitude to scale.
	"ricochet_rounds": 3,
	"armor_piercing_rounds": 1,
	"amphibious_hull": 1,
}

static func max_stacks_for_perk(perk_id: String) -> int:
	return PERK_MAX_STACKS.get(perk_id, 1)

## Shared "grant one stack of this perk to this player, respecting the cap"
## used by both shop_dialog.gd and event_dialog.gd (both run in
## spire_map.tscn, operating on the persistent GameState.unlocked_perks
## directly rather than through a live RPGManager instance). Returns false if
## the perk was already at its cap.
static func grant_perk_stack(perk_id: String, player_id: int = 1) -> bool:
	var perks = unlocked_perks if player_id == 1 else p2_unlocked_perks
	var cap = max_stacks_for_perk(perk_id)
	var cur = int(perks.get(perk_id, 0))
	if cur >= cap:
		return false
	perks[perk_id] = cur + 1
	return true

## Grants the "star tier" reward (STAR power-up, the shop's ⭐ 战车升阶模块,
## the "depot" event's Weapon Star Upgrade) at the persistent GameState layer
## -- used by shop_dialog.gd and event_dialog.gd, which run in spire_map.tscn
## with no live RPGManager instance to touch.
##
## On the still-undecided "default" branch this bumps the player's classic
## tier (player_tier/p2_tier, 0-3), which player.gd's default-branch weapon
## path reads for multi-shot at T2 and armor-piercing plasma at T3. But
## player.gd only reads that tier in the "default" match arm -- once a
## player commits to speed/heavy/train (which happens at literally their
## first level-up, since the branch-choice screen has no skip option), the
## tier keeps incrementing internally but has zero observable effect. All
## three "star" reward sources would silently do nothing for the ~100% of
## players who've picked a branch. Redirect to +1 permanent ATK instead --
## every branch's damage formula (RPGManager.get_atk_damage) uses atk_bonus.
static func grant_star_tier_reward(player_id: int = 1) -> void:
	var branch = tank_branch if player_id == 1 else p2_branch
	if branch == "default":
		if player_id == 1:
			player_tier = mini(player_tier + 1, 3)
		else:
			p2_tier = mini(p2_tier + 1, 3)
	else:
		atk_bonus += 1

## structure_id (String, e.g. "turret") -> owned count. Builder Controller
## structures used to be a flat "spend battle gold at placement time" cost;
## they're now shop-only consumable stock -- buy N in the shop (persists
## across battles like gold/perks), each in-battle placement consumes one
## unit instead of touching gold at all. See builder_controller.gd and
## shop_dialog.gd's BUILDING_ITEMS.
static var structure_inventory: Dictionary = {}

static func add_structure_stock(id: String, amount: int = 1) -> void:
	structure_inventory[id] = int(structure_inventory.get(id, 0)) + amount

static func consume_structure_stock(id: String) -> bool:
	var cur = int(structure_inventory.get(id, 0))
	if cur <= 0:
		return false
	structure_inventory[id] = cur - 1
	return true

static func get_structure_stock(id: String) -> int:
	return int(structure_inventory.get(id, 0))

# P2 Stats (For 2-Player Co-op)
static var p2_tier: int = 0
static var p2_lives: int = 3
static var p2_branch: String = "default"
static var p2_branch_tier: int = 0

# Battle Configuration
static var battle_type: String = "battle"
static var challenge_mode: String = "" # "", "bomb_rain", "night_ops", "vault", "night_bombs"
static var total_enemies_override: int = 15
static var boss_enabled: bool = false

# Map Grid Data
## 本次 run 的种子。用来给"选哪张手搓地图"洗牌 —— 见
## MapTemplates._pick_from_pool()。
##
## 必须**持久化**而不是每次现摇: 存档读回来以后, 已经走过的楼层要还是同一张
## 图, 否则同一个存档反复读会看到不同地形。也不能直接用 randi() 当场决定,
## 那样连同一层重进都会换图。
##
## 0 表示"这是老存档 / 还没开始 run", 此时 _pick_from_pool() 退回原来的
## 纯 floor_idx 取模行为, 不会炸。
static var run_seed: int = 0

static var spire_nodes: Dictionary = {}
static var spire_connections: Array = []

## Which of the 3 unique visual themes (Plains/Desert/Glacial) an act reuses.
## Acts 1-3 map 1:1; acts 4-8 cycle back through the same 3 themes.
static func get_visual_act(act_idx: int = -1) -> int:
	var a = current_act if act_idx == -1 else act_idx
	return ((a - 1) % 3) + 1

## How many full 3-act laps have completed before this act -- 0 for acts
## 1-3, 1 for acts 4-6, 2 for acts 7-8. Used to scale difficulty back up on
## repeat laps so acts 4-8 aren't just acts 1-3 replayed at identical
## difficulty.
static func get_difficulty_cycle(act_idx: int = -1) -> int:
	var a = current_act if act_idx == -1 else act_idx
	return (a - 1) / 3

static func get_act_name(act_idx: int = -1) -> String:
	var a = current_act if act_idx == -1 else act_idx
	var cycle = get_difficulty_cycle(a)
	var base_name = ""
	match get_visual_act(a):
		1: base_name = "诺曼底平原与河道要塞 (Frontline Plains & Rivers)"
		2: base_name = "阿塔卡马狂沙与流沙迷宫 (Atacama Quicksand Labyrinth)"
		3: base_name = "极地冻原与异次元要塞 (Glacial Singularity Citadel)"
	var suffix = "" if cycle == 0 else "  [重临 x%d / Lap %d]" % [cycle + 1, cycle + 1]
	return "ACT %d: %s%s" % [a, base_name, suffix]

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
	structure_inventory.clear()
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
	# 每局换一批地图。maxi(1, ...) 是因为 0 被 _pick_from_pool() 当作
	# "没有种子"的哨兵值。
	run_seed = maxi(1, randi())
	_generate_spire_map()

static func advance_to_next_act() -> void:
	current_act = mini(current_act + 1, max_acts)
	current_floor = 0
	current_node_id = ""
	visited_node_ids.clear()
	_generate_spire_map()

## 每层归到一个"节奏带"上，而不是给每个楼层号单独写一份池子——15 层的话手写
## 15×3 幕的池子既难维护又容易漏改。带边界之外的具体楼层号不重要，重要的是
## 相对位置（早期/中期/后期/Boss 前）在整个 max_floors 长度上等比例展开，
## 这样以后调整 max_floors 也不用跟着改这份表。
static func _floor_band(f_idx: int) -> String:
	if f_idx == 0:
		return "start"
	if f_idx == max_floors - 1:
		return "boss"
	if f_idx == max_floors - 2:
		return "pre_boss"
	var p = float(f_idx - 1) / float(maxi(1, max_floors - 3)) # 0..1 across the middle floors
	if p < 0.25:
		return "early"
	elif p < 0.5:
		return "early_mid"
	elif p < 0.75:
		return "mid"
	else:
		return "late"

static func _band_pool(band: String, act: int) -> Array:
	match band:
		"early":
			if act == 3:
				return [["battle", "challenge", "elite"], ["elite", "battle", "challenge"], ["battle", "shop", "elite"]]
			return [["battle", "challenge", "battle"], ["event", "battle", "challenge"], ["battle", "shop", "battle"]]
		"early_mid":
			if act == 2:
				return [["elite", "challenge", "shop"], ["battle", "elite", "shop"], ["challenge", "elite", "rest"]]
			elif act == 3:
				return [["elite", "challenge", "shop"], ["elite", "event", "rest"], ["shop", "elite", "challenge"]]
			return [["elite", "challenge", "shop"], ["battle", "elite", "rest"], ["challenge", "elite", "event"]]
		"mid":
			if act == 2:
				return [["elite", "shop", "challenge"], ["challenge", "elite", "elite"], ["event", "elite", "shop"]]
			elif act == 3:
				return [["elite", "shop", "challenge"], ["challenge", "elite", "elite"], ["elite", "event", "shop"]]
			return [["battle", "elite", "challenge"], ["elite", "shop", "battle"], ["challenge", "elite", "rest"]]
		"late":
			# 比 mid 更压迫: 双 elite 行出现的概率更高，为 Boss 前的强度爬升铺垫
			if act >= 2:
				return [["elite", "elite", "shop"], ["challenge", "elite", "challenge"], ["elite", "event", "elite"]]
			return [["elite", "challenge", "elite"], ["challenge", "elite", "shop"], ["elite", "battle", "challenge"]]
		"pre_boss":
			return [["rest", "shop"], ["shop", "rest"], ["rest", "event"]]
		_:
			return [["battle", "battle", "battle"]]

static func _generate_spire_map() -> void:
	spire_nodes.clear()
	spire_connections.clear()

	var floor_types: Array = []
	for f_idx in range(max_floors):
		var band = _floor_band(f_idx)
		match band:
			"start":
				floor_types.append(["battle", "battle", "battle"])
			"boss":
				floor_types.append(["boss"])
			_:
				var pool = _band_pool(band, get_visual_act())
				pool.shuffle()
				floor_types.append(pool[0])

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
				match get_visual_act():
					1: c_modes = ["bomb_rain", "night_ops", "vault"]
					2: c_modes = ["night_ops", "bomb_rain", "night_bombs"]
					_: c_modes = ["night_bombs", "bomb_rain", "night_ops"]
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

	# Connector-line generation. The old version let every node reach
	# c_idx-1/c_idx/c_idx+1 independently, which for same-width floor pairs
	# (the common case) always produced a literal X: node i's edge to i+1
	# and node i+1's edge to i cross in the middle, and stacked across many
	# floors that reads as a tangled mess rather than clean branching paths.
	#
	# Fix: assign each current-floor node a contiguous, ordered *interval*
	# of next-floor columns (a stable partition of next_count columns into
	# curr_count buckets). Interval i is always entirely at-or-left-of
	# interval i+1, so no two connector lines can ever cross, and every
	# next-floor column falls in exactly one interval so nothing is
	# orphaned. Equal-width transitions degenerate to pure verticals under
	# this scheme, so a capped one-column rightward "merge" edge is added
	# back in on top for visual variety -- it only ever reaches into the
	# *next* node's own interval start, never past it, so it still can't
	# cross that node's edges.
	for f_idx in range(floor_types.size() - 1):
		var curr_count = floor_types[f_idx].size()
		var next_count = floor_types[f_idx + 1].size()

		for c_idx in range(curr_count):
			var from_id = "f%d_n%d" % [f_idx, c_idx]
			var lo = int(floor(float(c_idx) * next_count / curr_count))
			var hi = int(floor(float(c_idx + 1) * next_count / curr_count)) - 1
			if hi < lo:
				hi = lo
			lo = clampi(lo, 0, next_count - 1)
			hi = clampi(hi, 0, next_count - 1)
			for t_idx in range(lo, hi + 1):
				spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, t_idx]})

			if hi == lo and c_idx + 1 < curr_count:
				var next_lo = int(floor(float(c_idx + 1) * next_count / curr_count))
				if next_lo > hi and randf() < 0.5:
					spire_connections.append({"from": from_id, "to": "f%d_n%d" % [f_idx + 1, next_lo]})

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

# ==================== DAILY CHALLENGE ====================
# One seeded, single-life run per calendar day: same map + same enemy
# sequence for everyone who plays today (see main.gd::start_game()'s
# DAILY_CHALLENGE branch, which calls `seed(GameState.get_daily_seed())`
# before generating the map/enemies), so a score comparison is meaningful.
# Separate save file from the campaign one so daily-challenge results don't
# interact with campaign progress at all.

const DAILY_SAVE_PATH = "user://daily_challenge_save.json"
static var _daily_best_score: int = 0
static var _daily_best_date: String = ""
static var _daily_record_loaded: bool = false

static func get_daily_date_string() -> String:
	var d = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

static func get_daily_seed() -> int:
	# String.hash() on "YYYY-MM-DD" alone has weak avalanche for these
	# particular strings -- consecutive days differ only in the last digit,
	# and hashing produced near-sequential seeds (e.g. 08-20..08-23 hashed to
	# ...619/620/621/622). Salting with a fixed tag before hashing spreads
	# adjacent days apart instead of relying on the tail character alone.
	return hash(get_daily_date_string() + "::tank_battle_daily_seed")

static func _load_daily_record() -> void:
	if _daily_record_loaded:
		return
	_daily_record_loaded = true
	if not FileAccess.file_exists(DAILY_SAVE_PATH):
		return
	var file = FileAccess.open(DAILY_SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_daily_best_score = int(json.data.get("best_score", 0))
		_daily_best_date = str(json.data.get("best_date", ""))
	file.close()

## Today's best score, or 0 if today's date has no record yet (a record from
## a previous day doesn't count -- different seed, not a fair comparison).
static func get_daily_best_score() -> int:
	_load_daily_record()
	if _daily_best_date != get_daily_date_string():
		return 0
	return _daily_best_score

## Call once when a Daily Challenge run ends. Returns true if `score` beat
## today's best.
static func submit_daily_score(score: int) -> bool:
	_load_daily_record()
	var today = get_daily_date_string()
	if _daily_best_date != today:
		_daily_best_score = 0
		_daily_best_date = today
	var is_record = score > _daily_best_score
	if is_record:
		_daily_best_score = score
	var file = FileAccess.open(DAILY_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"best_score": _daily_best_score, "best_date": _daily_best_date}, "\t"))
		file.close()
	return is_record

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
		"structure_inventory": structure_inventory,
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
		"run_seed": run_seed,
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
	unlocked_perks = _load_perk_dict(d.get("unlocked_perks", {}))
	structure_inventory = _load_perk_dict(d.get("structure_inventory", {})) # same {string: int} shape, reuse the same loader
	p2_tier = int(d.get("p2_tier", 0))
	p2_lives = int(d.get("p2_lives", 3))
	p2_branch = str(d.get("p2_branch", "default"))
	p2_branch_tier = int(d.get("p2_branch_tier", 0))
	p2_unlocked_perks = _load_perk_dict(d.get("p2_unlocked_perks", {}))
	max_hp_lvl = int(d.get("max_hp_lvl", 0))
	atk_bonus = int(d.get("atk_bonus", 0))
	speed_lvl = int(d.get("speed_lvl", 0))
	fire_rate_lvl = int(d.get("fire_rate_lvl", 0))
	regen_lvl = int(d.get("regen_lvl", 0))
	builder_lvl = int(d.get("builder_lvl", 0))
	battle_type = str(d.get("battle_type", "battle"))
	challenge_mode = str(d.get("challenge_mode", ""))
	# 老存档没有这个字段 -> 0 -> _pick_from_pool() 退回旧的取模行为。
	# 存档里已经打过的楼层因此和存档时看到的一致, 不会因为升级而变脸。
	run_seed = int(d.get("run_seed", 0))
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

## Reads either the new {perk_id: stack_count} format or an old save's
## Array[String] of unique perk ids (each implicitly 1 stack), so existing
## save files from before perks became stackable still load instead of
## erroring out on a type mismatch.
static func _load_perk_dict(raw) -> Dictionary:
	var result: Dictionary = {}
	if raw is Dictionary:
		for k in raw.keys():
			result[str(k)] = int(raw[k])
	elif raw is Array:
		for p in raw:
			result[str(p)] = 1
	return result

static func delete_saved_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
