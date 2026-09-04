class_name LaserPiercer
extends RefCounted

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

static func fire_linear_laser(parent: Node2D, start_pos: Vector2, direction: Vector2, shooter: Node2D, shooter_type: String, beam_damage: int = 2) -> void:
	if not parent or not is_instance_valid(parent):
		return

	var space_state = parent.get_world_2d().direct_space_state
	if not space_state:
		return

	SoundManager.play_laser(parent.get_tree())

	var main = parent.get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.25)

	# Raycast to find the border or maximum range
	var max_dist = 700.0
	var ray_end = start_pos + direction * max_dist

	# Query bodies along the laser trajectory with shape ray
	var shape = RectangleShape2D.new()
	# Perpendicular thickness of laser beam
	var perp = Vector2(-direction.y, direction.x)
	shape.size = Vector2(16.0, 16.0)

	var step_dist = 18.0
	var current_dist = 0.0
	var final_end = ray_end

	var hit_bodies: Array[Node2D] = []

	while current_dist <= max_dist:
		var check_pos = start_pos + direction * current_dist
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, check_pos)
		query.collision_mask = 1 | 2 | 16 # Terrain, players, enemies, eagle, buildings
		query.collide_with_bodies = true
		query.collide_with_areas = true

		var results = space_state.intersect_shape(query, 8)
		var stop_beam = false

		for res in results:
			var collider = res.get("collider")
			if not collider or not is_instance_valid(collider) or collider == shooter or hit_bodies.has(collider):
				continue

			if collider.is_in_group("border"):
				final_end = check_pos
				stop_beam = true
				break

			hit_bodies.append(collider)

			# Destroy destructible terrain along the beam
			if collider.is_in_group("brick"):
				VFXAnimator.spawn_dust_puff(parent, collider.global_position)
				collider.queue_free()
			elif collider.is_in_group("steel") and not collider.is_in_group("border"):
				VFXAnimator.spawn_shockwave(parent, collider.global_position)
				collider.queue_free()
			elif collider.is_in_group("oil_barrel") or collider.is_in_group("street_lamp"):
				# 同 bullet.gd 的口径: 这两样是路上道具, 不是免友伤的防御建筑,
				# 不分 shooter_type 一律命中。此前两个组都没在这条判定链里,
				# 穿透激光对油桶/路灯零效果。
				if collider.has_method("take_hit"):
					collider.take_hit(beam_damage)
				elif collider.has_method("take_damage"):
					collider.take_damage(beam_damage)
				VFXAnimator.spawn_shockwave(parent, collider.global_position)
			elif (collider.is_in_group("enemy") or collider.is_in_group("enemies")) and shooter_type == "player":
				# enemy.gd 的坦克只 add_to_group("enemy"), 但 train_carriage.gd
				# 的敌方车厢只加了 "enemies"(见 CLAUDE.md 分组单复数漂移一节)。
				# bullet.gd 两个都查, 这里原来只查单数, 结果是穿透激光打不中
				# 敌方列车车厢。
				if collider.has_method("take_damage"):
					collider.take_damage(beam_damage)
				VFXAnimator.spawn_shockwave(parent, collider.global_position)
			elif (collider.is_in_group("player") or collider.is_in_group("p1") or collider.is_in_group("p2")) and shooter_type == "enemy":
				if collider.has_method("try_parry_laser") and collider.try_parry_laser(start_pos, direction, beam_damage):
					final_end = collider.global_position
					stop_beam = true
					break
				if collider.has_method("take_damage"):
					collider.take_damage(beam_damage)
				VFXAnimator.spawn_clay_debris(parent, collider.global_position)
			elif (collider.is_in_group("base") or collider.is_in_group("base_eagle")) and shooter_type == "enemy":
				if collider.has_method("destroy"):
					collider.destroy()
				elif collider.has_method("take_damage_hit"):
					collider.take_damage_hit()
			elif (collider.is_in_group("building") or collider.is_in_group("buildings")) and shooter_type == "enemy":
				# defense_turret/fortified_wall/landmine/repair_station 只挂了
				# "buildings"(复数); factory/shield_station/signal_jammer_tower/
				# wind_blower 两个都挂。原来这里只查单数 "building", 于是激光
				# 打炮塔/强化墙完全无效, 跟 bullet.gd:183 的口径不一致。
				if collider.has_method("take_damage"):
					collider.take_damage(beam_damage)

		if stop_beam:
			break
		current_dist += step_dist

	# Create vibrant visual laser beam
	_spawn_laser_visual(parent, start_pos, final_end, direction)

static func _spawn_laser_visual(parent: Node2D, start_pos: Vector2, end_pos: Vector2, direction: Vector2) -> void:
	var beam_len = start_pos.distance_to(end_pos)
	var mid_pos = (start_pos + end_pos) / 2.0

	var beam_spr = Sprite2D.new()
	var tex = TextureHelper.get_tex("res://assets/sprites/effects/laser_beam.png")
	if tex:
		beam_spr.texture = tex
	beam_spr.rotation = direction.angle() + PI / 2.0
	beam_spr.scale = Vector2(0.24, beam_len / 256.0)
	beam_spr.z_index = 25
	parent.add_child(beam_spr)
	# 必须 add_child 之后再设 global_position。
	#
	# 这里原本是在 add_child 之前设 beam_spr.position = mid_pos —— 而 position 是
	# *局部*坐标, mid_pos 却是全局的。parent 是 ActorsContainer, 它挂在 GameArea
	# 下面, 而 GameArea 在 main.tscn 里 position = Vector2(48, 48), 于是整条光束
	# 被平移了一整格。伤害判定用的是全局坐标的射线, 一直是对的, 所以现象是
	# "打中的和画出来的不是一条线": 枪口闪光和冲击波 (都走 VFXAnimator, 用的是
	# global_position) 在正确位置, 唯独光束差一格。
	# vfx_animator.gd 里三处生成节点全部用 global_position, 本文件是唯一的例外。
	beam_spr.global_position = mid_pos

	var tween = parent.create_tween()
	tween.tween_property(beam_spr, "scale:x", 0.42, 0.04)
	tween.tween_property(beam_spr, "scale:x", 0.02, 0.18)
	tween.parallel().tween_property(beam_spr, "modulate:a", 0.0, 0.22)
	tween.tween_callback(beam_spr.queue_free)
