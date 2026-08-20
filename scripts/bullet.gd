class_name Bullet
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")

signal hit_target(target: Node2D)

@export var speed: float = 480.0
@export var damage: int = 1
@export var can_destroy_steel: bool = false

var direction: Vector2 = Vector2.UP
var shooter: Node2D = null
var shooter_type: String = "player"

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	rotation = direction.angle() + PI / 2.0
	
	var tex_path = "res://assets/sprites/effects/bullet_plasma.png" if can_destroy_steel else "res://assets/sprites/effects/bullet.png"
	var tex = TextureHelper.get_tex(tex_path)
	if not tex and can_destroy_steel:
		tex = TextureHelper.get_tex("res://assets/sprites/effects/bullet.png")
	if tex and sprite:
		sprite.texture = tex

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == shooter:
		return

	if shooter_type == "player" and (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")):
		return

	if shooter_type == "enemy" and body.is_in_group("enemy"):
		return

	if body.is_in_group("brick"):
		body.queue_free()
		queue_free()
		return
	elif body.is_in_group("steel"):
		if can_destroy_steel:
			body.queue_free()
		queue_free()
		return
	elif body.is_in_group("border"):
		queue_free()
		return
	elif body.is_in_group("building"):
		if shooter_type == "enemy":
			if body.has_method("take_damage"):
				body.take_damage(damage)
			queue_free()
		return
	elif body.is_in_group("enemy") and shooter_type == "player":
		if body.has_method("take_damage"):
			var pts = 100
			if body.has_method("get_points"):
				pts = body.get_points()
			body.take_damage(damage)
		queue_free()
		return
	elif (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")) and shooter_type == "enemy":
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
		return

func _on_area_entered(area: Area2D) -> void:
	if area == shooter:
		return
	if area.is_in_group("bullet"):
		if area.shooter_type != shooter_type:
			area.queue_free()
			queue_free()
		return
	if area.is_in_group("base"):
		if area.has_method("destroy"):
			area.destroy()
		queue_free()
		return
	if area.is_in_group("building") and shooter_type == "enemy":
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()
		return
