class_name RollerWall
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_health: int = 4
var current_health: int = 4
var is_moving: bool = false
var push_step: float = 48.0

var sprite: Sprite2D
var collision_shape: CollisionShape2D
var frames: Array[Texture2D] = []
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("steel")
	add_to_group("roller_wall")

	explosion_scene = load("res://scenes/explosion.tscn")

	# Base sprite & animated wheel rotation frames
	var base_tex = TextureHelper.get_tex("res://assets/sprites/buildings/roller_wall.png")
	for i in range(4):
		var f_tex = TextureHelper.get_tex("res://assets/sprites/buildings/roller_wall_f%d.png" % i)
		if f_tex:
			frames.append(f_tex)

	sprite = Sprite2D.new()
	sprite.texture = base_tex if base_tex else (frames[0] if frames.size() > 0 else null)
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

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(0.4, 2.0, 0.6), 0.1)
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func take_damage(amount: int) -> void:
	current_health -= amount
	SoundManager.play_hit_steel(get_tree())
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(2.2, 2.2, 2.2), 0.06)
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.06)
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
		VFXAnimator.spawn_clay_debris(p_node, global_position)
	queue_free()

## Called when shot or hit with directional kinetic impact (e.g. from Bullet)
func take_hit_direction(amount: int, hit_dir: Vector2) -> void:
	if amount >= 99:
		destroy()
		return

	take_damage(amount)
	if current_health <= 0 or not is_inside_tree():
		return

	if hit_dir != Vector2.ZERO and not is_moving:
		_try_push(hit_dir)

func _try_push(hit_dir: Vector2) -> void:
	# 1. Snap to dominant cardinal direction
	var cardinal = Vector2.ZERO
	if absf(hit_dir.x) > absf(hit_dir.y):
		cardinal = Vector2.RIGHT if hit_dir.x > 0.0 else Vector2.LEFT
	else:
		cardinal = Vector2.DOWN if hit_dir.y > 0.0 else Vector2.UP

	var target_pos = global_position + cardinal * push_step

	# 2. Check map arena bounds
	var main = get_tree().current_scene if is_inside_tree() else null
	if main and "game_area" in main and main.game_area:
		var local_target = main.game_area.to_local(target_pos)
		var min_b = 24.0
		var max_b = 13.0 * 48.0 - 24.0
		if local_target.x < min_b - 6.0 or local_target.x > max_b + 6.0 or local_target.y < min_b - 6.0 or local_target.y > max_b + 6.0:
			_shake_blocked()
			return

	# 3. Physics shape query to test obstacles at target position
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

		# Ram & crush destructible bricks
		if collider.is_in_group("brick") or collider.is_in_group("hard_clay"):
			if collider.has_method("take_hit"):
				collider.take_hit(3)
			else:
				VFXAnimator.spawn_dust_puff(get_parent(), collider.global_position)
				collider.queue_free()
		# Ram & crush enemy tanks in the way
		elif collider.is_in_group("enemy") or collider.is_in_group("enemies"):
			if collider.has_method("take_damage"):
				collider.take_damage(2)
			# enemy.gd 没有 stun() 方法，真正的定身机制叫 freeze()/freeze_timer
			# (_physics_process 里 freeze_timer > 0 时整体提前 return)。has_method
			# 守卫让这行调用一直静默地什么都没做——wooden_wall.gd 里也是同一个坑。
			if collider.has_method("freeze"):
				collider.freeze(0.8)
			VFXAnimator.spawn_clay_debris(get_parent(), collider.global_position)
		# Solid impenetrable obstacles
		elif collider.is_in_group("steel") or collider.is_in_group("border") or collider.is_in_group("buildings") or collider.is_in_group("base"):
			blocked_by_solid = true

	if blocked_by_solid:
		_shake_blocked()
		return

	# 4. Perform smooth roll movement
	_perform_roll_move(target_pos, cardinal)

func _shake_blocked() -> void:
	SoundManager.play_hit_steel(get_tree())
	if sprite:
		var tween = create_tween()
		var orig_scale = sprite.scale
		tween.tween_property(sprite, "scale", orig_scale * 1.15, 0.05)
		tween.tween_property(sprite, "scale", orig_scale, 0.05)

func _perform_roll_move(target_pos: Vector2, _dir: Vector2) -> void:
	is_moving = true
	var parent_node = get_parent() if get_parent() else self
	VFXAnimator.spawn_dust_puff(parent_node, global_position)
	SoundManager.play_hit_steel(get_tree())

	# Animated frame cycle during rolling
	if frames.size() > 0:
		var frame_tween = create_tween()
		for i in range(frames.size()):
			frame_tween.tween_callback(func():
				if sprite and is_instance_valid(sprite):
					sprite.texture = frames[i]
			)
			frame_tween.tween_interval(0.04)

	var move_tween = create_tween()
	move_tween.tween_property(self, "global_position", target_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	move_tween.tween_callback(func():
		is_moving = false
		if sprite and is_instance_valid(sprite):
			var base_tex = TextureHelper.get_tex("res://assets/sprites/buildings/roller_wall.png")
			if base_tex:
				sprite.texture = base_tex
		VFXAnimator.spawn_dust_puff(parent_node, global_position)
	)
