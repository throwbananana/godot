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
@export var base_speed: float = 125.0
@export var fire_cooldown: float = 0.65

var upgrade_tier: int = 0
var max_health: int = 1
var current_health: int = 1
var can_fire: bool = true
var fire_timer: float = 0.0
var facing_direction: Vector2 = Vector2.UP
var is_invulnerable: bool = false
var invulnerable_timer: float = 0.0
var regen_accumulator: float = 0.0
var is_on_sand: bool = false
var sand_overlap_count: int = 0
var is_on_ice: bool = false
var ice_overlap_count: int = 0
var is_on_platform: bool = false
var slide_direction: Vector2 = Vector2.ZERO
var ice_particle_timer: float = 0.0
var is_stunned: bool = false
var stun_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shield_sprite: Sprite2D = $ShieldSprite

var tank_frames: Array[Texture2D] = []
var current_frame: int = 0

var shield_textures: Array[Texture2D] = []
var shield_frame: int = 0

var bullet_scene: PackedScene
var explosion_scene: PackedScene
var carriage_scene: PackedScene
var attached_carriages: Array[Node2D] = []

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
		base_color = Color(1.0, 1.0, 1.0)

	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	carriage_scene = load("res://scenes/train_carriage.tscn")
	
	for i in range(8):
		var s_tex = TextureHelper.get_tex("res://assets/sprites/effects/shield_bubble_%d.png" % i)
		if s_tex:
			shield_textures.append(s_tex)
	if shield_sprite:
		shield_sprite.scale = Vector2(0.24, 0.24)
		if shield_textures.size() > 0:
			shield_sprite.texture = shield_textures[0]

	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		main.rpg_mgr.branch_changed.connect(_on_branch_changed)

	_apply_rpg_stats()
	_update_tier_appearance()
	set_invulnerable(3.5)

func _on_branch_changed(changed_player_id: int, _branch: String, _tier: int) -> void:
	if changed_player_id != player_id:
		return
	_apply_rpg_stats()
	_update_tier_appearance()

func _apply_rpg_stats() -> void:
	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		var prev_max = max_health
		max_health = main.rpg_mgr.get_player_max_hp(player_id)
		if current_health > max_health or max_health > prev_max:
			current_health = max_health
		health_changed.emit(player_id, current_health, max_health)

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(player_id, current_health, max_health)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.3, 2.2, 0.6), 0.1)
	tween.tween_property(sprite, "modulate", base_color, 0.1)

func _update_tier_appearance() -> void:
	var main = get_tree().current_scene
	var branch = "default"
	var b_tier = 0
	if main and main.rpg_mgr:
		branch = main.rpg_mgr.get_branch(player_id)
		b_tier = main.rpg_mgr.get_branch_tier(player_id)
	elif player_id == 1:
		branch = GameState.tank_branch
		b_tier = GameState.branch_tier
	else:
		branch = GameState.p2_branch
		b_tier = GameState.p2_branch_tier

	var prefix = ""
	var p_prefix = "player" if player_id == 1 else "player2"

	if branch == "speed":
		_clear_train_carriages()
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_speed_%s" % [p_prefix, t_str]
	elif branch == "heavy":
		_clear_train_carriages()
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_heavy_%s" % [p_prefix, t_str]
	elif branch == "train":
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_train_loco_%s" % [p_prefix, t_str]
		_sync_train_carriages(b_tier)
	else:
		_clear_train_carriages()
		prefix = "%s_tier%d" % [p_prefix, upgrade_tier]

	tank_frames.clear()
	for i in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [prefix, i])
		if tex:
			tank_frames.append(tex)
	if tank_frames.size() > 0 and sprite:
		sprite.texture = tank_frames[0]
		sprite.modulate = base_color

func _sync_train_carriages(b_tier: int) -> void:
	if not carriage_scene or not is_inside_tree():
		return

	# Remove dead carriages
	var valid_carriages: Array[Node2D] = []
	for c in attached_carriages:
		if is_instance_valid(c):
			valid_carriages.append(c)
	attached_carriages = valid_carriages

	# First carriage: Turret Wagon
	if attached_carriages.size() == 0:
		var c1 = carriage_scene.instantiate()
		get_parent().add_child(c1)
		c1.setup(self, "turret", false)
		attached_carriages.append(c1)

	# Second carriage (Tier 2): Rocket Artillery Wagon
	if b_tier >= 2 and attached_carriages.size() == 1:
		var c2 = carriage_scene.instantiate()
		get_parent().add_child(c2)
		c2.setup(attached_carriages[0], "rocket", false)
		attached_carriages.append(c2)

