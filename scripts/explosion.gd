class_name Explosion
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

@onready var sprite: Sprite2D = $Sprite2D

var textures: Array[Texture2D] = []
var current_frame: int = 0
var frame_timer: float = 0.0
var frame_duration: float = 0.055

func _ready() -> void:
	for i in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/effects/explosion_%d.png" % i)
		if tex:
			textures.append(tex)
	if textures.size() > 0:
		sprite.texture = textures[0]
	SoundManager.play_explosion(get_tree())

func _process(delta: float) -> void:
	frame_timer += delta
	if frame_timer >= frame_duration:
		frame_timer = 0.0
		current_frame += 1
		if current_frame < textures.size():
			sprite.texture = textures[current_frame]
		else:
			queue_free()
