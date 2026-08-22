class_name RPGManager
extends RefCounted

signal stats_changed
signal leveled_up(new_level: int)
signal gold_changed(new_gold: int)
signal branch_changed(player_id: int, new_branch: String, new_tier: int)

var level: int = 1
var current_xp: int = 0
var xp_to_next: int = 100
var gold: int = 100
var xp_earned_this_battle: int = 0 # reset at battle start, read by main.gd's Factory reward multiplier

# 属性点加成
var atk_bonus: int = 0      # 攻击力加成
var fire_rate_lvl: int = 0  # 攻速强化等级
var speed_lvl: int = 0      # 移速强化等级
var max_hp_lvl: int = 0     # 最大装甲等级
var regen_lvl: int = 0      # 纳米自愈等级
var builder_lvl: int = 0    # 防御工程强化

# RPG 分支流派与特性 (P1)
var tank_branch: String = "default" # "default", "speed", "heavy", "train"
var branch_tier: int = 0            # 0=基础, 1=一阶进阶, 2=二阶终极
var unlocked_perks: Dictionary = {} # perk_id -> stack count, see GameState.PERK_MAX_STACKS

# RPG 分支流派与特性 (P2 - 双人合作各自独立选择)
var p2_tank_branch: String = "default"
var p2_branch_tier: int = 0
var p2_unlocked_perks: Dictionary = {}

# 每额外一层叠加的边际价值递减曲线 (第1层100%/第2层65%/第3层45%)，避免线性
# 叠 3 层的数值感觉失控，同时仍然让每一次选择都有明确增量。
const PERK_STACK_CURVE := [1.0, 0.65, 0.45]

func get_branch(player_id: int = 1) -> String:
	return tank_branch if player_id == 1 else p2_tank_branch

func get_branch_tier(player_id: int = 1) -> int:
	return branch_tier if player_id == 1 else p2_branch_tier

func reset() -> void:
	level = 1
	current_xp = 0
	xp_to_next = 100
	gold = 100
	xp_earned_this_battle = 0
	atk_bonus = 0
	fire_rate_lvl = 0
	speed_lvl = 0
	max_hp_lvl = 0
	regen_lvl = 0
	builder_lvl = 0
	tank_branch = "default"
	branch_tier = 0
	unlocked_perks.clear()
	p2_tank_branch = "default"
	p2_branch_tier = 0
	p2_unlocked_perks.clear()
	stats_changed.emit()
	gold_changed.emit(gold)
	branch_changed.emit(1, tank_branch, branch_tier)
	branch_changed.emit(2, p2_tank_branch, p2_branch_tier)

func sync_from_game_state() -> void:
	level = GameState.player_level
	current_xp = GameState.player_xp
	xp_to_next = GameState.xp_to_next if GameState.xp_to_next > 0 else int(100.0 * pow(1.22, level - 1))
	gold = GameState.gold
	xp_earned_this_battle = 0
	atk_bonus = GameState.atk_bonus
	fire_rate_lvl = GameState.fire_rate_lvl
	speed_lvl = GameState.speed_lvl
	max_hp_lvl = GameState.max_hp_lvl
	regen_lvl = GameState.regen_lvl
	builder_lvl = GameState.builder_lvl
	tank_branch = GameState.tank_branch
	branch_tier = GameState.branch_tier
	unlocked_perks = GameState.unlocked_perks.duplicate()
	p2_tank_branch = GameState.p2_branch
	p2_branch_tier = GameState.p2_branch_tier
	p2_unlocked_perks = GameState.p2_unlocked_perks.duplicate()

	# 处理事件或商店增加的 XP 跨场景升级
	while current_xp >= xp_to_next:
		current_xp -= xp_to_next
		level += 1
		xp_to_next = int(100.0 * pow(1.22, level - 1))
		_auto_level_bonus()
		leveled_up.emit(level)

	stats_changed.emit()
	gold_changed.emit(gold)
	branch_changed.emit(1, tank_branch, branch_tier)
	branch_changed.emit(2, p2_tank_branch, p2_branch_tier)

func sync_to_game_state() -> void:
	GameState.player_level = level
	GameState.player_xp = current_xp
	GameState.xp_to_next = xp_to_next
	GameState.gold = gold
	GameState.atk_bonus = atk_bonus
	GameState.fire_rate_lvl = fire_rate_lvl
	GameState.speed_lvl = speed_lvl
	GameState.max_hp_lvl = max_hp_lvl
	GameState.regen_lvl = regen_lvl
	GameState.builder_lvl = builder_lvl
	GameState.tank_branch = tank_branch
	GameState.branch_tier = branch_tier
	GameState.unlocked_perks = unlocked_perks.duplicate()
	GameState.p2_branch = p2_tank_branch
	GameState.p2_branch_tier = p2_branch_tier
	GameState.p2_unlocked_perks = p2_unlocked_perks.duplicate()

