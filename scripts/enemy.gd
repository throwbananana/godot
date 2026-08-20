class_name EnemyTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

signal enemy_destroyed(points: int)

enum EnemyType { BASIC, FAST, POWER, ARMOR }

@export var enemy_type: EnemyType = EnemyType.BASIC

var speed: float = 100.0
var health: int = 1
var score_value: int = 100
var fire_interval: float = 1.2
var fire_timer: float = 0.0
var change_dir_timer: float = 0.0

var facing_direction: Vector2 = Vector2.DOWN
var tex_f0: Texture2D
var tex_f1: Texture2D
var current_frame: int = 0

@onready var sprite: Sprite2D = $Sprite2D

var bullet_scene: PackedScene
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("enemies")
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	_setup_tank_type()
	rotation = facing_direction.angle() + PI / 2.0
	change_dir_timer = randf_range(1.0, 2.5)
	fire_timer = randf_range(0.5, 1.5)

func _setup_tank_type() -> void:
	var prefix = "enemy_basic"
	match enemy_type:
		EnemyType.BASIC:
			prefix = "enemy_basic"
			speed = 100.0
			health = 1
			score_value = 100
			fire_interval = 1.6
		EnemyType.FAST:
			prefix = "enemy_fast"
			speed = 170.0
			health = 1
			score_value = 200
			fire_interval = 1.2
		EnemyType.POWER:
			prefix = "enemy_power"
			speed = 110.0
			health = 2
			score_value = 300
			fire_interval = 0.85
		EnemyType.ARMOR:
			prefix = "enemy_armor"
			speed = 80.0
			health = 4
			score_value = 400
			fire_interval = 1.1

	tex_f0 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f0.png" % prefix)
	tex_f1 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f1.png" % prefix)
	if tex_f0:
		sprite.texture = tex_f0

func _physics_process(delta: float) -> void:
	change_dir_timer -= delta
	if change_dir_timer <= 0.0:
		_choose_new_direction()
		change_dir_timer = randf_range(1.5, 3.5)

	fire_timer -= delta
	if fire_timer <= 0.0:
		_shoot()
		fire_timer = randf_range(fire_interval * 0.7, fire_interval * 1.3)

	velocity = facing_direction * speed
	var collision = move_and_collide(velocity * delta)
	if collision:
		_choose_new_direction()

	if int(Time.get_ticks_msec() / 100) % 2 != current_frame:
		current_frame = 1 - current_frame
		if tex_f0 and tex_f1:
			sprite.texture = tex_f1 if current_frame == 1 else tex_f0

func _choose_new_direction() -> void:
	var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	if randf() < 0.45:
		facing_direction = Vector2.DOWN
	else:
		dirs.shuffle()
		facing_direction = dirs[0]
	rotation = facing_direction.angle() + PI / 2.0

func _shoot() -> void:
	if not bullet_scene:
		return
	var bullet = bullet_scene.instantiate()
	bullet.direction = facing_direction
	bullet.global_position = global_position + facing_direction * 28.0
	bullet.shooter = self
	bullet.shooter_type = "enemy"
	get_parent().add_child(bullet)

func take_damage(amount: int) -> void:
	health -= amount
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0), 0.05)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.05)
	
	if health <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)
	enemy_destroyed.emit(score_value)
	queue_free()
