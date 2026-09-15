class_name LandmineHazard
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

var is_detonated: bool = false
var explosion_scene: PackedScene
var explosion_radius: float = 64.0
var damage: int = 3

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("landmines")
	add_to_group("hazards")
	explosion_scene = load("res://scenes/explosion.tscn")
	body_entered.connect(_on_body_entered)

	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_landmine.png")
	if tex and sprite:
		sprite.texture = tex
		sprite.scale = Vector2(0.13, 0.13)

func _process(_delta: float) -> void:
	if sprite and not is_detonated:
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.08
		sprite.scale = Vector2(0.13 * pulse, 0.13 * pulse)

func _on_body_entered(body: Node2D) -> void:
	if is_detonated:
		return
	if body.is_in_group("player") or body.is_in_group("enemy") or body.is_in_group("p1") or body.is_in_group("p2"):
		detonate(body)

func detonate(trigger_body: Node2D = null) -> void:
	if is_detonated:
		return
	is_detonated = true

	var parent = get_parent()
	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.40)

	SoundManager.play_explosion(get_tree())

	if explosion_scene and parent:
		var exp_inst = explosion_scene.instantiate()
		parent.add_child(exp_inst)
		exp_inst.global_position = global_position

	VFXAnimator.spawn_shockwave(parent, global_position)
	VFXAnimator.spawn_clay_debris(parent, global_position)

	if trigger_body and is_instance_valid(trigger_body) and trigger_body.has_method("take_damage"):
		trigger_body.take_damage(damage)

	# Explode surrounding area in direct space state
	var space_state = get_world_2d().direct_space_state
	if space_state:
		var shape = CircleShape2D.new()
		shape.radius = explosion_radius
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, global_position)
		query.collision_mask = 1 | 2 | 16
		query.collide_with_bodies = true
		query.collide_with_areas = true

		var results = space_state.intersect_shape(query, 16)
		for res in results:
			var collider = res.get("collider")
			if not collider or not is_instance_valid(collider) or collider == self:
				continue

			if collider.is_in_group("brick"):
				VFXAnimator.spawn_dust_puff(parent, collider.global_position)
				collider.queue_free()
			elif collider.is_in_group("steel") and not collider.is_in_group("border"):
				VFXAnimator.spawn_shockwave(parent, collider.global_position)
				collider.queue_free()
			elif collider.is_in_group("landmines") and collider != self:
				if collider.has_method("detonate"):
					collider.call_deferred("detonate", null)
			elif collider != trigger_body and collider.has_method("take_damage"):
				collider.take_damage(damage)

	queue_free()
