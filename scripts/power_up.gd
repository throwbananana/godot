class_name PowerUp
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

enum Type { STAR, BOMB, CLOCK, HELMET, SHOVEL, LIFE }

@export var power_up_type: Type = Type.STAR

@onready var sprite: Sprite2D = $Sprite2D

var lifetime: float = 20.0
var flash_timer: float = 0.0

func _ready() -> void:
	add_to_group("powerups")
	body_entered.connect(_on_body_entered)
	_update_texture()

func setup(type: Type) -> void:
	power_up_type = type
	_update_texture()

func _update_texture() -> void:
	if not sprite:
		return
	var tex_name = "star"
	match power_up_type:
		Type.STAR: tex_name = "star"
		Type.BOMB: tex_name = "bomb"
		Type.CLOCK: tex_name = "clock"
		Type.HELMET: tex_name = "helmet"
		Type.SHOVEL: tex_name = "shovel"
		Type.LIFE: tex_name = "life"
	
	var path = "res://assets/sprites/powerups/%s.png" % tex_name
	var tex = TextureHelper.get_tex(path)
	if not tex:
		tex = TextureHelper.get_tex("res://assets/sprites/powerups/%s.svg" % tex_name)
	if tex:
		sprite.texture = tex

func _process(delta: float) -> void:
	lifetime -= delta
	flash_timer += delta * 6.0
	
	# 上下浮动
	position.y += sin(flash_timer) * 0.4
	
	# 快消失时闪烁
	if lifetime < 5.0:
		modulate.a = 0.3 if int(lifetime * 6.0) % 2 == 0 else 1.0
	
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.has_method("apply_powerup"):
			body.apply_powerup(power_up_type)
		SoundManager.play_pickup(get_tree())
		queue_free()
