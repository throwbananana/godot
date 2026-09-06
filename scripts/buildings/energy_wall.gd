class_name EnergyWall
extends StaticBody2D

## 能量墙: 对**一切**火力都免疫 (子弹/激光/动能推移/四种爆破物/CRUSHER 近战全部
## 打不动), 唯一的摧毁手段是它同色的 bomb_switch 被打爆。
##
## 靠的是复用 "border" 组现成的免疫语义, 不是新写一条排除逻辑——bullet.gd /
## laser_piercer.gd / laser_ring_cutter.gd / kinetic_push_helper.gd /
## timed_bomb.gd / missile_strike.gd / oil_barrel.gd / buildings/landmine.gd /
## landmine_hazard.gd / enemy.gd(CRUSHER) 这九处判定全部已经在检查
## `is_in_group("steel") and not is_in_group("border")` 或等价写法——挂上
## steel+border 两个组, 不用碰这九个文件里的任何一行就自动继承"打不穿"的
## 全部反馈 (冷钢火星、不算破坏), 这正是 reinforced_steel 那条注释说的
## "自动继承 border 现有的反馈"同一个技巧, 只是这里要连*四种爆破物*一起免疫
## (reinforced_steel 允许 3 种爆破物破开, 这里一种都不许)。
##
## 关键: 绝不能同时加入 "buildings"/"building" 组。bullet.gd 的
## `_on_body_entered()` 是 if/elif 链, `is_in_group("buildings")` 那一支
## (259 行)排在 `is_in_group("steel")` 之前 (299 行) ——一旦挂上 buildings,
## 子弹进这条 elif 链会在 buildings 分支就短路掉, 永远走不到 steel 分支里
## 那些 `not is_in_group("border")` 保护, 免疫就形同虚设。同理它也不暴露
## take_damage()/destroy() 方法 (购买/敌方判定不会拿它当普通建筑处理)。
##
## 因为不在 buildings 组, main.gd::_clear_all() 靠清空 map_container 的全部
## 子节点而不是按组查找来重置房间, 所以这堵墙照样能在换房间时被正常清掉。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

const GATE_TINTS := {
	"red": Color(1.6, 0.55, 0.5, 1.0),
	"blue": Color(0.55, 0.85, 1.6, 1.0),
}

@export var gate_color: String = "red"

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	GameState.discover_encyclopedia_entry("bld_energy_wall")
	add_to_group("steel")
	add_to_group("border")
	add_to_group("energy_wall")

	# 贴图暂时复用钢墙贴图并按颜色调色, 跟 reinforced_steel_wall 是同一个
	# "先上玩法, 美术占位"先例——还没走 Blender 渲染流程出专属美术。
	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png")
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(0.1875, 0.1875)
	sprite.modulate = GATE_TINTS.get(gate_color, Color.WHITE)

	var base_tint: Color = GATE_TINTS.get(gate_color, Color.WHITE)
	var dim_tint := Color(base_tint.r * 0.7, base_tint.g * 0.7, base_tint.b * 0.7, base_tint.a)
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(sprite, "modulate", dim_tint, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sprite, "modulate", base_tint, 0.6).set_trans(Tween.TRANS_SINE)


## 同色的 bomb_switch 被打爆后, main.gd::_on_circuit_switch_pressed() 调这个——
## 跟 electric_wall/shield_station 共用同一个方法名, 但这里的语义是"摧毁自己"
## 而不是"切断/接通供电": 墙本身从此从场上消失, 不是变成可穿过的惰性状态。
## queue_free() 不需要 call_deferred: 它本来就是安全的延迟释放, 会撞上物理
## flush 报错的只有 collision_shape.disabled 这类立即生效的属性赋值, 这里
## 完全没有用到。
func set_circuit_solved(solved: bool) -> void:
	if not solved:
		return
	var p = get_parent()
	if p:
		VFXAnimator.spawn_shockwave(p, global_position)
		VFXAnimator.spawn_clay_debris(p, global_position)
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	queue_free()
