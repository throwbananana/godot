class_name CircuitGateDoor
extends StaticBody2D

## 电路闸门: 保持型压力板 (HoldSwitch) 控制的可逆闸门——有人踩着同色的
## 压力板就打开 (可通行, 子弹能过), 全部离开就重新关闭。跟 electric_wall/
## shield_station/energy_wall 的 set_circuit_solved(true) 不一样, 那三个
## 都是"这辈子只翻一次"的设计, 这里的 set_gate_open() 会被反复调用、反复
## 开合, 所以专门走 main.gd::circuit_hold_switches / circuit_hold_doors
## 那条独立通道, 不登记进 circuit_gated_buildings (那本字典的调用方假设
## set_circuit_solved 只会被叫一次, 混进一个可逆对象会让 circuit_solved[color]
## 被提前判定为"已解开", 而这扇门其实随时会关上)。
##
## 复用 energy_wall.gd 已经验证过的技巧: 只挂 steel + border 两个组就能让
## 子弹/激光/动能推移/四种爆破物/CRUSHER 近战全部免疫, 不用碰那九处判定。
## 但闸门打开的时候要真的能穿过——不是"假装免疫", 而是直接把
## CollisionShape2D.disabled 设 true, 碰撞体一失效, 物理查询直接跳过这个
## 节点, 子弹和坦克都照常通过。
##
## 绝不能加入 "buildings"/"building" 组: bullet.gd 的 if/elif 链会在
## buildings 分支先短路掉, 永远走不到 steel 分支里 `not is_in_group(border)`
## 的保护, 关闭状态下的"打不穿"就形同虚设——跟 energy_wall.gd 顶部注释是
## 同一个坑。
##
## collision_shape.disabled 的赋值要 call_deferred: 触发链路是
## HoldSwitch.body_entered/exited (Area2D 信号) -> main.gd 统一入口 -> 这里,
## 全程都在物理查询 flush 期间同步调用, 直接改会撞上引擎那句 "Can't change
## this state while flushing queries"——跟 electric_wall.gd 顶部注释是
## 同一个坑。

const TextureHelper = preload("res://scripts/texture_helper.gd")

const GATE_COLORS := {
	"red": Color(1.0, 0.35, 0.3, 1.0),
	"blue": Color(0.35, 0.55, 1.0, 1.0),
	"green": Color(0.4, 0.9, 0.45, 1.0),
}

@export var gate_color: String = "red"

var is_open: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	GameState.discover_encyclopedia_entry("bld_circuit_gate_door")
	add_to_group("steel")
	add_to_group("border")
	add_to_group("circuit_gate_door")

	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png")
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(0.1875, 0.1875)
	_refresh_visual()


func set_gate_open(open: bool) -> void:
	if is_open == open:
		return
	is_open = open
	if collision_shape:
		collision_shape.set_deferred("disabled", open)
	_refresh_visual()


func _refresh_visual() -> void:
	var base: Color = GATE_COLORS.get(gate_color, Color.WHITE)
	if is_open:
		sprite.modulate = Color(base.r, base.g, base.b, 0.28)
	else:
		sprite.modulate = base
