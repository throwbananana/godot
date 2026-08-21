class_name TrainCarriage
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal destroyed(carriage: TrainCarriage)

@export var carriage_type: String = "turret" # "turret", "armor", "rocket", "enemy_gunner"
@export var is_enemy: bool = false
@export var follow_distance: float = 38.0
@export var max_health: int = 5
@export var fire_range: float = 280.0

var current_health: int = 5
var leader_node: Node2D = null
var bullet_scene: PackedScene
var explosion_scene: PackedScene
var carriage_frames: Array[Texture2D] = []
var current_frame: int = 0
var anim_timer: float = 0.0

var fire_timer: float = 0.0
var fire_interval: float = 0.9
var hit_tween: Tween

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Position history buffer for smooth train snake following
var history_positions: Array[Vector2] = []
var history_rotations: Array[float] = []

func _ready() -> void:
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	current_health = max_health

	if is_enemy:
		add_to_group("enemies")
		collision_layer = 2
		collision_mask = 1 | 4 | 16
		fire_interval = 1.4
	else:
		add_to_group("player")
		add_to_group("player_carriage")
		collision_layer = 1
		collision_mask = 2 | 4 | 16
		fire_interval = 0.85

	_load_textures()

func _load_textures() -> void:
	carriage_frames.clear()
	var prefix = ""
	if is_enemy:
		if carriage_type == "enemy_gunner" or carriage_type == "turret":
			prefix = "enemy_train_wagon_gunner"
		else:
			prefix = "enemy_train_wagon_armor"
	else:
		match carriage_type:
			"turret":
				prefix = "train_wagon_turret"
			"armor":
				prefix = "train_wagon_armor"
			"rocket":
				prefix = "train_wagon_rocket"
			_:
				prefix = "train_wagon_turret"

	for i in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [prefix, i])
		if tex:
			carriage_frames.append(tex)

	if carriage_frames.size() > 0 and sprite:
		sprite.texture = carriage_frames[0]
		sprite.scale = Vector2(0.1875, 0.1875)

func setup(leader: Node2D, type: String, enemy_flag: bool = false) -> void:
	leader_node = leader
	carriage_type = type
	is_enemy = enemy_flag
	if leader:
		global_position = leader.global_position - Vector2.UP.rotated(leader.rotation) * follow_distance
		rotation = leader.rotation
	_load_textures()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(leader_node):
		# Leader is dead; explode carriage
		take_damage(999)
		return

	# Follow leader using distance constraint
	var leader_pos = leader_node.global_position
	var to_leader = leader_pos - global_position
	var dist = to_leader.length()

	if dist > follow_distance:
		var target_pos = leader_pos - to_leader.normalized() * follow_distance
		global_position = global_position.lerp(target_pos, delta * 11.0)
		
		# Smoothly rotate to face direction of travel
		var move_dir = (target_pos - global_position).normalized()
		if move_dir.length_squared() > 0.01:
			var target_rot = move_dir.angle() + PI / 2.0
			rotation = lerp_angle(rotation, target_rot, delta * 10.0)

		# Tread wheel animation
		anim_timer += delta * 9.0
		if anim_timer >= 1.0:
			anim_timer = 0.0
			current_frame = (current_frame + 1) % mini(6, maxi(1, carriage_frames.size()))
			if carriage_frames.size() > current_frame and sprite:
				sprite.texture = carriage_frames[current_frame]

	# Combat behavior
	fire_timer -= delta
	if fire_timer <= 0.0:
		_process_combat()

func _process_combat() -> void:
	var target = _find_nearest_target()
	if not target or not is_instance_valid(target):
		return

	var dist = global_position.distance_to(target.global_position)
	if dist > fire_range:
		return

	fire_timer = fire_interval
	var aim_dir = (target.global_position - global_position).normalized()

	match carriage_type:
		"turret", "enemy_gunner":
			_fire_bullet(aim_dir, false)
		"rocket":
			_fire_bullet(aim_dir, true)
		"armor":
			# Pulse defense wave
			VFXAnimator.spawn_shockwave(get_parent(), global_position)
			fire_timer = 3.0

func _find_nearest_target() -> Node2D:
	var target_group = "player" if is_enemy else "enemies"
	var nodes = get_tree().get_nodes_in_group(target_group)
	var nearest: Node2D = null
	var min_dist = 99999.0

	for node in nodes:
		if node == self or not is_instance_valid(node) or not (node is Node2D):
			continue
		if node.is_in_group("player_carriage") and is_enemy == false:
			continue
		var d = global_position.distance_to(node.global_position)
		if d < min_dist:
			min_dist = d
			nearest = node
	return nearest

func _fire_bullet(dir: Vector2, is_rocket: bool) -> void:
	if not bullet_scene:
		return

	var bullet = bullet_scene.instantiate()
	bullet.direction = dir
	bullet.speed = 480.0 if not is_rocket else 360.0
	bullet.damage = 1 if not is_rocket else 2
	bullet.can_destroy_steel = is_rocket
	bullet.shooter = self
	bullet.shooter_type = "enemy" if is_enemy else "player"

	get_parent().add_child(bullet)
	bullet.global_position = global_position + dir * 18.0

	VFXAnimator.spawn_muzzle_flash(get_parent(), bullet.global_position, dir.angle() + PI/2.0)
	SoundManager.play_shot(get_tree())

func take_damage(amount: int) -> void:
	current_health -= amount
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	hit_tween = create_tween()
	hit_tween.tween_property(sprite, "scale", Vector2(0.24, 0.14), 0.05)
	hit_tween.tween_property(sprite, "scale", Vector2(0.1875, 0.1875), 0.08)
	hit_tween.parallel().tween_property(sprite, "modulate", Color(2.5, 0.6, 0.6), 0.05)
	hit_tween.chain().tween_property(sprite, "modulate", Color.WHITE, 0.08)

	if current_health <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	destroyed.emit(self)
	queue_free()
