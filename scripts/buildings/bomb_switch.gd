class_name BombSwitch
extends StaticBody2D

## 可摧毁开关 ("打爆开关"): 跟 piston_switch.gd (压力板, 开上去触发) 是同一套
## 电路广播接口的另一种触发方式——两者共用 switch_pressed(color) 信号名和
## main.gd::_on_circuit_switch_pressed() 的同一份 circuit_solved/
## circuit_gated_buildings 字典, 所以场景里混用红/蓝两种开关类型完全没问题
## (同色多个开关是 OR 逻辑, 任意一个触发即算解开)。
##
## extends StaticBody2D 而不是 Area2D: 它要跟 radar_station.gd 一样吃
## take_damage() 才能被子弹/爆炸物摧毁——bullet.gd 靠 is_in_group("buildings")
## + has_method("take_damage") 鸭子分派, 这条路径要求是普通碰撞体, 不是
## piston_switch 那种纯触发用的 Area2D。同时它是实心 StaticBody2D, 会挡坦克
## 通行(不像压力板可以直接开上去), 这正好配合"打爆"而不是"开上去"的设计:
## 玩家应该远远地朝它开火, 而不是把它当成能穿过的地板。
##
## 血量刻意给到很低 (2 点): 这不是一座需要正面强攻的堡垒, 它只是电路的
## "扳机", 挡道感应该来自谜题布局本身 (找到它、瞄准它), 不是靠堆血量拖时间。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

const GATE_COLORS := {
	"red": Color(1.0, 0.35, 0.3, 1.0),
	"blue": Color(0.35, 0.55, 1.0, 1.0),
}

@export var gate_color: String = "red"
@export var max_health: int = 2

signal switch_pressed(color: String)

var current_health: int = 2
var is_destroyed: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	GameState.discover_encyclopedia_entry("bld_bomb_switch")
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("bomb_switch")
	current_health = max_health

	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_jump_pad.png")
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(0.1875, 0.1875)
	sprite.modulate = GATE_COLORS.get(gate_color, Color.WHITE)

	# 持续的危险感脉动——跟 piston_switch 那种"按一下就定住"的压力板视觉区分开,
	# 提示玩家这是个"打它"的目标而不是"走上去"的地板。
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(sprite, "modulate:a", 0.6, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sprite, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)


func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health -= amount
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	var p = get_parent()
	if p:
		VFXAnimator.spawn_hit_spall(p, global_position)
	if sprite:
		var flash := create_tween()
		flash.tween_property(sprite, "modulate", Color(3.0, 0.4, 0.4), 0.06)
		flash.tween_property(sprite, "modulate", GATE_COLORS.get(gate_color, Color.WHITE), 0.08)

	if current_health <= 0:
		_detonate()


func _detonate() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	var p = get_parent()
	if p:
		VFXAnimator.spawn_shockwave(p, global_position)
		VFXAnimator.spawn_clay_debris(p, global_position)
	switch_pressed.emit(gate_color)
	queue_free()
