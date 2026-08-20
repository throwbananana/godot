class_name FortifiedWall
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

@export var max_health: int = 6
var current_health: int = 6

@onready var sprite: Sprite2D = $Sprite2D
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("steel")
	current_health = max_health
	explosion_scene = load("res://scenes/explosion.tscn")
	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/fortified_wall.png")
	if tex: sprite.texture = tex

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.4, 2.0, 0.6), 0.1)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func take_damage(amount: int) -> void:
	current_health -= amount
	SoundManager.play_hit_steel(get_tree())
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0), 0.06)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.06)
	if current_health <= 0:
		if explosion_scene:
			var exp_inst = explosion_scene.instantiate()
			exp_inst.global_position = global_position
			get_parent().add_child(exp_inst)
		queue_free()
