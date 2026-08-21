class_name OilBarrel
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var blast_radius: float = 76.0 # 3x3 surrounding grid area (1.5 tiles radius)
@export var blast_damage: int = 4

var is_exploded: bool = false
var sprite: Sprite2D
var collision_shape: CollisionShape2D
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("oil_barrel")
	add_to_group("destructible")
	add_to_group("obstacle")

	explosion_scene = load("res://scenes/explosion.tscn")

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/oil_barrel.png")
	sprite = Sprite2D.new()
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(0.1875, 0.1875)
	add_child(sprite)

	collision_shape = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(42.0, 42.0)
	collision_shape.shape = box
	add_child(collision_shape)

	# Initial spawn pop
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func take_damage(_amount: int) -> void:
	detonate()

func take_hit(_amount: int) -> void:
	detonate()

func detonate() -> void:
	if is_exploded:
		return
	is_exploded = true

	# Disable collision immediately
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if sprite:
		sprite.visible = false

	# 1. Spawn Core Fiery Explosion & VFX
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)

	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)

	# Screen Trauma
	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.55)

	# Light up Night Fog
	if main and "darkness_fog_instance" in main and main.darkness_fog_instance:
		var local_p = global_position - main.game_area.global_position
		main.darkness_fog_instance.add_flash(local_p, 220.0, 0.45)

	# 2. Blast 3x3 Surrounding Grid Objects (Tiles, Blocks, Barrels, Tanks)
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = blast_radius
	query.shape = circle_shape
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var results = space_state.intersect_shape(query, 32)
	for hit in results:
		var collider = hit.get("collider")
		if not collider or not is_instance_valid(collider) or collider == self:
			continue

		# A. Chain detonate adjacent oil barrels
		if collider is OilBarrel or collider.is_in_group("oil_barrel"):
			if collider.has_method("detonate"):
				collider.call_deferred("detonate")
		# B. Chain detonate timed bombs
		elif collider.is_in_group("timed_bomb") and collider.has_method("detonate"):
			collider.call_deferred("detonate")
		# C. Destroy destructible tiles (Brick walls, hard clay, sand dunes)
		elif collider.is_in_group("brick") or collider.is_in_group("hard_clay") or collider.is_in_group("sand_dune") or collider.is_in_group("trees"):
			if collider.has_method("take_hit"):
				collider.take_hit(blast_damage)
			elif collider.has_method("take_damage"):
				collider.take_damage(blast_damage)
			else:
				collider.queue_free()
		# D. Deal heavy blast damage to tanks
		elif collider is PlayerTank or collider is EnemyTank or collider.has_method("take_damage"):
			collider.take_damage(blast_damage)
			if collider.has_method("add_trauma"):
				collider.add_trauma(0.35)

	queue_free()
