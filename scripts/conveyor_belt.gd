class_name ConveyorBelt
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")

enum Direction { UP = 0, RIGHT = 1, DOWN = 2, LEFT = 3 }

@export var direction: Direction = Direction.UP
@export var speed: float = 160.0

var move_vec: Vector2 = Vector2.UP

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("conveyor")
	add_to_group("terrain")
	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_conveyor.png")
	if tex:
		sprite.texture = tex
	_update_direction()

func set_direction(dir: Direction) -> void:
	direction = dir
	_update_direction()

func _update_direction() -> void:
	match direction:
		Direction.UP:
			move_vec = Vector2.UP
			sprite.rotation = 0.0
		Direction.RIGHT:
			move_vec = Vector2.RIGHT
			sprite.rotation = PI / 2.0
		Direction.DOWN:
			move_vec = Vector2.DOWN
			sprite.rotation = PI
		Direction.LEFT:
			move_vec = Vector2.LEFT
			sprite.rotation = -PI / 2.0

func _physics_process(delta: float) -> void:
	# Subtle arrow chevron pulse
	var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.04
	sprite.scale = Vector2(0.1875 * pulse, 0.1875)

	# Transport all overlapping units & bullets
	for body in get_overlapping_bodies():
		if body is CharacterBody2D or body.is_in_group("player") or body.is_in_group("enemy") or body.is_in_group("train_carriage"):
			body.global_position += move_vec * (speed * delta)

	for area in get_overlapping_areas():
		if area.is_in_group("bullet"):
			area.global_position += move_vec * (speed * 0.6 * delta)
