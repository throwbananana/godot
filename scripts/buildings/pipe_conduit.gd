class_name PipeConduit
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

## 管道方向预设 (90° 导流转角)
## 0: 左侧进入 -> 上方射出 (LEFT -> UP)
## 1: 上方进入 -> 右侧射出 (UP -> RIGHT)
## 2: 右侧进入 -> 下方射出 (RIGHT -> DOWN)
## 3: 下方进入 -> 左侧射出 (DOWN -> LEFT)
enum Orientation {
	LEFT_TO_UP = 0,
	UP_TO_RIGHT = 1,
	RIGHT_TO_DOWN = 2,
	DOWN_TO_LEFT = 3
}

## PipeConduit.Orientation (完整限定名), 不是裸 Orientation ——
## Godot 4.5 在"带 class_name 的脚本内联引用自己的枚举"这种写法上有解析怪癖:
## `Orientation.LEFT_TO_UP` 这个枚举常量表达式被推断成 "PipeConduit.Orientation"
## 类型, 但 `: Orientation` 这个类型标注解析出来是裸的 "Orientation" 类型,
## 两者在类型检查器眼里不是同一个类型, 于是报 "Cannot assign a value of type
## PipeConduit.Orientation to variable... with specified type Orientation"。
## 全项目搜过, 没有第二处这么写枚举 + @export + class_name 的组合, 是这里独有。
## 统一用完整限定名后两边类型一致, 编译通过。
@export var orientation: PipeConduit.Orientation = PipeConduit.Orientation.LEFT_TO_UP
@export var max_health: int = 4

var current_health: int = 4
var is_destroyed: bool = false

# 导流向量: entry_direction 表示打入管道的子弹飞行方向，exit_direction 表示射出方向
var entry_direction: Vector2 = Vector2.RIGHT
var exit_direction: Vector2 = Vector2.UP

var sprite: Sprite2D
var collision_shape: CollisionShape2D
var frames: Array[Texture2D] = []
var current_frame_idx: int = 0
var anim_timer: float = 0.0

var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("pipe_conduit")
	add_to_group("destructible")

	explosion_scene = load("res://scenes/explosion.tscn")

	# 加载动画帧
	var base_tex = TextureHelper.get_tex("res://assets/sprites/buildings/pipe_conduit.png")
	for i in range(4):
		var f_tex = TextureHelper.get_tex("res://assets/sprites/buildings/pipe_conduit_f%d.png" % i)
		if f_tex:
			frames.append(f_tex)

	sprite = Sprite2D.new()
	sprite.texture = base_tex if base_tex else (frames[0] if frames.size() > 0 else null)
	sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)
	add_child(sprite)

	collision_shape = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(42.0, 42.0)
	collision_shape.shape = box
	add_child(collision_shape)

	var main = get_tree().current_scene if is_inside_tree() else null
	var hp_mult = main.rpg_mgr.get_building_hp_mult() if (main and "rpg_mgr" in main and main.rpg_mgr) else 1.0
	current_health = maxi(1, int(max_health * hp_mult))
	max_health = current_health

	_apply_orientation()

func set_orientation(orient: int) -> void:
	orientation = orient as PipeConduit.Orientation
	_apply_orientation()

## 依据给定的输入/输出方向智能设置管道
func set_flow_directions(in_dir: Vector2, out_dir: Vector2) -> void:
	entry_direction = in_dir.normalized()
	exit_direction = out_dir.normalized()
	
	# 根据常见的 4 种主正交转角适配旋转角度
	if entry_direction == Vector2.RIGHT and exit_direction == Vector2.UP:
		orientation = Orientation.LEFT_TO_UP
	elif entry_direction == Vector2.DOWN and exit_direction == Vector2.RIGHT:
		orientation = Orientation.UP_TO_RIGHT
	elif entry_direction == Vector2.LEFT and exit_direction == Vector2.DOWN:
		orientation = Orientation.RIGHT_TO_DOWN
	elif entry_direction == Vector2.UP and exit_direction == Vector2.LEFT:
		orientation = Orientation.DOWN_TO_LEFT
	
	if sprite:
		match orientation:
			Orientation.LEFT_TO_UP: sprite.rotation = 0.0
			Orientation.UP_TO_RIGHT: sprite.rotation = PI / 2.0
			Orientation.RIGHT_TO_DOWN: sprite.rotation = PI
			Orientation.DOWN_TO_LEFT: sprite.rotation = 3.0 * PI / 2.0

