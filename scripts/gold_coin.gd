class_name GoldCoin
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

@export var value: int = 25
@onready var sprite: Sprite2D = $Sprite2D

var lifetime: float = 25.0
var magnet_range: float = 120.0
var move_speed: float = 0.0

func _ready() -> void:
	add_to_group("collectibles")
	var tex = TextureHelper.get_tex("res://assets/sprites/powerups/gold_coin.png")
	if tex: sprite.texture = tex
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	sprite.rotation += delta * 4.0
	
	# 磁吸追踪玩家
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		if is_instance_valid(p):
			var dist = global_position.distance_to(p.global_position)
			if dist < magnet_range:
				move_speed = move_toward(move_speed, 420.0, 1200.0 * delta)
				var dir = (p.global_position - global_position).normalized()
				position += dir * move_speed * delta

	if lifetime < 4.0:
		modulate.a = 0.4 if int(lifetime * 8.0) % 2 == 0 else 1.0
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var main = get_tree().current_scene
		if main and main.has_method("add_gold"):
			main.add_gold(value)
		SoundManager.play_hit_steel(get_tree())
		queue_free()
