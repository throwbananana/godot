class_name PlayerTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const PowerUp = preload("res://scripts/power_up.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal destroyed(pid: int)
signal fired_bullet
signal powerup_collected(type_name: String)
signal health_changed(pid: int, curr: int, max_hp: int)

@export var player_id: int = 1 # 1=P1 (Yellow/Gold), 2=P2 (Green/Mint)
@export var base_speed: float = 180.0
@export var fire_cooldown: float = 0.28

var upgrade_tier: int = 0
var max_health: int = 1
var current_health: int = 1
var can_fire: bool = true
var fire_timer: float = 0.0
var facing_direction: Vector2 = Vector2.UP
var is_invulnerable: bool = false
var invulnerable_timer: float = 0.0
var regen_accumulator: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shield_sprite: Sprite2D = $ShieldSprite

var tank_frames: Array[Texture2D] = []
var current_frame: int = 0

var shield_textures: Array[Texture2D] = []
var shield_frame: int = 0

var bullet_scene: PackedScene
var explosion_scene: PackedScene

var base_color: Color = Color(1.0, 1.0, 1.0)
var hit_tween: Tween
var recoil_tween: Tween

func _ready() -> void:
	add_to_group("player")
	if player_id == 1:
		add_to_group("p1")
		base_color = Color(1.0, 1.0, 1.0)
	else:
		add_to_group("p2")
		base_color = Color(0.40, 1.35, 0.70)

	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	
	for i in range(8):
		var s_tex = TextureHelper.get_tex("res://assets/sprites/effects/shield_bubble_%d.png" % i)
		if s_tex:
			shield_textures.append(s_tex)
	if shield_sprite:
		shield_sprite.scale = Vector2(0.24, 0.24)
		if shield_textures.size() > 0:
			shield_sprite.texture = shield_textures[0]

	_apply_rpg_stats()
	_update_tier_appearance()
	set_invulnerable(3.5)

func _apply_rpg_stats() -> void:
	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		max_health = main.rpg_mgr.get_player_max_hp()
		current_health = max_health
		health_changed.emit(player_id, current_health, max_health)

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(player_id, current_health, max_health)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.3, 2.2, 0.6), 0.1)
	tween.tween_property(sprite, "modulate", base_color, 0.1)

func _update_tier_appearance() -> void:
	var prefix = "player_tier%d" % upgrade_tier
	tank_frames.clear()
	for i in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [prefix, i])
		if tex:
			tank_frames.append(tex)
	if tank_frames.size() > 0 and sprite:
		sprite.texture = tank_frames[0]
		sprite.modulate = base_color

func apply_powerup(type: PowerUp.Type) -> void:
	var main = get_tree().current_scene
	var p_name = "P1" if player_id == 1 else "P2"
	match type:
		PowerUp.Type.STAR:
			upgrade_tier = mini(upgrade_tier + 1, 3)
			_update_tier_appearance()
			VFXAnimator.spawn_shockwave(get_parent(), global_position)
			var rank_name = ["BASIC", "SCOUT+", "TWIN-CANNON", "PLASMA DREADNOUGHT"][upgrade_tier]
			powerup_collected.emit("[%s] STAR UPGRADE: %s!" % [p_name, rank_name])
		PowerUp.Type.HELMET:
			set_invulnerable(10.0)
			powerup_collected.emit("[%s] HELMET SHIELD (10s)" % p_name)
		PowerUp.Type.BOMB:
			if main and main.has_method("trigger_bomb"):
				main.trigger_bomb()
			powerup_collected.emit("[%s] SCREEN BOMB TRIGGERED!" % p_name)
		PowerUp.Type.CLOCK:
			if main and main.has_method("trigger_freeze"):
				main.trigger_freeze(7.5)
			powerup_collected.emit("[%s] TIME FROZEN (7.5s)" % p_name)
		PowerUp.Type.SHOVEL:
			if main and main.has_method("trigger_shovel"):
				main.trigger_shovel(15.0)
			powerup_collected.emit("[%s] STEEL BASE FORTIFIED!" % p_name)
		PowerUp.Type.LIFE:
			if main and main.has_method("add_life"):
				main.add_life(1)
			powerup_collected.emit("[%s] +1 EXTRA LIFE!" % p_name)

func set_invulnerable(duration: float) -> void:
	is_invulnerable = true
	invulnerable_timer = duration
	if shield_sprite:
		shield_sprite.visible = true

