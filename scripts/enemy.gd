class_name EnemyTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal enemy_destroyed(points: int, is_bonus: bool, drop_pos: Vector2)

enum EnemyType { BASIC, FAST, POWER, ARMOR }

@export var enemy_type: EnemyType = EnemyType.BASIC
@export var is_bonus: bool = false

var speed: float = 100.0
var max_health: int = 1
var health: int = 1
var score_value: int = 100
var xp_value: int = 35
var gold_value: int = 20
var fire_interval: float = 1.2
var fire_timer: float = 0.0
var change_dir_timer: float = 0.0
var freeze_timer: float = 0.0

var facing_direction: Vector2 = Vector2.DOWN
var tex_f0: Texture2D
var tex_f1: Texture2D
var current_frame: int = 0

@onready var sprite: Sprite2D = $Sprite2D

var bullet_scene: PackedScene
var explosion_scene: PackedScene
var coin_scene: PackedScene

var hit_tween: Tween
var recoil_tween: Tween

func _ready() -> void:
	add_to_group("enemies")
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	coin_scene = load("res://scenes/gold_coin.tscn")
	_setup_tank_type()
	rotation = facing_direction.angle() + PI / 2.0
	change_dir_timer = randf_range(1.0, 2.5)
	fire_timer = randf_range(0.3, 1.2)

func _setup_tank_type() -> void:
	var prefix = "enemy_basic"
	match enemy_type:
		EnemyType.BASIC:
			prefix = "enemy_basic"
			speed = 110.0
			max_health = 1
			score_value = 100
			xp_value = 25
			gold_value = 15
			fire_interval = 1.4
		EnemyType.FAST:
			prefix = "enemy_fast"
			speed = 185.0
			max_health = 1
			score_value = 200
			xp_value = 40
			gold_value = 25
			fire_interval = 1.1
		EnemyType.POWER:
			prefix = "enemy_power"
			speed = 120.0
			max_health = 2
			score_value = 300
			xp_value = 55
			gold_value = 35
			fire_interval = 0.75
		EnemyType.ARMOR:
			prefix = "enemy_armor"
			speed = 90.0
			max_health = 4
			score_value = 400
			xp_value = 80
			gold_value = 50
			fire_interval = 1.0

	health = max_health
	tex_f0 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f0.png" % prefix)
	tex_f1 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f1.png" % prefix)
	if tex_f0:
		sprite.texture = tex_f0

func freeze(duration: float) -> void:
	freeze_timer = duration

func _physics_process(delta: float) -> void:
	if freeze_timer > 0.0:
		freeze_timer -= delta
		sprite.modulate = Color(0.5, 0.8, 1.2)
		return

	if is_bonus:
		var flash = int(Time.get_ticks_msec() / 120) % 2 == 0
		sprite.modulate = Color(2.0, 0.4, 0.4) if flash else Color(1.0, 1.0, 1.0)
	elif enemy_type == EnemyType.ARMOR:
		if health == 3:
			sprite.modulate = Color(1.2, 1.1, 0.6)
		elif health == 2:
			sprite.modulate = Color(1.3, 0.8, 0.4)
		elif health == 1:
			sprite.modulate = Color(1.5, 0.4, 0.4)
		else:
			sprite.modulate = Color(1.0, 1.0, 1.0)
	else:
		sprite.modulate = Color(1.0, 1.0, 1.0)

	change_dir_timer -= delta
	if change_dir_timer <= 0.0:
		_choose_new_direction()
		change_dir_timer = randf_range(1.5, 3.5)

	fire_timer -= delta
	if fire_timer <= 0.0:
		_shoot()
		fire_timer = randf_range(fire_interval * 0.8, fire_interval * 1.3)

	velocity = facing_direction * speed
	var collision = move_and_collide(velocity * delta)
	if collision:
		_choose_new_direction()

	if int(Time.get_ticks_msec() / 75) % 2 != current_frame:
		current_frame = 1 - current_frame
		if tex_f0 and tex_f1:
			sprite.texture = tex_f1 if current_frame == 1 else tex_f0

func _choose_new_direction() -> void:
	var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var weights = [1.0, 3.0, 2.0, 2.0] # 倾向于向下推进
	var total_w = 8.0
	var r = randf() * total_w
	var accum = 0.0
	var chosen = Vector2.DOWN
	for i in range(dirs.size()):
		accum += weights[i]
		if r <= accum:
			chosen = dirs[i]
			break

	facing_direction = chosen
	rotation = facing_direction.angle() + PI / 2.0

func _shoot() -> void:
	if not bullet_scene:
		return
	var bullet = bullet_scene.instantiate()
	bullet.direction = facing_direction
	bullet.speed = 360.0 if enemy_type != EnemyType.POWER else 480.0
	bullet.damage = 1
	bullet.can_destroy_steel = false
	var muzzle_pos = global_position + facing_direction * 26.0
	bullet.global_position = muzzle_pos
	bullet.shooter = self
	bullet.shooter_type = "enemy"
	get_parent().add_child(bullet)

	# 枪口后坐力与火花
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	recoil_tween = create_tween()
	recoil_tween.tween_property(sprite, "position", Vector2(0, 3.0), 0.04)
	recoil_tween.tween_property(sprite, "position", Vector2.ZERO, 0.08)
	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)

func take_damage(amount: int) -> void:
	health -= amount
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	# 受击形变晃动
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	hit_tween = create_tween()
	hit_tween.tween_property(sprite, "scale", Vector2(0.24, 0.12), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(sprite, "scale", Vector2(0.15, 0.22), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hit_tween.tween_property(sprite, "scale", Vector2(0.18, 0.18), 0.08).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if health <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)

	if enemy_type == EnemyType.ARMOR or enemy_type == EnemyType.POWER:
		VFXAnimator.spawn_shockwave(get_parent(), global_position)

	if coin_scene and randf() < 0.4:
		var coin = coin_scene.instantiate()
		coin.global_position = global_position
		coin.gold_amount = gold_value
		get_parent().call_deferred("add_child", coin)

	enemy_destroyed.emit(score_value, is_bonus, global_position)
	queue_free()

func get_points() -> int:
	return score_value

func get_xp() -> int:
	return xp_value

func get_gold() -> int:
	return gold_value