func _apply_orientation() -> void:
	match orientation:
		Orientation.LEFT_TO_UP:
			# 子弹从左侧向右飞入，从顶部向上飞出
			entry_direction = Vector2.RIGHT
			exit_direction = Vector2.UP
			if sprite: sprite.rotation = 0.0
		Orientation.UP_TO_RIGHT:
			# 子弹从上方朝下飞入，从右侧向右飞出
			entry_direction = Vector2.DOWN
			exit_direction = Vector2.RIGHT
			if sprite: sprite.rotation = PI / 2.0
		Orientation.RIGHT_TO_DOWN:
			# 子弹从右侧朝左飞入，从下方朝下飞出
			entry_direction = Vector2.LEFT
			exit_direction = Vector2.DOWN
			if sprite: sprite.rotation = PI
		Orientation.DOWN_TO_LEFT:
			# 子弹从下方朝上飞入，从左侧朝左飞出
			entry_direction = Vector2.UP
			exit_direction = Vector2.LEFT
			if sprite: sprite.rotation = 3.0 * PI / 2.0

func _process(delta: float) -> void:
	if frames.size() > 1 and sprite:
		anim_timer += delta
		if anim_timer >= 0.15:
			anim_timer = 0.0
			current_frame_idx = (current_frame_idx + 1) % frames.size()
			sprite.texture = frames[current_frame_idx]

## 核心交互: 处理子弹命中
## 返回 true 表示子弹成功从管道入口打入并重定向射出 (子弹存活并转向)
## 返回 false 表示击中管道非入口外壁 (管道承受伤害，子弹被阻挡销毁)
func handle_bullet_hit(bullet: Node2D, hit_pos: Vector2, hit_dir: Vector2) -> bool:
	if is_destroyed:
		return false

	var bullet_dir = hit_dir.normalized()
	var expected_entry = entry_direction.normalized()

	# 检查子弹飞行方向是否对准管道入口 (点积 > 0.6 表示顺着入口方向射入)
	var dot_align = bullet_dir.dot(expected_entry)
	if dot_align > 0.6:
		# ========== 成功打入管道入口 ==========
		_redirect_bullet(bullet)
		return true
	else:
		# ========== 打在非入口方向处，破坏该建筑 ==========
		var dmg = 1
		if "damage" in bullet:
			dmg = bullet.damage
		take_damage(dmg)
		return false

func _redirect_bullet(bullet: Node2D) -> void:
	var out_dir = exit_direction.normalized()
	var out_pos = global_position + out_dir * 26.0

	# 改变子弹坐标与飞行方向
	bullet.global_position = out_pos
	if "direction" in bullet:
		bullet.direction = out_dir
	bullet.rotation = out_dir.angle() + PI / 2.0

	if "speed" in bullet:
		bullet.speed = maxf(bullet.speed, 520.0)

	# 播放出管加速音效与特效
	if is_inside_tree() and get_tree():
		SoundManager.play_laser(get_tree())
	var p = get_parent()
	if p:
		VFXAnimator.spawn_dust_puff(p, out_pos)
		VFXAnimator.spawn_dust_puff(p, global_position - entry_direction.normalized() * 16.0)

	# 管道自身弹性脉冲反馈
	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "scale", Vector2(56.0 / 256.0, 56.0 / 256.0), 0.06)
		tw.tween_property(sprite, "scale", Vector2(48.0 / 256.0, 48.0 / 256.0), 0.08)

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health -= amount
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	var p = get_parent()
	if p:
		VFXAnimator.spawn_clay_debris(p, global_position)

	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(2.5, 0.4, 0.4), 0.06)
		tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.08)

	if current_health <= 0:
		destroy()

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	var p = get_parent()
	if p:
		if explosion_scene:
			var exp_inst = explosion_scene.instantiate()
			p.add_child(exp_inst)
			exp_inst.global_position = global_position
		VFXAnimator.spawn_shockwave(p, global_position)
		VFXAnimator.spawn_clay_debris(p, global_position)
	queue_free()