func _physics_process(delta: float) -> void:
	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		var regen = main.rpg_mgr.get_regen_rate()
		if regen > 0.0 and current_health < max_health:
			regen_accumulator += regen * delta
			if regen_accumulator >= 1.0:
				regen_accumulator -= 1.0
				heal(1)

	if is_invulnerable:
		invulnerable_timer -= delta
		if shield_sprite and shield_textures.size() > 0:
			shield_sprite.rotation += delta * 4.0
			var s_idx = int(Time.get_ticks_msec() / 100) % shield_textures.size()
			shield_sprite.texture = shield_textures[s_idx]
		if invulnerable_timer <= 0.0:
			is_invulnerable = false
			if shield_sprite:
				shield_sprite.visible = false
	
	if not can_fire:
		fire_timer -= delta
		if fire_timer <= 0.0:
			can_fire = true

	var act_up = "p1_move_up" if player_id == 1 else "p2_move_up"
	var act_down = "p1_move_down" if player_id == 1 else "p2_move_down"
	var act_left = "p1_move_left" if player_id == 1 else "p2_move_left"
	var act_right = "p1_move_right" if player_id == 1 else "p2_move_right"
	var act_fire = "p1_fire" if player_id == 1 else "p2_fire"

	var input_vec = Vector2.ZERO
	if Input.is_action_pressed(act_up):
		input_vec = Vector2.UP
	elif Input.is_action_pressed(act_down):
		input_vec = Vector2.DOWN
	elif Input.is_action_pressed(act_left):
		input_vec = Vector2.LEFT
	elif Input.is_action_pressed(act_right):
		input_vec = Vector2.RIGHT
	
	var speed_mult = (1.0 + float(upgrade_tier) * 0.12)
	if main and main.rpg_mgr:
		speed_mult *= main.rpg_mgr.get_speed_multiplier()
	var current_speed = base_speed * speed_mult

	if input_vec != Vector2.ZERO:
		facing_direction = input_vec
		velocity = input_vec * current_speed
		rotation = facing_direction.angle() + PI / 2.0
		
		if tank_frames.size() > 0:
			var f_idx = int(Time.get_ticks_msec() / 60) % tank_frames.size()
			if f_idx != current_frame:
				current_frame = f_idx
				sprite.texture = tank_frames[current_frame]
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	if Input.is_action_pressed(act_fire) and can_fire:
		_shoot()

func _shoot() -> void:
	if not bullet_scene:
		return
	var main = get_tree().current_scene
	var cd = fire_cooldown * (0.65 if upgrade_tier >= 1 else 1.0)
	if main and main.rpg_mgr:
		cd *= main.rpg_mgr.get_fire_cooldown_mult()
	can_fire = false
	fire_timer = cd
	
	var is_plasma = (upgrade_tier >= 3)
	var can_break_steel = is_plasma
	var b_speed = 520.0 if upgrade_tier == 0 else 660.0
	var dmg = 1 + (main.rpg_mgr.atk_bonus if (main and main.rpg_mgr) else 0)
	
	# 开炮后坐力动画与枪口火焰
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	recoil_tween = create_tween()
	recoil_tween.tween_property(sprite, "position", Vector2(0, 4.0), 0.04)
	recoil_tween.tween_property(sprite, "position", Vector2.ZERO, 0.08)

	var muzzle_pos = global_position + facing_direction * 28.0
	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)
	if is_plasma:
		VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)

	if upgrade_tier == 2:
		for offset_x in [-10.0, 10.0]:
			var right_vec = facing_direction.rotated(PI / 2.0)
			var bullet = bullet_scene.instantiate()
			bullet.direction = facing_direction
			bullet.speed = b_speed
			bullet.damage = dmg
			bullet.can_destroy_steel = can_break_steel
			bullet.global_position = global_position + facing_direction * 28.0 + right_vec * offset_x
			bullet.shooter = self
			bullet.shooter_type = "player"
			get_parent().add_child(bullet)
	else:
		var bullet = bullet_scene.instantiate()
		bullet.direction = facing_direction
		bullet.speed = b_speed
		bullet.damage = dmg
		bullet.can_destroy_steel = can_break_steel
		bullet.global_position = muzzle_pos
		bullet.shooter = self
		bullet.shooter_type = "player"
		get_parent().add_child(bullet)
	
	SoundManager.play_shot(get_tree())
	fired_bullet.emit()

func take_damage(amount: int) -> void:
	if is_invulnerable:
		return
	current_health -= amount
	health_changed.emit(player_id, current_health, max_health)

	# 黏土受击挤压形变动画 + 碎屑飞溅
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	hit_tween = create_tween()
	hit_tween.tween_property(sprite, "scale", Vector2(0.24, 0.12), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(sprite, "scale", Vector2(0.15, 0.22), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hit_tween.tween_property(sprite, "scale", Vector2(0.18, 0.18), 0.08).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	hit_tween.parallel().tween_property(sprite, "modulate", Color(2.8, 0.6, 0.6), 0.05)
	hit_tween.chain().tween_property(sprite, "modulate", base_color, 0.08)

	if current_health <= 0:
		_die()

func _die() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		get_parent().add_child(exp_inst)
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	destroyed.emit(player_id)
	queue_free()
