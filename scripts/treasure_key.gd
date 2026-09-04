class_name TreasureKey
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@onready var sprite: Sprite2D = $Sprite2D

var lifetime: float = 60.0

func _ready() -> void:
	add_to_group("collectibles")
	add_to_group("treasure_key")
	var tex = TextureHelper.get_tex("res://assets/sprites/powerups/treasure_key.png")
	if tex:
		sprite.texture = tex
	body_entered.connect(_on_body_entered)

	# Pop-in bounce animation
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.3, 1.3), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.12)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	# Floating bob and gentle rotation
	sprite.rotation = sin(Time.get_ticks_msec() * 0.005) * 0.25
	var pulse = 0.1875 + sin(Time.get_ticks_msec() * 0.008) * 0.015
	sprite.scale = Vector2(pulse, pulse)

	if lifetime < 5.0:
		modulate.a = 0.4 if int(lifetime * 8.0) % 2 == 0 else 1.0
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2"):
		var main = get_tree().current_scene
		if main and main.has_method("obtain_treasure_key"):
			main.obtain_treasure_key()
		SoundManager.play_level_up(get_tree())
		VFXAnimator.spawn_reward_burst(get_parent(), global_position)
		queue_free()
