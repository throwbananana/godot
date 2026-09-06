class_name PistonSwitch
extends Area2D

## 活塞压力板: 任何坦克(玩家或敌人)开上去就永久按下, 按下瞬间给同色的
## 电路广播一次"接通"事件——main.gd::_on_circuit_switch_pressed() 收到后
## 会把 circuit_gated_buildings[gate_color] 里所有还活着的建筑一次性
## set_circuit_solved(true)。
##
## 永久锁存, 不是"松开就断电": 单车玩法下"站在开关上"和"走过开关打开的那条
## 路"是两个互斥的位置, 松开就断电的设计只能支持"解谜=削弱一个目标"这一种
## 玩法, 支持不了"解谜=打开一条新路"——后者恰恰是迷宫解密关卡最常见的用法。
## 按一次永久生效, 玩家可以按完再走过去。
##
## 贴图占位: 复用 tile_jump_pad 的圆盘造型当压力板底座, 用 modulate 按
## gate_color 上色区分红/蓝——还没走 Blender 那套离线渲染流程出专属美术,
## 跟 CLAUDE.md 记录的 reinforced_steel_wall 是同一个"先上玩法, 美术占位"
## 的先例。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

const GATE_COLORS := {
	"red": Color(1.0, 0.35, 0.3, 1.0),
	"blue": Color(0.35, 0.55, 1.0, 1.0),
}

@export var gate_color: String = "red"

signal switch_pressed(color: String)

var pressed: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	GameState.discover_encyclopedia_entry("bld_piston_switch")
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("piston_switch")

	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_jump_pad.png")
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(0.1875, 0.1875)
	sprite.modulate = GATE_COLORS.get(gate_color, Color.WHITE)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if pressed:
		return
	if not (body is CharacterBody2D):
		return
	pressed = true
	SoundManager.play_pickup(get_tree())
	# 按下之后视觉上"沉下去并锁死": 缩小压扁 + 提亮, 跟其它建筑用 tween
	# 做瞬时反馈是同一个idiom (roller_wall/fortified_wall 的受击闪光),
	# 只是这里停在终态不弹回去, 因为按下是永久的。
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(0.1875, 0.06), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sprite.modulate = GATE_COLORS.get(gate_color, Color.WHITE) * Color(1.4, 1.4, 1.4, 1.0)
	switch_pressed.emit(gate_color)
