class_name WoodenWall
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const KineticPushHelper = preload("res://scripts/kinetic_push_helper.gd")

@export var max_health: int = 3
var current_health: int = 3
var is_moving: bool = false
var push_step: float = 48.0

var sprite: Sprite2D
var collision_shape: CollisionShape2D
var move_frames: Array[Texture2D] = []
var damage_frames: Array[Texture2D] = []
var base_texture: Texture2D
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("building")
	add_to_group("wooden_wall")
	add_to_group("wood")
	add_to_group("destructible")

	explosion_scene = load("res://scenes/explosion.tscn")

	# Base sprite & Damage stages (dmg0=intact, dmg1=cracked, dmg2=splintered)
	base_texture = TextureHelper.get_tex("res://assets/sprites/buildings/wooden_wall.png")
	for i in range(3):
		var d_tex = TextureHelper.get_tex("res://assets/sprites/buildings/wooden_wall_dmg%d.png" % i)
		if d_tex:
			damage_frames.append(d_tex)
		elif base_texture:
			damage_frames.append(base_texture)

	# Kinetic movement / sliding frames (f0..f3)
	for i in range(4):
		var f_tex = TextureHelper.get_tex("res://assets/sprites/buildings/wooden_wall_f%d.png" % i)
		if f_tex:
			move_frames.append(f_tex)

	sprite = Sprite2D.new()
	sprite.texture = damage_frames[0] if damage_frames.size() > 0 else base_texture
	sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)
	add_child(sprite)

	collision_shape = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(44.0, 44.0)
	collision_shape.shape = box
	add_child(collision_shape)

	var main = get_tree().current_scene if is_inside_tree() else null
	var hp_mult = main.rpg_mgr.get_building_hp_mult() if (main and "rpg_mgr" in main and main.rpg_mgr) else 1.0
	current_health = maxi(1, int(max_health * hp_mult))
	max_health = current_health
	_update_visual_state()

func _update_visual_state() -> void:
	if not sprite or is_moving:
		return
	if damage_frames.size() >= 3:
		if current_health >= 3:
			sprite.texture = damage_frames[0]
		elif current_health == 2:
			sprite.texture = damage_frames[1]
		else:
			sprite.texture = damage_frames[2]
	elif base_texture:
		sprite.texture = base_texture

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	_update_visual_state()
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(0.4, 2.0, 0.6), 0.1)
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func take_damage(amount: int) -> void:
	current_health -= amount
	SoundManager.play_hit_brick(get_tree())
	var p = get_parent()
	if p:
		VFXAnimator.spawn_wood_debris(p, global_position)
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(2.4, 1.8, 1.2), 0.06)
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.06)
	_update_visual_state()
	if current_health <= 0:
		destroy()

func destroy() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		var p = get_parent()
		if p:
			p.add_child(exp_inst)
			exp_inst.global_position = global_position
	var p_node = get_parent()
	if p_node:
		VFXAnimator.spawn_shockwave(p_node, global_position)
		VFXAnimator.spawn_wood_debris(p_node, global_position)

	# 木墙破裂时向周围迸发木刺弹片对贴近的敌军造成 1 点破片震荡伤害
	_trigger_splinter_blast()
	queue_free()

func _trigger_splinter_blast() -> void:
	if not is_inside_tree() or get_world_2d() == null:
		return
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 48.0
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 1 | 2 | 16
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var hits = space_state.intersect_shape(query, 6)
	for hit in hits:
		var collider = hit.get("collider")
		if is_instance_valid(collider) and collider != self:
			if collider.is_in_group("enemy") or collider.is_in_group("enemies"):
				if collider.has_method("take_damage"):
					collider.take_damage(1)

## 受到具有方向动量攻击 (如子弹命中或推力) 时的响应
func take_hit_direction(amount: int, hit_dir: Vector2) -> void:
	if amount >= 99:
		destroy()
		return

	take_damage(amount)
	if current_health <= 0 or not is_inside_tree():
		return

	if hit_dir != Vector2.ZERO and not is_moving:
		_try_push(hit_dir)

## 受到坦克直接身体接触推挤 (Physical Tank Contact Push)
func take_push(push_dir: Vector2, _pusher: Node = null) -> void:
	if not is_moving and push_dir != Vector2.ZERO:
		_try_push(push_dir)

