class_name MissileStrike
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var team: String = "enemy" # "enemy" or "player"
@export var aim_duration: float = 1.8
@export var damage: int = 3
@export var aoe_radius: float = 68.0

var elapsed: float = 0.0
var is_impacted: bool = false

var reticle_sprite: Sprite2D
var missile_sprite: Sprite2D
var shadow_sprite: Sprite2D
var explosion_scene: PackedScene

func _ready() -> void:
	explosion_scene = load("res://scenes/explosion.tscn")

	# 1. Targeting Reticle
	reticle_sprite = Sprite2D.new()
	var ret_tex = TextureHelper.get_tex("res://assets/sprites/effects/reticle_target.png")
	if ret_tex:
		reticle_sprite.texture = ret_tex
	reticle_sprite.scale = Vector2(0.35, 0.35)
	if team == "enemy":
		reticle_sprite.modulate = Color(2.5, 0.4, 0.3, 0.95)
	else:
		reticle_sprite.modulate = Color(0.3, 2.2, 2.5, 0.95)
	add_child(reticle_sprite)

	# 2. Descending Missile Shadow
	shadow_sprite = Sprite2D.new()
	var mis_tex = TextureHelper.get_tex("res://assets/sprites/powerups/projectile_missile.png")
	if mis_tex:
		shadow_sprite.texture = mis_tex
	shadow_sprite.scale = Vector2(0.05, 0.05)
	shadow_sprite.modulate = Color(0, 0, 0, 0.0)
	add_child(shadow_sprite)

	# 3. Descending Missile Projectile
	missile_sprite = Sprite2D.new()
	if mis_tex:
		missile_sprite.texture = mis_tex
	missile_sprite.scale = Vector2(0.22, 0.22)
	missile_sprite.rotation = PI # Pointing downwards
	missile_sprite.position = Vector2(0, -420.0)
	missile_sprite.visible = false
	add_child(missile_sprite)

	SoundManager.play_shot(get_tree())

func _process(delta: float) -> void:
	if is_impacted:
		return

	elapsed += delta
	var progress = clampf(elapsed / aim_duration, 0.0, 1.0)

	# Reticle shrinks from large (scale ~ 0.55) to locked-on (scale ~ 0.18)
	var r_scale = lerpf(0.55, 0.18, progress)
	var pulse = sin(elapsed * 18.0) * 0.03
	reticle_sprite.scale = Vector2(r_scale + pulse, r_scale + pulse)
	reticle_sprite.rotation += delta * 3.5

	# Flashing alarm tint as it gets closer
	if team == "enemy":
		var flash = 1.0 + sin(elapsed * 24.0) * 0.5
		reticle_sprite.modulate = Color(2.2 * flash, 0.3, 0.2, 0.95)
	else:
		var flash = 1.0 + sin(elapsed * 24.0) * 0.5
		reticle_sprite.modulate = Color(0.2, 2.2 * flash, 2.5 * flash, 0.95)

	# Descending phase (last 0.45s before impact)
	if elapsed >= (aim_duration - 0.45):
		missile_sprite.visible = true
		var plunge_prog = (elapsed - (aim_duration - 0.45)) / 0.45
		missile_sprite.position.y = lerpf(-420.0, 0.0, plunge_prog * plunge_prog)
		
		shadow_sprite.modulate.a = lerpf(0.0, 0.55, plunge_prog)
		shadow_sprite.scale = Vector2(lerpf(0.05, 0.18, plunge_prog), lerpf(0.05, 0.18, plunge_prog))

		if int(elapsed * 30.0) % 2 == 0:
			VFXAnimator.spawn_dust_puff(get_parent(), global_position + missile_sprite.position)

	if elapsed >= aim_duration:
		_detonate()

func _detonate() -> void:
	is_impacted = true
	reticle_sprite.visible = false
	missile_sprite.visible = false
	shadow_sprite.visible = false

	# Spawn explosion & shockwaves
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position

	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	SoundManager.play_explosion(get_tree())

	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.55)

	# AoE Damage Resolution
	if team == "enemy":
		# Hit Players
		for p in get_tree().get_nodes_in_group("player"):
			if is_instance_valid(p) and p is Node2D:
				if global_position.distance_to(p.global_position) <= aoe_radius:
					if p.has_method("take_damage"):
						p.take_damage(damage)

		# Hit Base Eagle
		for b in get_tree().get_nodes_in_group("base_eagle"):
			if is_instance_valid(b) and not b.is_destroyed:
				if global_position.distance_to(b.global_position) <= aoe_radius:
					b.take_damage(damage)

		# Hit Player Defenses
		for d in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(d) and d is Node2D:
				if global_position.distance_to(d.global_position) <= aoe_radius:
					if d.has_method("take_damage"):
						d.take_damage(damage)
	else:
		# Player Strike Hits Enemies
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and e is Node2D:
				if global_position.distance_to(e.global_position) <= aoe_radius:
					if e.has_method("take_damage"):
						e.take_damage(damage + 2)

	# Destroy destructible terrain blocks in radius
	for b in get_tree().get_nodes_in_group("brick"):
		if is_instance_valid(b) and b is Node2D:
			if global_position.distance_to(b.global_position) <= aoe_radius:
				if main and main.has_method("check_key_drop"):
					main.check_key_drop(b, b.global_position)
				if main and main.has_method("try_spawn_block_loot"):
					main.try_spawn_block_loot(b.global_position)
				VFXAnimator.spawn_dust_puff(get_parent(), b.global_position)
				b.queue_free()

	for h in get_tree().get_nodes_in_group("hard_clay"):
		if is_instance_valid(h) and h is Node2D:
			if global_position.distance_to(h.global_position) <= aoe_radius:
				if h.has_method("take_hit"):
					h.take_hit(99)

	get_tree().create_timer(0.4).timeout.connect(queue_free)
