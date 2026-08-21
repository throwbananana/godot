class_name Bullet
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal hit_target(target: Node2D)

@export var speed: float = 480.0
@export var damage: int = 1
@export var can_destroy_steel: bool = false
@export var is_homing: bool = false
@export var homing_turn_speed: float = 3.8

var direction: Vector2 = Vector2.UP
var shooter: Node2D = null
var shooter_type: String = "player"
var target: Node2D = null
var trail_timer: float = 0.0
var custom_texture_path: String = ""

var is_destroyed: bool = false
var destroyed_bodies: Array[Node2D] = []

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	rotation = direction.angle() + PI / 2.0
	
	var tex_path = "res://assets/sprites/effects/bullet_plasma.png" if can_destroy_steel else "res://assets/sprites/effects/bullet.png"
	if is_homing:
		tex_path = "res://assets/sprites/effects/bullet_missile.png"
	if custom_texture_path != "":
		tex_path = custom_texture_path

	var tex = TextureHelper.get_tex(tex_path)
	if not tex and can_destroy_steel:
		tex = TextureHelper.get_tex("res://assets/sprites/effects/bullet.png")
	if tex and sprite:
		sprite.texture = tex
		if is_homing:
			sprite.scale = Vector2(0.22, 0.22)

func _physics_process(delta: float) -> void:
	if is_homing and target and is_instance_valid(target):
		var desired = (target.global_position - global_position).normalized()
		direction = direction.slerp(desired, homing_turn_speed * delta).normalized()
		rotation = direction.angle() + PI / 2.0
		trail_timer += delta
		if trail_timer >= 0.08:
			trail_timer = 0.0
			VFXAnimator.spawn_dust_puff(get_parent(), global_position - direction * 12.0)

	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == shooter:
		return

	if shooter_type == "player" and (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")):
		return

	if shooter_type == "enemy" and body.is_in_group("enemy"):
		return

	if body.is_in_group("brick"):
		if not destroyed_bodies.has(body):
			destroyed_bodies.append(body)
			VFXAnimator.spawn_dust_puff(get_parent(), body.global_position)
			body.queue_free()
		if not is_destroyed:
			is_destroyed = true
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_brick(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif body.is_in_group("steel"):
		if not is_destroyed:
			is_destroyed = true
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		if can_destroy_steel and not body.is_in_group("border"):
			if not destroyed_bodies.has(body):
				destroyed_bodies.append(body)
				VFXAnimator.spawn_shockwave(get_parent(), body.global_position)
				body.queue_free()
		return
	elif body.is_in_group("border"):
		if not is_destroyed:
			is_destroyed = true
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif body.is_in_group("building"):
		if shooter_type == "enemy":
			if not is_destroyed:
				is_destroyed = true
				if body.has_method("take_damage"):
					body.take_damage(damage)
				VFXAnimator.spawn_clay_debris(get_parent(), global_position)
				queue_free()
		return
	elif body.is_in_group("enemy") and shooter_type == "player":
		if not is_destroyed:
			is_destroyed = true
			if body.has_method("take_damage"):
				body.take_damage(damage)
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")) and shooter_type == "enemy":
		if not is_destroyed:
			is_destroyed = true
			if body.has_method("take_damage"):
				body.take_damage(damage)
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return

func _on_area_entered(area: Area2D) -> void:
	if area == shooter or is_destroyed:
		return
	if area.is_in_group("bullet"):
		if area.shooter_type != shooter_type:
			is_destroyed = true
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			area.queue_free()
			queue_free()
		return
	if area.is_in_group("base") or area.is_in_group("base_eagle"):
		is_destroyed = true
		if area.has_method("destroy"):
			area.destroy()
		elif area.has_method("take_damage_hit"):
			area.take_damage_hit()
		queue_free()
		return
	if area.is_in_group("building") and shooter_type == "enemy":
		is_destroyed = true
		if area.has_method("take_damage"):
			area.take_damage(damage)
		VFXAnimator.spawn_clay_debris(get_parent(), global_position)
		queue_free()
		return
