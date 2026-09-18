class_name HoldSwitch
extends Area2D

## 保持型压力板: 跟 piston_switch.gd (永久锁存) 是同一块"开上去触发"的
## 物理形状, 但语义相反——有坦克站着才通电, 全部离开就断电, 可以反复触发。
##
## 不复用 circuit_solved / circuit_gated_buildings 那套一次性锁存字典——
## electric_wall / shield_station / energy_wall 的 set_circuit_solved()
## 实现全都假设这辈子只会被叫一次 (energy_wall 甚至直接 queue_free 自己),
## 混进一个会反复翻转的信号只会把 circuit_solved[color] 提前钉死成
## "已解开"。走的是 main.gd::circuit_hold_switches / circuit_hold_doors
## 那条平行的"持续状态"通道, 配 CircuitGateDoor 使用, 见 main.gd
## ::_recompute_hold_gate() 顶部注释。
##
## 只在"是否有坦克站着"这个布尔值翻转的瞬间才广播, 不是每帧或每次
## body_entered——两台坦克同时站上去, 第二台进来不该重新触发音效/联机包,
## 一台先走另一台还在也不该断电, 所以用 _occupant_count 计数而不是单纯的
## body_entered/exited 触发。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

const GATE_COLORS := {
	"red": Color(1.0, 0.35, 0.3, 1.0),
	"blue": Color(0.35, 0.55, 1.0, 1.0),
	"green": Color(0.4, 0.9, 0.45, 1.0),
}

@export var gate_color: String = "red"

signal hold_state_changed(color: String, held: bool)

var is_held: bool = false
var _occupant_count: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	GameState.discover_encyclopedia_entry("bld_hold_switch")
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("hold_switch")

	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_jump_pad.png")
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(0.1875, 0.1875)
	_refresh_visual()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not (body is CharacterBody2D):
		return
	_occupant_count += 1
	if _occupant_count == 1:
		is_held = true
		_refresh_visual()
		SoundManager.play_pickup(get_tree())
		hold_state_changed.emit(gate_color, true)


## Area2D 在被监控的坦克 queue_free (阵亡/换房清场) 时也会照常触发这个信号,
## 不需要额外的 tree_exiting 监听——不这样处理的话, 一台坦克站在压力板上
## 被击毁, 闸门会永远以为它还站在那儿, 保持"通电"状态锁死。
func _on_body_exited(body: Node2D) -> void:
	if not (body is CharacterBody2D):
		return
	_occupant_count = max(0, _occupant_count - 1)
	if _occupant_count == 0:
		is_held = false
		_refresh_visual()
		hold_state_changed.emit(gate_color, false)


func _refresh_visual() -> void:
	var base: Color = GATE_COLORS.get(gate_color, Color.WHITE)
	if is_held:
		sprite.modulate = base * Color(1.4, 1.4, 1.4, 1.0)
		sprite.scale = Vector2(0.1875, 0.06)
	else:
		sprite.modulate = base * Color(0.6, 0.6, 0.6, 1.0)
		sprite.scale = Vector2(0.1875, 0.1875)