func _clear_train_carriages() -> void:
	for c in attached_carriages:
		if is_instance_valid(c):
			c.queue_free()
	attached_carriages.clear()

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
		PowerUp.Type.MISSILE:
			var strike_scene = load("res://scenes/missile_strike.tscn")
			if strike_scene:
				var enemies = get_tree().get_nodes_in_group("enemies")
				var targets: Array[Vector2] = []
				for e in enemies:
					if is_instance_valid(e) and e is Node2D:
						targets.append(e.global_position)
				if targets.size() == 0:
					targets.append(global_position + facing_direction * 180.0)

				# Call 3 tactical missile strikes on enemy clusters
				for i in range(mini(3, max(1, targets.size()))):
					var strike = strike_scene.instantiate()
					strike.team = "player"
					strike.aim_duration = 1.4
					strike.damage = 5
					get_parent().add_child(strike)
					strike.global_position = targets[i % targets.size()] + Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
			powerup_collected.emit("[%s] 🚀 战术导弹群空袭支援！" % p_name)
		PowerUp.Type.TIMED_BOMB:
			var bomb_scene = load("res://scenes/timed_bomb.tscn")
			if bomb_scene:
				# Deploys 2 linked bombs ahead in facing direction
				for offset in [32.0, 72.0]:
					var bomb = bomb_scene.instantiate()
					bomb.team = "player"
					bomb.countdown = 2.0
					bomb.blast_range = 4 # Extended 4-tile blast for powerup!
					bomb.damage = 5
					get_parent().add_child(bomb)
					bomb.global_position = global_position + facing_direction * offset
			SoundManager.play_build(get_tree())
			powerup_collected.emit("[%s] 💣 强化十字连环定时炸弹！" % p_name)

func set_invulnerable(duration: float) -> void:
	is_invulnerable = true
	invulnerable_timer = duration
	if shield_sprite:
		shield_sprite.visible = true

func stun(duration: float = 2.5) -> void:
	if is_invulnerable:
		return
	is_stunned = true
	stun_timer = duration
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)

func _physics_process(delta: float) -> void:
	if is_stunned:
		stun_timer -= delta
		# Dizzy vibration & yellow electric stun flash
		sprite.rotation = sin(Time.get_ticks_msec() * 0.04) * 0.20
		sprite.modulate = Color(2.5, 2.5, 0.4, 1.0) if int(stun_timer * 10.0) % 2 == 0 else Color(1.0, 1.0, 0.5, 1.0)
		velocity = Vector2.ZERO
		move_and_slide()
		if stun_timer <= 0.0:
			is_stunned = false
			sprite.rotation = facing_direction.angle() + PI / 2.0
			sprite.modulate = base_color
		return

	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		var regen = main.rpg_mgr.get_regen_rate(player_id)
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
	
	var speed_mult = 1.0
	var is_speed_branch = (main and main.rpg_mgr and main.rpg_mgr.get_branch(player_id) == "speed")

	if main and main.rpg_mgr:
		speed_mult *= main.rpg_mgr.get_speed_multiplier(player_id)
	else:
		speed_mult *= (1.0 + float(upgrade_tier) * 0.12)

	# Sand slow resistance for speed branch / nitro booster perk
	if is_on_sand:
		if is_speed_branch or (main and main.rpg_mgr and main.rpg_mgr.has_perk("nitro_booster", player_id)):
			speed_mult *= 0.90 # Minimal sand drag
		else:
			speed_mult *= 0.50 # Normal sand drag

	var current_speed = base_speed * speed_mult

	var has_frost_cleats = (main and main.rpg_mgr and main.rpg_mgr.has_perk("frost_cleats", player_id))

	if is_on_ice and not has_frost_cleats:
		# Slipper ice physics: input steers slide direction; releasing input keeps sliding uncontrollably!
		if input_vec != Vector2.ZERO:
			facing_direction = input_vec
			slide_direction = input_vec
			velocity = input_vec * (current_speed * 1.30)
			rotation = facing_direction.angle() + PI / 2.0
		elif slide_direction != Vector2.ZERO:
			velocity = slide_direction * (current_speed * 1.30)
			rotation = slide_direction.angle() + PI / 2.0
			
			ice_particle_timer += delta
			if ice_particle_timer >= 0.08:
				ice_particle_timer = 0.0
				if is_inside_tree() and get_parent():
					VFXAnimator.spawn_dust_puff(get_parent(), global_position - slide_direction * 14.0)
		else:
			velocity = Vector2.ZERO

		if tank_frames.size() > 0 and velocity.length_squared() > 0.0:
			var f_idx = int(Time.get_ticks_msec() / 60) % tank_frames.size()
			if f_idx != current_frame:
				current_frame = f_idx
				sprite.texture = tank_frames[current_frame]
	else:
		slide_direction = Vector2.ZERO
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

	# Hitting a solid obstacle stops ice sliding
	if is_on_ice and get_slide_collision_count() > 0:
		slide_direction = Vector2.ZERO

	if Input.is_action_pressed(act_fire) and can_fire:
		_shoot()

