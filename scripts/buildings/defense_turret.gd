class_name DefenseTurret
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

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
	# 外观差分 (通用战损贴花 + 战区覆盖层)。延迟调用: 有的建筑在 _ready() 里
	# 才创建 sprite / 才按 rpg_mgr 改 max_health, 立即调会读到还没成形的状态。
	BuildingSkin.attach.call_deferred(self)
	add_to_group("buildings")
	add_to_group("steel")
	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		max_health = int(max_health * main.rpg_mgr.get_building_hp_mult())
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
		# Snap to whichever cardinal axis currently dominates toward the
		# target -- every other tank/bullet in this game only ever moves or
		# aims up/down/left/right, so the auto-turret can't be the one
		# exception that tracks a free diagonal angle.
		var to_target = target_enemy.global_position - global_position
		var target_dir = Vector2.RIGHT if to_target.x > 0.0 else Vector2.LEFT
		if absf(to_target.y) > absf(to_target.x):
			target_dir = Vector2.DOWN if to_target.y > 0.0 else Vector2.UP
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
	bullet.shooter = self
	bullet.shooter_type = "player"
	get_parent().add_child(bullet)
	var muzzle_pos = global_position + dir * 26.0
	bullet.global_position = muzzle_pos
	SoundManager.play_shot(get_tree())

	# 枪口后坐力与火花
	var tw = create_tween()
	tw.tween_property(gun_sprite, "position", -dir * 3.0, 0.04)
	tw.tween_property(gun_sprite, "position", Vector2.ZERO, 0.08)
	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, gun_sprite.rotation)

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
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position
	queue_free()
