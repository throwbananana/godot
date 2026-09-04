class_name DarknessDevice
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_hp: int = 5
@export var light_radius: float = 105.0
@export var is_active: bool = true

var current_hp: int = 5
var sprite: Sprite2D
var collision_shape: CollisionShape2D

var tex_unlit: Texture2D
var tex_lit: Texture2D

func _ready() -> void:
	add_to_group("darkness_device")
	add_to_group("building")
	add_to_group("destructible")
	add_to_group("buildings")

	current_hp = max_hp
	tex_unlit = TextureHelper.get_tex("res://assets/sprites/buildings/darkness_device.png")
	tex_lit = TextureHelper.get_tex("res://assets/sprites/buildings/darkness_device_lit.png")

	# Base sprite
	sprite = Sprite2D.new()
	sprite.texture = tex_lit if is_active else tex_unlit
	sprite.scale = Vector2(0.1875, 0.1875)
	add_child(sprite)

	# Collision Shape (36x36 box centered on 48px tile)
	collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(36.0, 36.0)
	collision_shape.shape = shape
	add_child(collision_shape)

	# Initial spawn scale pop
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

	# Blanket the battlefield in darkness
	if is_active:
		var main = get_tree().current_scene
		if main and main.has_method("activate_darkness_fog"):
			main.activate_darkness_fog()

func _process(_delta: float) -> void:
	if not is_active or not sprite:
		return

	# Eerie pulsating violet core aura
	var pulse = sin(Time.get_ticks_msec() * 0.006) * 0.08
	sprite.modulate = Color(1.0 + pulse * 0.4, 0.94 + pulse * 0.2, 1.15 + pulse, 1.0)

func take_damage(amount: int) -> void:
	current_hp -= amount
	SoundManager.play_hit_steel(get_tree())
	if get_parent():
		VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	# Hurt shake
	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "position", Vector2(randf_range(-3, 3), randf_range(-3, 3)), 0.04)
		tw.tween_property(sprite, "position", Vector2.ZERO, 0.04)

	if current_hp <= 0:
		_destroy()

func take_hit(amount: int) -> void:
	take_damage(amount)

func _destroy() -> void:
	if not is_active and is_queued_for_deletion():
		return
	is_active = false
	remove_from_group("darkness_device")

	SoundManager.play_explosion(get_tree())
	if get_parent():
		VFXAnimator.spawn_dust_puff(get_parent(), global_position)
		VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	# Restore battlefield lighting if no more darkness devices remain
	var main = get_tree().current_scene
	if main and main.has_method("deactivate_darkness_fog"):
		main.deactivate_darkness_fog()

	queue_free()
