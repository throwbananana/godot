class_name EnemyTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

signal enemy_destroyed(points: int, is_bonus: bool, drop_pos: Vector2)

enum EnemyType { BASIC, FAST, POWER, ARMOR }

@export var enemy_type: EnemyType = EnemyType.BASIC
@export var is_bonus: bool = false

var speed: float = 100.0
var max_health: int = 1
var health: int = 1
var score_value: int = 100
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

func _ready() -> void:
	add_to_group("enemies")
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
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
			fire_interval = 1.4
		EnemyType.FAST:
			prefix = "enemy_fast"
			speed = 185.0
			max_health = 1
			score_value = 200
			fire_interval = 1.1
		EnemyType.POWER:
			prefix = "enemy_power"
			speed = 120.0
			max_health = 2
			score_value = 300
			fire_interval = 0.75
		EnemyType.ARMOR:
			prefix = "enemy_armor"
			speed = 90.0
			max_health = 4
			score_value = 400
			fire_interval = 1.0

	health = max_health
	tex_f0 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f0.png" % prefix)
	tex_f1 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f1.png" % prefix)
	if tex_f0:
		sprite.texture = tex_f0

func freeze(duration: float) -> void:
	freeze_timer = duration

func _physics_process(delta: float) -> void:
	# 冰冻状态
	if freeze_timer > 0.0:
		freeze_timer -= delta
		# 冰冻淡蓝光晕
		sprite.modulate = Color(0.5, 0.8, 1.2)
		return

	# 红闪道具坦克视觉反馈
	if is_bonus:
		var flash = int(Time.get_ticks_msec() / 120) % 2 == 0
		sprite.modulate = Color(2.0, 0.4, 0.4) if flash else Color(1.0, 1.0, 1.0)
	elif enemy_type == EnemyType.ARMOR:
		_update_armor_color()
	else:
		sprite.modulate = Color(1.0, 1.0, 1.0)

	# 智能瞄准与开火判断
	_check_aim_and_fire(delta)

	# 换向决策
	change_dir_timer -= delta
	if change_dir_timer <= 0.0:
		_decide_smart_direction()
		change_dir_timer = randf_range(1.5, 3.5)

	# 沿当前方向行进并检测碰撞
	velocity = facing_direction * speed
	var collision = move_and_collide(velocity * delta)
	if collision:
		# 遇到障碍物：如果是砖墙，尝试开火击破；否则拐弯
		var collider = collision.get_collider()
		if collider and collider.is_in_group("brick"):
			if fire_timer > 0.3:
				fire_timer = 0.1 # 快速开火破墙
		_decide_smart_direction()

	# 履带动画
	if int(Time.get_ticks_msec() / 100) % 2 != current_frame:
		current_frame = 1 - current_frame
		if tex_f0 and tex_f1:
			sprite.texture = tex_f1 if current_frame == 1 else tex_f0

func _update_armor_color() -> void:
	match health:
		4: sprite.modulate = Color(1.0, 1.0, 1.0)
		3: sprite.modulate = Color(1.2, 1.1, 0.3)
		2: sprite.modulate = Color(1.3, 0.7, 0.2)
		1: sprite.modulate = Color(1.5, 0.3, 0.3)

func _check_aim_and_fire(delta: float) -> void:
	fire_timer -= delta
	if fire_timer <= 0.0:
		# 检查视线前方是否有玩家或老鹰基地
		if _has_target_in_line_of_sight():
			_shoot()
			fire_timer = randf_range(fire_interval * 0.8, fire_interval * 1.2)
		elif randf() < 0.35: # 周期性概率性巡逻开火
			_shoot()
			fire_timer = randf_range(fire_interval * 0.9, fire_interval * 1.4)

func _has_target_in_line_of_sight() -> bool:
	var space_state = get_world_2d().direct_space_state
	var ray_len = 450.0
	var query = PhysicsRayQueryParameters2D.create(
		global_position + facing_direction * 24.0,
		global_position + facing_direction * ray_len,
		1 | 16 # 检测玩家 (layer 1) 与 基地 (layer 5/16)
	)
	query.exclude = [get_rid()]
	var result = space_state.intersect_ray(query)
	if result:
		var col = result.collider
		if col.is_in_group("player") or col.is_in_group("base_eagle"):
			return true
	return false

func _decide_smart_direction() -> void:
	# 网格转弯对齐吸附 (Corner Snapping)
	_snap_to_grid_lane()

	var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	# 偏向进攻基地（基地在下方约 y=600 处）
	var weights = [10, 45, 25, 25] # UP, DOWN, LEFT, RIGHT
	
	# 如果下方有通道，极大概率朝下进攻
	var chosen_dir = Vector2.DOWN
	var total_weight = 0
	for w in weights: total_weight += w
	var r = randi_range(0, total_weight)
	var cum = 0
	for i in range(dirs.size()):
		cum += weights[i]
		if r <= cum:
			chosen_dir = dirs[i]
			break

	facing_direction = chosen_dir
	rotation = facing_direction.angle() + PI / 2.0

func _snap_to_grid_lane() -> void:
	var lane_size = 24.0
	if facing_direction == Vector2.UP or facing_direction == Vector2.DOWN:
		position.x = round(position.x / lane_size) * lane_size
	else:
		position.y = round(position.y / lane_size) * lane_size

func _shoot() -> void:
	if not bullet_scene:
		return
	var bullet = bullet_scene.instantiate()
	bullet.direction = facing_direction
	bullet.global_position = global_position + facing_direction * 26.0
	bullet.shooter = self
	bullet.shooter_type = "enemy"
	if enemy_type == EnemyType.POWER:
		bullet.speed = 580.0
	get_parent().add_child(bullet)

func take_damage(amount: int) -> void:
	health -= amount
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(2.5, 2.5, 2.5), 0.05)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.05)
	
	if health <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)
	enemy_destroyed.emit(score_value, is_bonus, global_position)
	queue_free()
