class_name MovingPlatform
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var patrol_axis: Vector2 = Vector2.RIGHT # Vector2.RIGHT or Vector2.DOWN
@export var patrol_distance: float = 144.0 # Distance in pixels (e.g. 3 tiles * 48px)
@export var move_speed: float = 48.0 # Pixels per second
@export var wait_time_at_ends: float = 0.8 # Pause at turnaround points

var origin_pos: Vector2
var current_dir: float = 1.0 # 1.0 = forward, -1.0 = reverse
var current_dist: float = 0.0
var wait_timer: float = 0.0
var is_waiting: bool = false

var passengers: Array[Node2D] = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var passenger_area: Area2D = $PassengerArea

func _ready() -> void:
	origin_pos = position
	patrol_axis = patrol_axis.normalized()

	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_platform.png")
	if tex and sprite:
		sprite.texture = tex
		sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)

	if passenger_area:
		passenger_area.body_entered.connect(_on_body_entered)
		passenger_area.body_exited.connect(_on_body_exited)

func _physics_process(delta: float) -> void:
	if is_waiting:
		wait_timer -= delta
		if wait_timer <= 0.0:
			is_waiting = false
			current_dir *= -1.0
		return

	# Calculate movement step
	var step_amount = move_speed * delta
	current_dist += step_amount
	var next_pos: Vector2

	if current_dist >= patrol_distance:
		var overshoot = current_dist - patrol_distance
		current_dist = patrol_distance
		next_pos = origin_pos + patrol_axis * (patrol_distance if current_dir > 0 else 0.0)
		is_waiting = true
		wait_timer = wait_time_at_ends
		current_dist = 0.0
	else:
		if current_dir > 0:
			next_pos = origin_pos + patrol_axis * current_dist
		else:
			next_pos = origin_pos + patrol_axis * (patrol_distance - current_dist)

	var move_delta = next_pos - position
	position = next_pos

	# Carry all passengers on board
	var valid_passengers: Array[Node2D] = []
	for p in passengers:
		if is_instance_valid(p) and p is Node2D:
			valid_passengers.append(p)
			p.global_position += move_delta
	passengers = valid_passengers

	# Amber beacon pulse animation
	if sprite:
		var pulse = 0.90 + sin(Time.get_ticks_msec() * 0.008) * 0.12
		sprite.modulate = Color(1.0 + pulse * 0.15, 1.0 + pulse * 0.10, 1.0)

func _on_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if (body.is_in_group("player") or body.is_in_group("enemies") or body.is_in_group("player_carriage")):
		if not passengers.has(body):
			passengers.append(body)
		if "is_on_platform" in body:
			body.is_on_platform = true
		_set_water_exception(body, true)

func _on_body_exited(body: Node2D) -> void:
	if passengers.has(body):
		passengers.erase(body)
	if "is_on_platform" in body:
		body.is_on_platform = false
	_set_water_exception(body, false)

# Water tiles carry a permanently-blocking StaticBody2D (main.gd::_spawn_tile) --
# the same thing Amphibious Hull bypasses with add_collision_exception_with().
# _physics_process above carries riders by directly incrementing global_position,
# not move_and_slide, so nothing stops the *carry* itself -- but the rider's own
# move_and_slide() call next physics frame depenetrates it out of any solid body
# it's now overlapping, ejecting it straight back off the platform mid-crossing.
# Grant the same exception, scoped to however long the body is actually riding.
func _set_water_exception(body: Node2D, add: bool) -> void:
	if not (body is PhysicsBody2D):
		return
	# Amphibious Hull's exception is permanent (player.gd::_apply_rpg_stats) --
	# don't strip it back off just because this ride happened to end.
	if not add and "amphibious_hull_applied" in body and body.amphibious_hull_applied:
		return
	var main = get_tree().current_scene
	if not (main and "water_bodies" in main):
		return
	for water_body in main.water_bodies:
		if is_instance_valid(water_body):
			if add:
				body.add_collision_exception_with(water_body)
			else:
				body.remove_collision_exception_with(water_body)
