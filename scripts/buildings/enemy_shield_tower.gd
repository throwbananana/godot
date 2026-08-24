class_name EnemyShieldTower
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal tower_destroyed

@export var max_hp: int = 8
@export var shield_radius: float = 180.0

var current_hp: int = 8
var anim_timer: float = 0.0
var frame_index: int = 0
var shielded_enemies: Array[Node2D] = []
var frame_textures: Array[Texture2D] = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var shield_area: Area2D = $ShieldArea
@onready var shield_shape: CollisionShape2D = $ShieldArea/CollisionShape2D
@onready var field_visual: Node2D = $FieldVisual

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("enemy_building")
	add_to_group("enemy_shield_tower")
	current_hp = max_hp

	# Load 4 animated frames
	for i in range(4):
		var tex = TextureHelper.get_tex("res://assets/sprites/buildings/enemy_shield_tower_f%d.png" % i)
		if tex:
			frame_textures.append(tex)

	if frame_textures.size() > 0 and sprite:
		sprite.texture = frame_textures[0]

	if shield_shape and shield_shape.shape is CircleShape2D:
		(shield_shape.shape as CircleShape2D).radius = shield_radius

	if shield_area:
		shield_area.body_entered.connect(_on_shield_area_entered)
		shield_area.body_exited.connect(_on_shield_area_exited)

	# Initial scale pop-in animation
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _process(delta: float) -> void:
	# Cycle rotation frames
	if frame_textures.size() > 0 and sprite:
		anim_timer += delta * 5.0
		frame_index = int(anim_timer) % frame_textures.size()
		sprite.texture = frame_textures[frame_index]

	# Redraw field visual
	if field_visual:
		field_visual.queue_redraw()

	# Periodic cleanup of dead or deleted enemy instances
	for i in range(shielded_enemies.size() - 1, -1, -1):
		var e = shielded_enemies[i]
		if not is_instance_valid(e):
			shielded_enemies.remove_at(i)

	# Scan for any enemy bodies inside shield_area that might have spawned inside
	if shield_area:
		for b in shield_area.get_overlapping_bodies():
			if is_instance_valid(b) and _is_enemy_unit(b) and not shielded_enemies.has(b):
				_protect_enemy(b)

func _is_enemy_unit(body: Node2D) -> bool:
	return body.is_in_group("enemy") or body.is_in_group("enemies") or body.has_method("add_shield_source")

func _protect_enemy(body: Node2D) -> void:
	if not shielded_enemies.has(body):
		shielded_enemies.append(body)
		if body.has_method("add_shield_source"):
			body.add_shield_source(self)
		VFXAnimator.spawn_dust_puff(get_parent(), body.global_position)

func _on_shield_area_entered(body: Node2D) -> void:
	if is_instance_valid(body) and _is_enemy_unit(body):
		_protect_enemy(body)
		SoundManager.play_pickup(get_tree())

func _on_shield_area_exited(body: Node2D) -> void:
	if shielded_enemies.has(body):
		if is_instance_valid(body) and body.has_method("remove_shield_source"):
			body.remove_shield_source(self)
		shielded_enemies.erase(body)

func take_damage(amount: int) -> void:
	current_hp -= amount
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	# Structural hit shudder
	var tw = create_tween()
	tw.tween_property(sprite, "position", Vector2(randf_range(-3, 3), randf_range(-3, 3)), 0.04)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.04)

	# Red flash on tower when damaged
	if sprite:
		sprite.modulate = Color(2.5, 0.6, 0.6, 1.0)
		var flash_tw = create_tween()
		flash_tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)

	if current_hp <= 0:
		_destroy()

func take_hit(amount: int) -> void:
	take_damage(amount)

func _destroy() -> void:
	# Release all shielded enemies and cancel their invulnerability buff
	for body in shielded_enemies:
		if is_instance_valid(body) and body.has_method("remove_shield_source"):
			body.remove_shield_source(self)
	shielded_enemies.clear()

	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	tower_destroyed.emit()
	queue_free()