func set_branch(new_branch: String, player_id: int = 1) -> void:
	if player_id == 1:
		tank_branch = new_branch
		if branch_tier == 0:
			branch_tier = 1
	else:
		p2_tank_branch = new_branch
		if p2_branch_tier == 0:
			p2_branch_tier = 1
	sync_to_game_state()
	branch_changed.emit(player_id, get_branch(player_id), get_branch_tier(player_id))
	stats_changed.emit()

func promote_branch_tier(player_id: int = 1) -> void:
	if player_id == 1:
		branch_tier = mini(branch_tier + 1, 2)
	else:
		p2_branch_tier = mini(p2_branch_tier + 1, 2)
	sync_to_game_state()
	branch_changed.emit(player_id, get_branch(player_id), get_branch_tier(player_id))
	stats_changed.emit()

## Returns false (no-op) once perk_id is already at GameState.max_stacks_for_perk.
func add_perk(perk_id: String, player_id: int = 1) -> bool:
	var perks = unlocked_perks if player_id == 1 else p2_unlocked_perks
	var cur = int(perks.get(perk_id, 0))
	if cur >= GameState.max_stacks_for_perk(perk_id):
		return false
	perks[perk_id] = cur + 1
	sync_to_game_state()
	stats_changed.emit()
	return true

func has_perk(perk_id: String, player_id: int = 1) -> bool:
	return get_perk_stacks(perk_id, player_id) > 0

func get_perk_stacks(perk_id: String, player_id: int = 1) -> int:
	var perks = unlocked_perks if player_id == 1 else p2_unlocked_perks
	return int(perks.get(perk_id, 0))

## base * how many stacks owned, run through PERK_STACK_CURVE so each
## additional copy of the same perk still matters but tapers off instead of
## scaling linearly (3 stacks of rapid_loader is +65% total, not +90%).
func get_perk_value(perk_id: String, base: float, player_id: int = 1) -> float:
	var stacks = get_perk_stacks(perk_id, player_id)
	var total := 0.0
	for i in range(mini(stacks, PERK_STACK_CURVE.size())):
		total += base * PERK_STACK_CURVE[i]
	return total

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false

func add_xp(amount: int) -> void:
	xp_earned_this_battle += amount
	current_xp += amount
	while current_xp >= xp_to_next:
		current_xp -= xp_to_next
		level += 1
		xp_to_next = int(100.0 * pow(1.22, level - 1))
		_auto_level_bonus()
		leveled_up.emit(level)
	stats_changed.emit()

func _auto_level_bonus() -> void:
	atk_bonus += 1
	if level % 2 == 0:
		fire_rate_lvl += 1
	if level % 3 == 0:
		max_hp_lvl += 1
	if level % 4 == 0:
		regen_lvl += 1
	if level % 2 == 1:
		speed_lvl += 1
		builder_lvl += 1
	stats_changed.emit()

func get_player_max_hp(player_id: int = 1) -> int:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var hp = 1 + max_hp_lvl
	if branch == "heavy":
		hp += 2 + tier * 2
	elif branch == "train":
		hp += 1 + tier
	hp += int(round(get_perk_value("titan_plating", 2.0, player_id)))
	return hp

func get_speed_multiplier(player_id: int = 1) -> float:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var mult = 1.0 + float(speed_lvl) * 0.04
	if branch == "speed":
		mult += 0.30 + float(tier) * 0.15
	elif branch == "heavy":
		mult -= 0.10 # 重装型较重，稍显沉稳
	mult += get_perk_value("nitro_booster", 0.18, player_id)
	return maxf(0.5, mult)

func get_fire_cooldown_mult(player_id: int = 1) -> float:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var rate = 1.0 + float(fire_rate_lvl) * 0.10
	if branch == "speed":
		rate += 0.70 + float(tier) * 0.40 # 极高射速
	elif branch == "heavy":
		rate *= 0.85 # 重型巨炮单发威猛，装填稍慢
	rate += get_perk_value("rapid_loader", 0.30, player_id)
	return 1.0 / rate

func get_atk_damage(player_id: int = 1) -> int:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var dmg = 1 + atk_bonus
	if branch == "heavy":
		dmg += 2 + tier * 2
	dmg += int(round(get_perk_value("high_explosive", 2.0, player_id)))
	return dmg

func get_regen_rate(player_id: int = 1) -> float:
	var rate = float(regen_lvl) * 0.25
	rate += get_perk_value("nano_repair", 0.50, player_id)
	return rate

func get_building_hp_mult() -> float:
	return 1.0 + float(builder_lvl) * 0.25

