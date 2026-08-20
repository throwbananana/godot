class_name SpawnStar
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")

signal finished

@onready var sprite: Sprite2D = $Sprite2D

var duration: float = 0.85
var timer: float = 0.0

func _ready() -> void:
	var tex = TextureHelper.get_tex("res://assets/sprites/effects/spawn_star.png")
	if not tex:
		tex = TextureHelper.get_tex("res://assets/sprites/effects/spawn_star.svg")
	if tex:
		sprite.texture = tex
	scale = Vector2.ZERO

func _process(delta: float) -> void:
	timer += delta
	var progress = timer / duration
	
	# 旋转与闪烁缩放动画
	sprite.rotation += delta * 12.0
	var scale_pulse = (sin(timer * 24.0) * 0.25 + 0.75) * clampf(progress * 2.0, 0.2, 1.0)
	scale = Vector2(scale_pulse * 0.45, scale_pulse * 0.45)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.7 + sin(timer * 20.0) * 0.3)
	
	if timer >= duration:
		finished.emit()
		queue_free()