func _try_push(hit_dir: Vector2) -> void:
	# 1. 贴合到主要正交轴向 (Snap to dominant cardinal direction)
	var cardinal = Vector2.ZERO
	if absf(hit_dir.x) > absf(hit_dir.y):
		cardinal = Vector2.RIGHT if hit_dir.x > 0.0 else Vector2.LEFT
	else:
		cardinal = Vector2.DOWN if hit_dir.y > 0.0 else Vector2.UP

	var target_pos = global_position + cardinal * push_step

	# 2. 地图边界限制检查
	var main = get_tree().current_scene if is_inside_tree() else null
	if main and "game_area" in main and main.game_area:
		var local_target = main.game_area.to_local(target_pos)
		var min_b = 24.0
		var max_b = 13.0 * 48.0 - 24.0
		if local_target.x < min_b - 6.0 or local_target.x > max_b + 6.0 or local_target.y < min_b - 6.0 or local_target.y > max_b + 6.0:
			_shake_blocked(true)
			return

	# 3. 目标格物理障碍物检测
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(36.0, 36.0)
	query.shape = shape
	query.transform = Transform2D(0.0, target_pos)
	query.collision_mask = 1 | 2 | 16 # Walls, terrain, border, buildings, enemies, players
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var hits = space_state.intersect_shape(query, 6)
	var blocked_by_solid = false

	for hit in hits:
		var collider = hit.get("collider")
		if not is_instance_valid(collider) or collider == self:
			continue

		# 撞碎普通砖块与软陶泥 (Crush destructible terrain)
		if collider.is_in_group("brick") or collider.is_in_group("hard_clay"):
			if collider.has_method("take_hit"):
				collider.take_hit(3)
			else:
				var p_node = get_parent() if get_parent() else self
				VFXAnimator.spawn_dust_puff(p_node, collider.global_position)
				VFXAnimator.spawn_wood_debris(p_node, collider.global_position)
				collider.queue_free()
		# 顶撞敌人坦克：造成 2 点伤害与眩晕，若被挤压在硬物死角则触发粉碎消灭
		elif collider.is_in_group("enemy") or collider.is_in_group("enemies"):
			var behind_pos = target_pos + cardinal * push_step
			var is_pinned = KineticPushHelper._is_position_blocked_solid(self, behind_pos, collider, main, 24.0, 13.0 * 48.0 - 24.0)
			if is_pinned:
				KineticPushHelper._trigger_squeeze_kill(collider, self, main, true, false, false)
			else:
				if collider.has_method("take_damage"):
					collider.take_damage(2)
				if collider.has_method("freeze"):
					collider.freeze(0.6)
				KineticPushHelper._trigger_knockback_unit(collider, behind_pos, get_parent() if get_parent() else self)
				var p_node = get_parent() if get_parent() else self
				VFXAnimator.spawn_wood_debris(p_node, collider.global_position)
				VFXAnimator.spawn_dust_puff(p_node, collider.global_position)
		# 坚硬不可移动固体障碍（钢铁/地图边界/基地/建筑）
		elif collider.is_in_group("steel") or collider.is_in_group("border") or collider.is_in_group("buildings") or collider.is_in_group("base"):
			blocked_by_solid = true

	if blocked_by_solid:
		# 撞击硬物受阻：自身承受 1 点反震撞击伤害并剧烈震颤
		_shake_blocked(true)
		take_damage(1)
		return

	# 4. 执行平滑推移与动效
	_perform_slide_move(target_pos, cardinal)

func _shake_blocked(play_sound: bool = true) -> void:
	if play_sound:
		SoundManager.play_hit_brick(get_tree())
	if sprite:
		var tween = create_tween()
		var orig_scale = sprite.scale
		tween.tween_property(sprite, "scale", orig_scale * 1.12, 0.04)
		tween.tween_property(sprite, "scale", orig_scale, 0.04)

func _perform_slide_move(target_pos: Vector2, _dir: Vector2) -> void:
	is_moving = true
	var parent_node = get_parent() if get_parent() else self
	VFXAnimator.spawn_dust_puff(parent_node, global_position)
	VFXAnimator.spawn_wood_debris(parent_node, global_position)
	SoundManager.play_hit_brick(get_tree())

	# 播放 4 帧移动应力动画
	if move_frames.size() > 0:
		var frame_tween = create_tween()
		for i in range(move_frames.size()):
			frame_tween.tween_callback(func():
				if sprite and is_instance_valid(sprite):
					sprite.texture = move_frames[i]
			)
			frame_tween.tween_interval(0.035)

	var move_tween = create_tween()
	move_tween.tween_property(self, "global_position", target_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	move_tween.tween_callback(func():
		is_moving = false
		_update_visual_state()
		VFXAnimator.spawn_dust_puff(parent_node, global_position)
	)
