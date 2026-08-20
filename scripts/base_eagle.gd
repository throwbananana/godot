class_name BaseEagle
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

signal destroyed

@onready var sprite: Sprite2D = $Sprite2D
var is_destroyed: bool = false

var tex_alive: Texture2D
var tex_destroyed: Texture2D
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("base_eagle")
	tex_alive = TextureHelper.get_tex("res://assets/sprites/tiles/base_eagle.png")
	tex_destroyed = TextureHelper.get_tex("res://assets/sprites/tiles/base_destroyed.png")
	explosion_scene = load("res://scenes/explosion.tscn")
	if tex_alive:
		sprite.texture = tex_alive

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if tex_destroyed:
		sprite.texture = tex_destroyed
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)
	SoundManager.play_game_over(get_tree())
	destroyed.emit()
