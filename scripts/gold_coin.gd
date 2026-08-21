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
	
	# 磁吸追踪玩家 (结合 magnetic_salvage 战术芯片)
	var main = get_tree().current_scene
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and p is Node2D:
			var effective_range = magnet_range
			if main and main.rpg_mgr and ("player_id" in p) and main.rpg_mgr.has_perk("magnetic_salvage", p.player_id):
				effective_range = 380.0
			var dist = global_position.distance_to(p.global_position)
			if dist < effective_range:
				move_speed = move_toward(move_speed, 540.0, 1600.0 * delta)
				var dir = (p.global_position - global_position).normalized()
				position += dir * move_speed * delta
				break

	if lifetime < 4.0:
		modulate.a = 0.4 if int(lifetime * 8.0) % 2 == 0 else 1.0
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var main = get_tree().current_scene
		var final_val = value
		if main and main.rpg_mgr and ("player_id" in body) and main.rpg_mgr.has_perk("magnetic_salvage", body.player_id):
			final_val = int(float(value) * 1.35)
		if main and main.has_method("add_gold"):
			main.add_gold(final_val)
		SoundManager.play_pickup(get_tree())
		queue_free()