func _shoot() -> void:
	if not bullet_scene:
		return
	var main = get_tree().current_scene
	var branch: String
	var b_tier: int
	if main and main.rpg_mgr:
		branch = main.rpg_mgr.get_branch(player_id)
		b_tier = main.rpg_mgr.get_branch_tier(player_id)
	elif player_id == 1:
		branch = GameState.tank_branch
		b_tier = GameState.branch_tier
	else:
		branch = GameState.p2_branch
		b_tier = GameState.p2_branch_tier

	var cd = fire_cooldown
	if main and main.rpg_mgr:
		cd *= main.rpg_mgr.get_fire_cooldown_mult(player_id)
	cd = maxf(0.18 if branch == "speed" else 0.32, cd)
	can_fire = false
	fire_timer = cd

	var dmg = main.rpg_mgr.get_atk_damage(player_id) if (main and main.rpg_mgr) else 1
	if is_on_platform and main and main.rpg_mgr and main.rpg_mgr.has_perk("ferry_artillery", player_id):
		dmg = int(dmg * 1.5)
	var muzzle_pos = global_position + facing_direction * 28.0

	# 开炮后坐力动画与枪口火焰
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	recoil_tween = create_tween()
	recoil_tween.tween_property(sprite, "position", Vector2(0, 4.0), 0.03)
	recoil_tween.tween_property(sprite, "position", Vector2.ZERO, 0.06)

	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)

	match branch:
		"speed":
			# High speed needle cannons
			var b_speed = 720.0
			if b_tier >= 2:
				# Triple needle fan shot
				for ang_deg in [-10.0, 0.0, 10.0]:
					var shot_dir = facing_direction.rotated(deg_to_rad(ang_deg))
					var bullet = bullet_scene.instantiate()
					bullet.direction = shot_dir
					bullet.speed = b_speed
					bullet.damage = dmg
					bullet.shooter = self
					bullet.shooter_type = "player"
					get_parent().add_child(bullet)
					bullet.global_position = muzzle_pos
			else:
				# Dual needle shot
				for offset_x in [-8.0, 8.0]:
					var right_vec = facing_direction.rotated(PI / 2.0)
					var bullet = bullet_scene.instantiate()
					bullet.direction = facing_direction
					bullet.speed = b_speed
					bullet.damage = dmg
					bullet.shooter = self
					bullet.shooter_type = "player"
					get_parent().add_child(bullet)
					bullet.global_position = muzzle_pos + right_vec * offset_x

		"heavy":
			# Massive Heavy Siege Mortar with AoE splash & screen shake
			VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
			var bullet = bullet_scene.instantiate()
			bullet.direction = facing_direction
			bullet.speed = 460.0
			bullet.damage = dmg # get_atk_damage() already folds in the heavy-branch bonus
			bullet.is_aoe = true
			bullet.aoe_radius = 64.0 if b_tier <= 1 else 84.0
			bullet.can_destroy_steel = (b_tier >= 2)
			bullet.shooter = self
			bullet.shooter_type = "player"
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos
			if main and main.has_method("add_trauma"):
				main.add_trauma(0.18)

		"train":
			# Heavy Train Locomotive Forward Cannon
			var bullet = bullet_scene.instantiate()
			bullet.direction = facing_direction
			bullet.speed = 580.0
			bullet.damage = dmg + 1 + b_tier
			bullet.can_destroy_steel = (b_tier >= 2)
			bullet.shooter = self
			bullet.shooter_type = "player"
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos

		_:
			# Default classical tiers
			var is_plasma = (upgrade_tier >= 3)
			var can_break_steel = is_plasma
			var b_speed = 520.0 if upgrade_tier == 0 else 660.0
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
					bullet.shooter = self
					bullet.shooter_type = "player"
					get_parent().add_child(bullet)
					bullet.global_position = global_position + facing_direction * 28.0 + right_vec * offset_x
			else:
				var bullet = bullet_scene.instantiate()
				bullet.direction = facing_direction
				bullet.speed = b_speed
				bullet.damage = dmg
				bullet.can_destroy_steel = can_break_steel
				bullet.shooter = self
				bullet.shooter_type = "player"
				get_parent().add_child(bullet)
				bullet.global_position = muzzle_pos

	SoundManager.play_shot(get_tree())
	fired_bullet.emit()

func take_damage(amount: int) -> void:
	if is_invulnerable:
		SoundManager.play_shield_hit(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
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
	for c in attached_carriages:
		if is_instance_valid(c):
			c.queue_free()
	attached_carriages.clear()

	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	destroyed.emit(player_id)
	queue_free()

func on_enter_sand() -> void:
	sand_overlap_count += 1
	is_on_sand = true

func on_exit_sand() -> void:
	sand_overlap_count = max(0, sand_overlap_count - 1)
	is_on_sand = (sand_overlap_count > 0)

func on_enter_ice() -> void:
	ice_overlap_count += 1
	is_on_ice = true
	slide_direction = facing_direction

func on_exit_ice() -> void:
	ice_overlap_count = max(0, ice_overlap_count - 1)
	is_on_ice = (ice_overlap_count > 0)
	if not is_on_ice:
		slide_direction = Vector2.ZERO
