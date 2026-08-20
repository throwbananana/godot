class_name RPGManager
extends RefCounted

signal stats_changed
signal leveled_up(new_level: int)
signal gold_changed(new_gold: int)

var level: int = 1
var current_xp: int = 0
var xp_to_next: int = 100
var gold: int = 100 # 初始赠送100金币以供建造试玩

# 属性点加成
var atk_bonus: int = 0      # 攻击力加成
var fire_rate_lvl: int = 0  # 攻速强化等级
var speed_lvl: int = 0      # 移速强化等级
var max_hp_lvl: int = 0     # 最大装甲等级
var regen_lvl: int = 0      # 纳米自愈等级
var builder_lvl: int = 0    # 防御工程强化

func reset() -> void:
	level = 1
	current_xp = 0
	xp_to_next = 100
	gold = 100
	atk_bonus = 0
	fire_rate_lvl = 0
	speed_lvl = 0
	max_hp_lvl = 0
	regen_lvl = 0
	builder_lvl = 0
	stats_changed.emit()
	gold_changed.emit(gold)

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
	current_xp += amount
	while current_xp >= xp_to_next:
		current_xp -= xp_to_next
		level += 1
		xp_to_next = int(100.0 * pow(1.4, level - 1))
		_auto_level_bonus()
		leveled_up.emit(level)
	stats_changed.emit()

func _auto_level_bonus() -> void:
	# 每升1级全属性微幅自增，并在特定等级质变
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

func get_player_max_hp() -> int:
	return 1 + max_hp_lvl

func get_speed_multiplier() -> float:
	return 1.0 + float(speed_lvl) * 0.08

func get_fire_cooldown_mult() -> float:
	return maxf(0.4, 1.0 - float(fire_rate_lvl) * 0.08)

func get_regen_rate() -> float:
	return float(regen_lvl) * 0.25 # 每秒回血

func get_building_hp_mult() -> float:
	return 1.0 + float(builder_lvl) * 0.25
