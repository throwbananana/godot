class_name Factory
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal factory_destroyed

@export var max_hp: int = 16 # tougher than the other map buildings -- it's meant to be an escort objective, not incidental cover

var current_hp: int = 16
var is_destroyed_flag: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("factory")
	current_hp = max_hp

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/factory.png")
	if tex and sprite:
		sprite.texture = tex

	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _process(_delta: float) -> void:
	if sprite:
		# Low-HP warning flicker so its "please protect me" stakes are readable at a glance
		if current_hp <= max_hp / 3:
			var flash = int(Time.get_ticks_msec() / 200) % 2 == 0
			sprite.modulate = Color(2.2, 0.6, 0.5, 1.0) if flash else Color(1.0, 1.0, 1.0, 1.0)
		else:
			sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

func take_damage(amount: int) -> void:
	if is_destroyed_flag:
		return
	current_hp -= amount
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var tw = create_tween()
	tw.tween_property(sprite, "position", Vector2(randf_range(-3, 3), randf_range(-3, 3)), 0.04)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.04)

	if current_hp <= 0:
		_destroy()

func take_hit(amount: int) -> void:
	take_damage(amount)

func _destroy() -> void:
	if is_destroyed_flag:
		return
	is_destroyed_flag = true
	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.35)
	factory_destroyed.emit()
	queue_free()
