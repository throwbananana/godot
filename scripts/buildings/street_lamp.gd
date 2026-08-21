class_name StreetLamp
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_hp: int = 3
@export var light_radius: float = 165.0
@export var is_lit: bool = true

var current_hp: int = 3
var sprite: Sprite2D
var glow_sprite: Sprite2D
var collision_shape: CollisionShape2D

var tex_lamp: Texture2D
var tex_lamp_lit: Texture2D

func _ready() -> void:
	add_to_group("street_lamp")
	add_to_group("building")
	add_to_group("destructible")

	current_hp = max_hp
	tex_lamp = TextureHelper.get_tex("res://assets/sprites/buildings/street_lamp.png")
	tex_lamp_lit = TextureHelper.get_tex("res://assets/sprites/buildings/street_lamp_lit.png")

	# Base sprite
	sprite = Sprite2D.new()
	sprite.texture = tex_lamp_lit if is_lit else tex_lamp
	sprite.scale = Vector2(0.1875, 0.1875)
	add_child(sprite)

	# Collision Shape
	collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 16.0
	collision_shape.shape = shape
	add_child(collision_shape)

	# Initial spawn scale pop
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _process(delta: float) -> void:
	if not is_lit:
		return

	# Soft warm breathing lantern glow pulse
	var pulse = sin(Time.get_ticks_msec() * 0.005) * 0.04
	sprite.modulate = Color(1.0 + pulse, 1.0 + pulse * 0.8, 0.95, 1.0)

func take_damage(amount: int) -> void:
	current_hp -= amount
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	
	# Hurt shake
	var tw = create_tween()
	tw.tween_property(sprite, "position", Vector2(randf_range(-3, 3), randf_range(-3, 3)), 0.04)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.04)

	if current_hp <= 0:
		_destroy()

func take_hit(amount: int) -> void:
	take_damage(amount)

func _destroy() -> void:
	is_lit = false
	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	queue_free()
