class_name RPGManager
extends RefCounted

signal stats_changed
signal gold_changed(new_gold: int)

# Battle economy and persistent-stat view. Tank weapon tier is intentionally
# NOT managed here: STAR pickups are the only source of tank tier upgrades.
var gold: int = 100

# Persistent stat bonuses loaded from GameState when entering a campaign battle.
var atk_bonus: int = 0
var fire_rate_lvl: int = 0
var speed_lvl: int = 0
var max_hp_lvl: int = 0
var regen_lvl: int = 0
var builder_lvl: int = 0

func reset() -> void:
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

func get_player_max_hp() -> int:
	return 1 + max_hp_lvl

func get_speed_multiplier() -> float:
	# One campaign speed bonus corresponds to the advertised +15% reward.
	return 1.0 + float(speed_lvl) * 0.15

func get_fire_cooldown_mult() -> float:
	return maxf(0.4, 1.0 - float(fire_rate_lvl) * 0.08)

func get_regen_rate() -> float:
	return float(regen_lvl) * 0.25

func get_building_hp_mult() -> float:
	return 1.0 + float(builder_lvl) * 0.25
