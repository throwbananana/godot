class_name Bullet
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal hit_target(target: Node2D)

@export var speed: float = 480.0
@export var damage: int = 1
@export var can_destroy_steel: bool = false
@export var is_homing: bool = false
@export var homing_turn_speed: float = 3.8
@export var is_aoe: bool = false
@export var aoe_radius: float = 58.0

var direction: Vector2 = Vector2.UP
var shooter: Node2D = null
var shooter_type: String = "player"
var target: Node2D = null
var trail_timer: float = 0.0
var custom_texture_path: String = ""

var is_destroyed: bool = false
var destroyed_bodies: Array[Node2D] = []

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	rotation = direction.angle() + PI / 2.0
	
	var tex_path = "res://assets/sprites/effects/bullet_plasma.png" if can_destroy_steel else "res://assets/sprites/effects/bullet.png"
	if is_homing:
		tex_path = "res://assets/sprites/effects/bullet_missile.png"
	if custom_texture_path != "":
		tex_path = custom_texture_path

	var tex = TextureHelper.get_tex(tex_path)
	if not tex and can_destroy_steel:
		tex = TextureHelper.get_tex("res://assets/sprites/effects/bullet.png")
	if tex and sprite:
		sprite.texture = tex
		if is_homing or is_aoe:
			sprite.scale = Vector2(0.24, 0.24)

func _physics_process(delta: float) -> void:
	if is_homing and target and is_instance_valid(target):
		var desired = (target.global_position - global_position).normalized()
		direction = direction.slerp(desired, homing_turn_speed * delta).normalized()
		rotation = direction.angle() + PI / 2.0
		trail_timer += delta
		if trail_timer >= 0.08:
			trail_timer = 0.0
			VFXAnimator.spawn_dust_puff(get_parent(), global_position - direction * 12.0)

	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == shooter:
		return

	if shooter_type == "player" and (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")):
		if body != shooter:
			if body.has_method("stun"):
				body.stun(2.5)
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			var main = get_tree().current_scene if is_inside_tree() else null
			if main and main.has_method("show_toast"):
				var hit_pid = body.player_id if "player_id" in body else 2
				var shoot_pid = shooter.player_id if "player_id" in shooter else 1
				main.show_toast("💫 P%d 误击友军 P%d！陷入僵直 2.5 秒！" % [shoot_pid, hit_pid])
			queue_free()
		return

	if shooter_type == "enemy" and (body.is_in_group("enemy") or body.is_in_group("enemies")):
		return

	if body.is_in_group("brick") or body.is_in_group("hard_clay"):
		if not destroyed_bodies.has(body):
			destroyed_bodies.append(body)
			var effective_damage = damage
			var main = get_tree().current_scene if is_inside_tree() else null
			if main and main.rpg_mgr and shooter_type == "player" and is_instance_valid(shooter) and ("player_id" in shooter):
				if main.rpg_mgr.has_perk("clay_crusher", shooter.player_id):
					effective_damage = 99
			
			if body.has_method("take_hit"):
				body.take_hit(effective_damage)
			else:
				if main:
					if main.has_method("check_key_drop"):
						main.check_key_drop(body, body.global_position)
					if main.has_method("try_spawn_block_loot") and shooter_type == "player":
						main.try_spawn_block_loot(body.global_position)
				VFXAnimator.spawn_dust_puff(get_parent(), body.global_position)
				body.queue_free()
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion()
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_brick(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif body.is_in_group("buildings"):
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion()
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			if shooter_type == "enemy":
				if body.has_method("take_damage"):
					body.take_damage(damage)
				elif can_destroy_steel:
					body.queue_free()
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif body.is_in_group("steel"):
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion()
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		if can_destroy_steel and not body.is_in_group("border"):
			if not destroyed_bodies.has(body):
				destroyed_bodies.append(body)
				VFXAnimator.spawn_shockwave(get_parent(), body.global_position)
				body.queue_free()
		return
	elif body.is_in_group("border"):
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion()
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif (body.is_in_group("enemy") or body.is_in_group("enemies")) and shooter_type == "player":
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion()
			if body.has_method("take_damage"):
				body.take_damage(damage)
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")) and shooter_type == "enemy":
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion()
			if body.has_method("take_damage"):
				body.take_damage(damage)
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return

func _trigger_aoe_explosion() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	var exp_scene = load("res://scenes/explosion.tscn")
	if exp_scene:
		var exp_inst = exp_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position

	# Damage unique targets without duplicate hits
	var damaged_nodes: Array[Node] = []
	var target_groups = ["enemies", "enemy"] if shooter_type == "player" else ["player", "p1", "p2"]
	for grp in target_groups:
		for target_node in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(target_node) and target_node is Node2D and target_node != shooter:
				if not damaged_nodes.has(target_node) and global_position.distance_to(target_node.global_position) <= aoe_radius:
					damaged_nodes.append(target_node)
					if target_node.has_method("take_damage"):
						target_node.take_damage(maxi(1, int(damage * 0.75)))

	for brick in get_tree().get_nodes_in_group("brick"):
		if is_instance_valid(brick) and brick is Node2D:
			if global_position.distance_to(brick.global_position) <= aoe_radius:
				if brick.has_method("take_hit"):
					brick.take_hit(damage)
				else:
					VFXAnimator.spawn_dust_puff(get_parent(), brick.global_position)
					brick.queue_free()

	if can_destroy_steel:
		for steel in get_tree().get_nodes_in_group("steel"):
			if is_instance_valid(steel) and steel is Node2D and not steel.is_in_group("border"):
				if global_position.distance_to(steel.global_position) <= aoe_radius:
					if steel.is_in_group("buildings"):
						if shooter_type == "enemy":
							VFXAnimator.spawn_shockwave(get_parent(), steel.global_position)
							if steel.has_method("take_damage"):
								steel.take_damage(damage)
					else:
						VFXAnimator.spawn_shockwave(get_parent(), steel.global_position)
						steel.queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area == shooter or is_destroyed:
		return
	if area.is_in_group("bullet"):
		if area.shooter_type != shooter_type:
			is_destroyed = true
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			area.queue_free()
			queue_free()
		return
	if area.is_in_group("base") or area.is_in_group("base_eagle"):
		is_destroyed = true
		if is_aoe:
			_trigger_aoe_explosion()
		if area.has_method("destroy"):
			area.destroy()
		elif area.has_method("take_damage_hit"):
			area.take_damage_hit()
		queue_free()
		return
	if area.is_in_group("buildings") and shooter_type == "enemy":
		is_destroyed = true
		if is_aoe:
			_trigger_aoe_explosion()
		if area.has_method("take_damage"):
			area.take_damage(damage)
		VFXAnimator.spawn_clay_debris(get_parent(), global_position)
		queue_free()
		return

