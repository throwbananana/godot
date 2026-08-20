class_name SpawnStar
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")

signal finished

@onready var sprite: Sprite2D = $Sprite2D

var frames: Array[Texture2D] = []
var duration: float = 0.85
var timer: float = 0.0

func _ready() -> void:
	for i in range(4):
		var tex = TextureHelper.get_tex("res://assets/sprites/effects/spawn_star_%d.png" % i)
		if tex:
			frames.append(tex)
	if frames.size() > 0:
		sprite.texture = frames[0]
	scale = Vector2.ZERO

func _process(delta: float) -> void:
	timer += delta
	var progress = timer / duration
	
	# 4帧动画切换
	if frames.size() > 0:
		var frame_idx = int(timer * 16.0) % frames.size()
		sprite.texture = frames[frame_idx]

	sprite.rotation += delta * 8.0
	var scale_pulse = (sin(timer * 22.0) * 0.25 + 0.8) * clampf(progress * 2.2, 0.2, 1.0)
	scale = Vector2(scale_pulse * 0.45, scale_pulse * 0.45)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.75 + sin(timer * 20.0) * 0.25)
	
	if timer >= duration:
		finished.emit()
		queue_free()
