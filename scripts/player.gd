class_name PlayerTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const PowerUp = preload("res://scripts/power_up.gd")

signal destroyed
signal fired_bullet
signal powerup_collected(type_name: String)

@export var base_speed: float = 180.0
@export var fire_cooldown: float = 0.28
@export var max_health: int = 1

var upgrade_tier: int = 0 # 0=基础, 1=提速+速射, 2=连发, 3=超武破钢
var current_health: int = 1
var can_fire: bool = true
var fire_timer: float = 0.0
var facing_direction: Vector2 = Vector2.UP
var is_invulnerable: bool = false
var invulnerable_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shield_sprite: Sprite2D = $ShieldSprite

var tex_f0: Texture2D
var tex_f1: Texture2D
var current_frame: int = 0

var bullet_scene: PackedScene
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("player")
	_update_tier_appearance()
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	current_health = max_health
	set_invulnerable(3.5)

func _update_tier_appearance() -> void:
	var prefix = "player_tank_yellow" if upgrade_tier < 2 else "player_tank_green"
	tex_f0 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f0.png" % prefix)
	tex_f1 = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f1.png" % prefix)
	if tex_f0 and sprite:
		sprite.texture = tex_f0

func apply_powerup(type: PowerUp.Type) -> void:
	var main = get_tree().current_scene
	match type:
		PowerUp.Type.STAR:
			upgrade_tier = mini(upgrade_tier + 1, 3)
			_update_tier_appearance()
			powerup_collected.emit("STAR (TIER %d)" % (upgrade_tier + 1))
		PowerUp.Type.HELMET:
			set_invulnerable(10.0)
			powerup_collected.emit("HELMET SHIELD")
		PowerUp.Type.BOMB:
			if main and main.has_method("trigger_bomb"):
				main.trigger_bomb()
			powerup_collected.emit("SCREEN BOMB")
		PowerUp.Type.CLOCK:
			if main and main.has_method("trigger_freeze"):
				main.trigger_freeze(7.5)
			powerup_collected.emit("TIME FREEZE")
		PowerUp.Type.SHOVEL:
			if main and main.has_method("trigger_shovel"):
				main.trigger_shovel(15.0)
			powerup_collected.emit("STEEL BASE")
		PowerUp.Type.LIFE:
			if main and main.has_method("add_life"):
				main.add_life(1)
			powerup_collected.emit("EXTRA LIFE")

func set_invulnerable(duration: float) -> void:
	is_invulnerable = true
	invulnerable_timer = duration
	if shield_sprite:
		shield_sprite.visible = true

func _physics_process(delta: float) -> void:
	if is_invulnerable:
		invulnerable_timer -= delta
		if shield_sprite:
			shield_sprite.rotation += delta * 5.0
			shield_sprite.modulate.a = 0.5 + sin(Time.get_ticks_msec() * 0.015) * 0.35
		if invulnerable_timer <= 0.0:
			is_invulnerable = false
			if shield_sprite:
				shield_sprite.visible = false
	
	if not can_fire:
		fire_timer -= delta
		if fire_timer <= 0.0:
			can_fire = true

	var input_vec = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		input_vec = Vector2.UP
	elif Input.is_action_pressed("move_down"):
		input_vec = Vector2.DOWN
	elif Input.is_action_pressed("move_left"):
		input_vec = Vector2.LEFT
	elif Input.is_action_pressed("move_right"):
		input_vec = Vector2.RIGHT
	
	var current_speed = base_speed * (1.2 if upgrade_tier >= 1 else 1.0)

	if input_vec != Vector2.ZERO:
		facing_direction = input_vec
		velocity = input_vec * current_speed
		rotation = facing_direction.angle() + PI / 2.0
		
		# 履带动画
		if int(Time.get_ticks_msec() / 70) % 2 != current_frame:
			current_frame = 1 - current_frame
			if tex_f0 and tex_f1:
				sprite.texture = tex_f1 if current_frame == 1 else tex_f0
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	if Input.is_action_pressed("fire") and can_fire:
		_shoot()

func _shoot() -> void:
	if not bullet_scene:
		return
	var cd = fire_cooldown * (0.75 if upgrade_tier >= 1 else 1.0)
	can_fire = false
	fire_timer = cd
	
	var b_speed = 480.0 if upgrade_tier == 0 else 620.0
	var can_break_steel = (upgrade_tier >= 3)
	
	var bullet = bullet_scene.instantiate()
	bullet.direction = facing_direction
	bullet.speed = b_speed
	bullet.can_destroy_steel = can_break_steel
	bullet.global_position = global_position + facing_direction * 28.0
	bullet.shooter = self
	bullet.shooter_type = "player"
	get_parent().add_child(bullet)
	
	SoundManager.play_shot(get_tree())
	fired_bullet.emit()

func take_damage(amount: int) -> void:
	if is_invulnerable:
		return
	current_health -= amount
	if current_health <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)
	destroyed.emit()
	queue_free()
