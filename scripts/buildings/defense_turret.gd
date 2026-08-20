class_name DefenseTurret
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

@export var max_health: int = 8
@export var attack_range: float = 220.0
@export var fire_interval: float = 0.65

var current_health: int = 8
var fire_timer: float = 0.0
var target_enemy: Node2D = null

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var gun_sprite: Sprite2D = $GunSprite
@onready var range_area: Area2D = $RangeArea

var bullet_scene: PackedScene
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("steel")
	current_health = max_health
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")

	var b_tex = TextureHelper.get_tex("res://assets/sprites/buildings/turret_base.png")
	var g_tex = TextureHelper.get_tex("res://assets/sprites/buildings/turret_gun.png")
	if b_tex: base_sprite.texture = b_tex
	if g_tex: gun_sprite.texture = g_tex

func _physics_process(delta: float) -> void:
	_find_nearest_target()
	
	if target_enemy and is_instance_valid(target_enemy):
		var target_dir = (target_enemy.global_position - global_position).normalized()
		gun_sprite.rotation = target_dir.angle() + PI / 2.0
		
		fire_timer -= delta
		if fire_timer <= 0.0:
			fire_timer = fire_interval
			_shoot(target_dir)
	else:
		fire_timer = maxf(0.0, fire_timer - delta)

func _find_nearest_target() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest_dist = attack_range
	target_enemy = null
	
	for e in enemies:
		if is_instance_valid(e):
			var dist = global_position.distance_to(e.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				target_enemy = e

func _shoot(dir: Vector2) -> void:
	if not bullet_scene:
		return
	var bullet = bullet_scene.instantiate()
	bullet.direction = dir
	bullet.speed = 520.0
	bullet.global_position = global_position + dir * 24.0
	bullet.shooter = self
	bullet.shooter_type = "player"
	get_parent().add_child(bullet)
	SoundManager.play_shot(get_tree())

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	var tween = create_tween()
	tween.tween_property(base_sprite, "modulate", Color(0.3, 2.0, 0.5), 0.1)
	tween.tween_property(base_sprite, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func take_damage(amount: int) -> void:
	current_health -= amount
	var tween = create_tween()
	tween.tween_property(base_sprite, "modulate", Color(2.5, 0.5, 0.5), 0.08)
	tween.tween_property(base_sprite, "modulate", Color(1.0, 1.0, 1.0), 0.08)
	if current_health <= 0:
		_destroy()

func _destroy() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)
	queue_free()
