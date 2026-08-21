class_name WindBlower
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

enum Direction { UP = 0, RIGHT = 1, DOWN = 2, LEFT = 3 }

@export var blow_direction: Direction = Direction.UP
@export var wind_strength: float = 220.0
@export var wind_range: float = 200.0
@export var max_hp: int = 6

var current_hp: int = 6
var blow_vec: Vector2 = Vector2.UP
var particle_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var wind_area: Area2D = $WindArea
@onready var wind_shape: CollisionShape2D = $WindArea/CollisionShape2D

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("wind_blower")
	current_hp = max_hp

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/wind_blower.png")
	if tex:
		sprite.texture = tex

	_update_direction()

func set_direction(dir: Direction) -> void:
	blow_direction = dir
	_update_direction()

func _update_direction() -> void:
	match blow_direction:
		Direction.UP:
			blow_vec = Vector2.UP
			sprite.rotation = -PI / 2.0
		Direction.RIGHT:
			blow_vec = Vector2.RIGHT
			sprite.rotation = 0.0
		Direction.DOWN:
			blow_vec = Vector2.DOWN
			sprite.rotation = PI / 2.0
		Direction.LEFT:
			blow_vec = Vector2.LEFT
			sprite.rotation = PI

	# Position and size the wind area ahead of the blower
	if wind_area and wind_shape and wind_shape.shape is RectangleShape2D:
		var rect = wind_shape.shape as RectangleShape2D
		rect.size = Vector2(wind_range, 44.0)
		wind_area.rotation = blow_vec.angle()
		wind_area.position = blow_vec * (wind_range / 2.0 + 20.0)

func _physics_process(delta: float) -> void:
	# Turbine impeller vibration
	var vibe = sin(Time.get_ticks_msec() * 0.04) * 0.02
	sprite.scale = Vector2(0.1875 + vibe, 0.1875 - vibe)

	# Wind trail particle stream
	particle_timer += delta
	if particle_timer >= 0.10:
		particle_timer = 0.0
		var r_dist = randf_range(24.0, wind_range)
		var perp = blow_vec.orthogonal() * randf_range(-16.0, 16.0)
		var p_pos = global_position + blow_vec * r_dist + perp
		if is_inside_tree() and get_parent():
			VFXAnimator.spawn_dust_puff(get_parent(), p_pos)

	# Apply wind force to overlapping tanks and units
	if is_instance_valid(wind_area):
		for body in wind_area.get_overlapping_bodies():
			if body == self:
				continue
			if body is CharacterBody2D or body.is_in_group("player") or body.is_in_group("enemy") or body.is_in_group("train_carriage"):
				body.global_position += blow_vec * (wind_strength * delta)

		for area in wind_area.get_overlapping_areas():
			if area.is_in_group("bullet"):
				# Deflect bullet trajectory
				area.global_position += blow_vec * (wind_strength * 0.45 * delta)

func take_damage(dmg: int) -> void:
	current_hp -= dmg
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color(3.0, 0.5, 0.5), 0.08)
	tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.12)

	if current_hp <= 0:
		SoundManager.play_explosion(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		queue_free()

func heal(amt: int) -> void:
	current_hp = mini(current_hp + amt, max_hp)
