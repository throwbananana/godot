class_name EnemyTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal enemy_destroyed(points: int, is_bonus: bool, drop_pos: Vector2)

enum EnemyType { BASIC, FAST, POWER, ARMOR, BOSS }

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
var tank_frames: Array[Texture2D] = []
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
		EnemyType.BOSS:
			prefix = "enemy_boss"
			speed = 75.0
			max_health = 10
			score_value = 1500
			xp_value = 250
			gold_value = 180
			fire_interval = 0.65

	# 动态难度缩放 (Dynamic Scaling based on floor & encounter type)
	var floor_mult = 1.0 + float(GameState.current_floor) * 0.08
	if GameState.battle_type == "elite":
		max_health = int(ceil(max_health * 1.5))
		speed = speed * 1.10
		xp_value = int(xp_value * 1.6)
		gold_value = int(gold_value * 1.5)
		score_value = int(score_value * 1.5)
		fire_interval = fire_interval * 0.85
	elif GameState.battle_type == "boss":
		if enemy_type != EnemyType.BOSS:
			max_health = int(ceil(max_health * 1.6))
		speed = speed * 1.12
		xp_value = int(xp_value * 1.8)
		gold_value = int(gold_value * 1.8)
		score_value = int(score_value * 1.8)
		fire_interval = fire_interval * 0.80
	else:
		xp_value = int(xp_value * floor_mult)
		gold_value = int(gold_value * floor_mult)
		score_value = int(score_value * floor_mult)

	health = max_health
	tank_frames.clear()
	for i in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [prefix, i])
		if tex:
			tank_frames.append(tex)
	if tank_frames.size() > 0 and sprite:
		sprite.texture = tank_frames[0]
		if enemy_type == EnemyType.BOSS:
			sprite.scale = Vector2(0.24, 0.24)

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

	if tank_frames.size() > 0:
		var f_idx = int(Time.get_ticks_msec() / 65) % tank_frames.size()
		if f_idx != current_frame:
			current_frame = f_idx
			sprite.texture = tank_frames[current_frame]

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

	if enemy_type == EnemyType.BOSS:
		# Twin Super Siege Cannons Firing
		var right_vec = facing_direction.rotated(PI / 2.0)
		for side in [-1.0, 1.0]:
			var b = bullet_scene.instantiate()
			b.direction = facing_direction
			b.speed = 460.0
			b.damage = 1
			b.can_destroy_steel = true
			var m_pos = global_position + facing_direction * 30.0 + right_vec * (side * 8.0)
			b.global_position = m_pos
			b.shooter = self
			b.shooter_type = "enemy"
			get_parent().add_child(b)
			VFXAnimator.spawn_muzzle_flash(get_parent(), m_pos, rotation)
	else:
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
		VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)

	# 枪口后坐力与火花
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	recoil_tween = create_tween()
	recoil_tween.tween_property(sprite, "position", Vector2(0, 4.0), 0.04)
	recoil_tween.tween_property(sprite, "position", Vector2.ZERO, 0.08)

func take_damage(amount: int) -> void:
	health -= amount
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	# 按敌人类型追加额外特效
	if enemy_type == EnemyType.ARMOR or enemy_type == EnemyType.BOSS:
		VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	elif enemy_type == EnemyType.POWER:
		VFXAnimator.spawn_shockwave(get_parent(), global_position)

	if enemy_type == EnemyType.BOSS:
		VFXAnimator.spawn_shockwave(get_parent(), global_position)

	# 受击形变晃动
	var base_scale = Vector2(0.24, 0.24) if enemy_type == EnemyType.BOSS else Vector2(0.196, 0.196)
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	hit_tween = create_tween()
	hit_tween.tween_property(sprite, "scale", base_scale * Vector2(1.3, 0.7), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(sprite, "scale", base_scale * Vector2(0.8, 1.2), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hit_tween.tween_property(sprite, "scale", base_scale, 0.08).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if health <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)

	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	if enemy_type == EnemyType.ARMOR or enemy_type == EnemyType.POWER:
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		# Delayed second shockwave for dramatic heavy-tank destruction
		get_tree().create_timer(0.15).timeout.connect(func():
			if is_instance_valid(get_parent()):
				VFXAnimator.spawn_shockwave(get_parent(), global_position)
		)

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
