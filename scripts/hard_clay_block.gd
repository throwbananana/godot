class_name HardClayBlock
extends StaticBody2D

const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

@export var max_health: int = 3
var current_health: int = 3
var sprite: Sprite2D = null

# Visual color tint per durability level:
# 3 HP: Pristine Hardened Terracotta (White/Original 1.0)
# 2 HP: Stressed/Chipped Ochre Clay (0.85, 0.68, 0.48)
# 1 HP: Heavily Fractured Dark Burnt Terracotta (0.58, 0.36, 0.25)
const DAMAGE_STAGE_COLORS: Array[Color] = [
	Color(0.55, 0.32, 0.22), # 0 HP fallback
	Color(0.58, 0.36, 0.25), # 1 HP
	Color(0.85, 0.68, 0.48), # 2 HP
	Color(1.0, 1.0, 1.0)     # 3 HP
]

func _ready() -> void:
	current_health = max_health
	add_to_group("brick")
	add_to_group("hard_clay")

func take_hit(damage: int = 1) -> void:
	current_health -= damage
	if current_health <= 0:
		var main = get_tree().current_scene if is_inside_tree() else null
		if main:
			if main.has_method("check_key_drop"):
				main.check_key_drop(self, global_position)
			if main.has_method("try_spawn_block_loot"):
				main.try_spawn_block_loot(global_position)
		if is_inside_tree() and get_parent():
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			VFXAnimator.spawn_dust_puff(get_parent(), global_position)
			if get_tree():
				SoundManager.play_hit_brick(get_tree())
		queue_free()
	else:
		if is_inside_tree() and get_parent():
			VFXAnimator.spawn_dust_puff(get_parent(), global_position)
			if get_tree():
				SoundManager.play_hit_steel(get_tree())
		_play_damage_feedback()

func _play_damage_feedback() -> void:
	if not sprite or not is_inside_tree():
		return

	var target_col = DAMAGE_STAGE_COLORS[clampi(current_health, 0, 3)]
	
	# Color flash and settle into damaged shade
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.6, 1.4, 1.1), 0.04)
	tween.tween_property(sprite, "modulate", target_col, 0.14)

	# Physical shock jiggle
	var orig_pos = sprite.position
	var jiggle = Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
	var shake_tween = create_tween()
	shake_tween.tween_property(sprite, "position", orig_pos + jiggle, 0.03)
	shake_tween.tween_property(sprite, "position", orig_pos, 0.05)
