class_name Bunker
extends StaticBody2D

## 战术防御堡垒 (Tactical Bunker)
## 机制：
## 1. 具有 4 个朝向 (UP, RIGHT, DOWN, LEFT)，默认 UP (正面朝上)。
## 2. 躲在堡垒后方向前射出的子弹 (与堡垒朝向一致) 可以自由穿过射击孔出膛，不伤害堡垒。
## 3. 正面飞来的子弹 (迎头撞击正面重装甲防盾) 被堡垒格挡弹开/销毁，低等级子弹无法打穿且堡垒免伤。
## 4. 从左面、右面 (以及后方非射击孔区域) 射入的子弹命中薄弱侧翼，正常扣除堡垒 HP 并可摧毁堡垒。

enum FacingDirection { UP = 0, RIGHT = 1, DOWN = 2, LEFT = 3 }

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var facing: FacingDirection = FacingDirection.UP
@export var max_health: int = 6
var current_health: int = 6
var is_destroyed: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("destructible")
	add_to_group("bunker")
	current_health = max_health
	_update_visuals()

func set_facing(new_facing: int) -> void:
	facing = new_facing as FacingDirection
	_update_visuals()

func get_facing_vector() -> Vector2:
	match facing:
		FacingDirection.UP:
			return Vector2.UP
		FacingDirection.RIGHT:
			return Vector2.RIGHT
		FacingDirection.DOWN:
			return Vector2.DOWN
		FacingDirection.LEFT:
			return Vector2.LEFT
		_:
			return Vector2.UP

func _update_visuals() -> void:
	if not is_inside_tree():
		return
	var f_idx = int(facing) % 4
	var tex_path = "res://assets/sprites/buildings/bunker_f%d.png" % f_idx
	var tex = TextureHelper.get_tex(tex_path)
	if not tex:
		tex = TextureHelper.get_tex("res://assets/sprites/buildings/bunker.png")
	if sprite and tex:
		sprite.texture = tex
		# 如果使用的是统一 bunker.png 贴图，根据朝向旋转
		if not ResourceLoader.exists(tex_path):
			var angles = [0.0, PI * 0.5, PI, PI * 1.5]
			sprite.rotation = angles[f_idx]
		else:
			sprite.rotation = 0.0

## 处理来自 bullet.gd 的击中判定
## 返回 true 表示已由堡垒接管并处理（不执行 bullet 默认通用销毁逻辑）
func handle_bullet_hit(bullet: Node, hit_pos: Vector2, hit_dir: Vector2) -> bool:
	if is_destroyed or not is_inside_tree():
		return false

	var f_vec = get_facing_vector()
	var b_dir = hit_dir.normalized()
	if b_dir == Vector2.ZERO and "direction" in bullet:
		b_dir = bullet.direction.normalized()

	var dot = b_dir.dot(f_vec)

	# 1. 从掩体后方向前开火 (子弹与堡垒朝向一致, dot > 0.6)
	# 坦克躲在后面向前开火：允许子弹穿透射击孔飞出！
	if dot > 0.6:
		# 播放穿透射击孔微火花/烟尘
		VFXAnimator.spawn_dust_puff(get_parent(), hit_pos)
		if "add_collision_exception_with" in bullet:
			bullet.add_collision_exception_with(self)
		return true # 允许子弹继续飞行，不消耗子弹，不损毁堡垒

	# 2. 从正面飞来的敌方子弹 (迎头撞击正面重盾, dot < -0.6)
	# 正面重装甲格挡低级炮弹！
	elif dot < -0.6:
		var can_destroy_steel = false
		if "can_destroy_steel" in bullet:
			can_destroy_steel = bullet.can_destroy_steel

		# 如果是 3 阶等离子破钢炮弹，则强行击破堡垒正面
		if can_destroy_steel:
			take_damage(bullet.damage if "damage" in bullet else 2)
			VFXAnimator.spawn_clay_debris(get_parent(), hit_pos)
		else:
			# 低等级炮弹无法打穿正面，完全被重装甲吸收/格挡！
			SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_dust_puff(get_parent(), hit_pos)
			VFXAnimator.spawn_clay_debris(get_parent(), hit_pos)
			# 堡垒产生坚固受击金属震颤反馈
			_play_deflect_feedback()

		# 销毁来袭子弹
		if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
			bullet.queue_free()
		return true

	# 3. 从左右侧面 (以及斜向非射击孔区域) 射入的子弹 (abs(dot) <= 0.6)
	# 命中薄弱侧翼，正常承受伤害并破坏堡垒！
	else:
		var dmg = bullet.damage if "damage" in bullet else 1
		take_damage(dmg)
		SoundManager.play_hit_brick(get_tree())
		VFXAnimator.spawn_clay_debris(get_parent(), hit_pos)

		if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
			bullet.queue_free()
		return true

func _play_deflect_feedback() -> void:
	if not is_inside_tree() or sprite == null:
		return
	var f_vec = get_facing_vector()
	var orig_pos = sprite.position
	var tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position", orig_pos - f_vec * 3.0, 0.05)
	tw.tween_property(sprite, "position", orig_pos, 0.08)
	tw.parallel().tween_property(sprite, "modulate", Color(1.8, 1.8, 2.0), 0.05)
	tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.08)

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health -= amount
	_play_hit_flash()
	if current_health <= 0:
		destroy()

func _play_hit_flash() -> void:
	if not is_inside_tree() or sprite == null:
		return
	var tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate", Color(2.5, 0.6, 0.6), 0.06)
	tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.10)

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	queue_free()
