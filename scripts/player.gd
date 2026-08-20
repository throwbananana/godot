class_name PlayerTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

signal destroyed
signal fired_bullet

@export var speed: float = 180.0
@export var fire_cooldown: float = 0.28
@export var max_health: int = 1

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
	tex_f0 = TextureHelper.get_tex("res://assets/sprites/tanks/player_tank_yellow_f0.png")
	tex_f1 = TextureHelper.get_tex("res://assets/sprites/tanks/player_tank_yellow_f1.png")
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")

	if tex_f0:
		sprite.texture = tex_f0
	current_health = max_health
	set_invulnerable(3.0)

func set_invulnerable(duration: float) -> void:
	is_invulnerable = true
	invulnerable_timer = duration
	if shield_sprite:
		shield_sprite.visible = true

func _physics_process(delta: float) -> void:
	if is_invulnerable:
		invulnerable_timer -= delta
		if shield_sprite:
			shield_sprite.rotation += delta * 4.0
			shield_sprite.modulate.a = 0.5 + sin(Time.get_ticks_msec() * 0.01) * 0.3
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
	
	if input_vec != Vector2.ZERO:
		facing_direction = input_vec
		velocity = input_vec * speed
		rotation = facing_direction.angle() + PI / 2.0
		if int(Time.get_ticks_msec() / 80) % 2 != current_frame:
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
	can_fire = false
	fire_timer = fire_cooldown
	var bullet = bullet_scene.instantiate()
	bullet.direction = facing_direction
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
