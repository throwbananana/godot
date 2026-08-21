class_name JumpPad
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var launch_distance: float = 144.0
@export var launch_duration: float = 0.42

var jumping_bodies: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("jump_pad")
	add_to_group("terrain")
	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_jump_pad.png")
	if tex:
		sprite.texture = tex
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# Spring core pulse
	var pulse = 0.1875 + sin(Time.get_ticks_msec() * 0.01) * 0.01
	sprite.scale = Vector2(pulse, pulse)

	# Clean up jumping cooldowns
	var now = Time.get_ticks_msec() / 1000.0
	for b in jumping_bodies.keys():
		if now - jumping_bodies[b] > 0.8:
			jumping_bodies.erase(b)

func _on_body_entered(body: Node2D) -> void:
	if jumping_bodies.has(body):
		return
	if body is CharacterBody2D or body.is_in_group("player") or body.is_in_group("enemy"):
		_launch_body(body)

func _launch_body(body: Node2D) -> void:
	jumping_bodies[body] = Time.get_ticks_msec() / 1000.0
	
	var dir = Vector2.UP
	if "facing_direction" in body and body.facing_direction != Vector2.ZERO:
		dir = body.facing_direction
	elif "velocity" in body and body.velocity.length_squared() > 1.0:
		dir = body.velocity.normalized()

	var target_pos = body.global_position + dir * launch_distance
	target_pos.x = clampf(target_pos.x, 32.0, 13.0 * 48.0 - 32.0)
	target_pos.y = clampf(target_pos.y, 32.0, 13.0 * 48.0 - 32.0)

	# Sound & Launch Pad Compression Animation
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)

	var pad_tw = create_tween()
	pad_tw.tween_property(sprite, "scale", Vector2(0.12, 0.12), 0.08)
	pad_tw.tween_property(sprite, "scale", Vector2(0.22, 0.22), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pad_tw.tween_property(sprite, "scale", Vector2(0.1875, 0.1875), 0.10)

	# Unit Airborne Parabolic Trajectory
	var orig_z = body.z_index
	body.z_index = 40

	var tw_pos = create_tween()
	tw_pos.tween_property(body, "global_position", target_pos, launch_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var tw_scale = create_tween()
	tw_scale.tween_property(body, "scale", Vector2(1.55, 1.55), launch_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_scale.tween_property(body, "scale", Vector2(1.0, 1.0), launch_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_scale.tween_callback(func():
		if is_instance_valid(body):
			body.z_index = orig_z
			SoundManager.play_hit_brick(get_tree())
			VFXAnimator.spawn_shockwave(get_parent(), target_pos)
			var main = get_tree().current_scene
			if main and main.has_method("add_trauma"):
				main.add_trauma(0.15)
	)
