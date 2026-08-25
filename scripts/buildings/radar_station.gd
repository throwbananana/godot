class_name RadarStation
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_health: int = 10
var current_health: int = 10
var is_destroyed: bool = false

var scan_timer: float = 0.0
var sprite: Sprite2D
var collision_shape: CollisionShape2D
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("radar_station")
	add_to_group("destructible")

	explosion_scene = load("res://scenes/explosion.tscn")

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/radar_station.png")
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)
	add_child(sprite)

	collision_shape = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(44.0, 44.0)
	collision_shape.shape = box
	add_child(collision_shape)

	var main = get_tree().current_scene if is_inside_tree() else null
	var hp_mult = main.rpg_mgr.get_building_hp_mult() if (main and "rpg_mgr" in main and main.rpg_mgr) else 1.0
	current_health = maxi(1, int(max_health * hp_mult))
	max_health = current_health

func _process(delta: float) -> void:
	if is_destroyed:
		return
	scan_timer += delta
	if scan_timer >= 3.5:
		scan_timer = 0.0
		_trigger_radar_sweep()

func _trigger_radar_sweep() -> void:
	if not is_inside_tree():
		return
	var p = get_parent()
	if p:
		VFXAnimator.spawn_shockwave(p, global_position)
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())

	# 视觉雷达脉冲微颤
	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(0.3, 2.5, 0.6), 0.1)
		tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.15)

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health -= amount
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	var p = get_parent()
	if p:
		VFXAnimator.spawn_clay_debris(p, global_position)

	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(3.0, 0.4, 0.4), 0.06)
		tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.08)

	if current_health <= 0:
		destroy()

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	var p = get_parent()
	if p:
		if explosion_scene:
			var exp_inst = explosion_scene.instantiate()
			p.add_child(exp_inst)
			exp_inst.global_position = global_position
		VFXAnimator.spawn_shockwave(p, global_position)
		VFXAnimator.spawn_clay_debris(p, global_position)
	queue_free()
