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
@export var is_aoe: bool = false
@export var aoe_radius: float = 58.0

var direction: Vector2 = Vector2.UP
var shooter: Node2D = null
var shooter_type: String = "player"
var target: Node2D = null
var homing_relock_timer: float = 0.0
var trail_timer: float = 0.0
var custom_texture_path: String = ""

var is_destroyed: bool = false
var destroyed_bodies: Array[Node2D] = []

# Ricochet Rounds (反射炮弹) shop perk: instead of dying on an obstacle it
# can't break, the bullet picks a new random direction and keeps flying, up
# to bounces_remaining times (one per perk stack). The risk half of the
# trade: once a bullet has ricocheted at least once, it stops treating its
# own shooter as immune (has_bounced gates the shooter-immunity check in
# _on_body_entered), so a reflected round can hit the tank that fired it.
var bounces_remaining: int = 0
var has_bounced: bool = false

# Armor-Piercing Rounds (穿甲弹) shop perk: keeps flying through destructible
# walls (brick/hard_clay, and steel when also can_destroy_steel) instead of
# dying on impact. The risk half: it also stops cancelling enemy bullets on
# contact (see _on_area_entered), so incoming fire that a normal shot would
# have shot down instead sails straight through.
var armor_piercing: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	rotation = direction.angle() + PI / 2.0

	if shooter_type == "player" and is_instance_valid(shooter) and ("player_id" in shooter):
		var main = get_tree().current_scene
		if main and main.rpg_mgr:
			bounces_remaining = main.rpg_mgr.get_perk_stacks("ricochet_rounds", shooter.player_id)
			armor_piercing = main.rpg_mgr.has_perk("armor_piercing_rounds", shooter.player_id)

	var tex_path = "res://assets/sprites/effects/bullet_plasma.png" if can_destroy_steel else "res://assets/sprites/effects/bullet.png"
	if is_homing:
		tex_path = "res://assets/sprites/effects/bullet_missile.png"
	if bounces_remaining > 0:
		tex_path = "res://assets/sprites/effects/bullet_ricochet.png"
	if custom_texture_path != "":
		tex_path = custom_texture_path

	var tex = TextureHelper.get_tex(tex_path)
	if not tex and can_destroy_steel:
		tex = TextureHelper.get_tex("res://assets/sprites/effects/bullet.png")
	if tex and sprite:
		sprite.texture = tex
		if is_homing or is_aoe:
			sprite.scale = Vector2(0.24, 0.24)

## Consumes one bounce and redirects the bullet randomly. Returns false (no
## bounce available) if the caller should fall through to normal destruction.
func _try_ricochet() -> bool:
	if bounces_remaining <= 0:
		return false
	bounces_remaining -= 1
	has_bounced = true
	# Cardinal-only redirect (never a free angle) -- exclude the direction it
	# was just travelling in so a "bounce" always visibly changes course
	# instead of picking a no-op continue-straight result.
	var cardinals: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	cardinals.erase(direction)
	direction = cardinals[randi() % cardinals.size()]
	rotation = direction.angle() + PI / 2.0
	position += direction * 8.0 # nudge clear so it doesn't re-trigger the same collision next tick
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	return true

func _physics_process(delta: float) -> void:
	if is_homing and target and is_instance_valid(target):
		# Re-lock onto whichever cardinal axis currently dominates toward the
		# target on a timer, not every single frame. Re-evaluating every
		# frame still only ever *sets* an exactly-cardinal direction, but a
		# target sitting near the diagonal from the missile flips which axis
		# dominates from one frame to the next, so the position trail traced
		# out over many 1-frame RIGHT/DOWN/RIGHT/DOWN... steps reads as a
		# smooth diagonal line -- the exact "360° missile" bug this is
		# fixing. Committing to a heading for a stretch (like enemy.gd's
		# change_dir_timer) keeps the path a visible staircase of straight
		# segments instead.
		homing_relock_timer -= delta
		if homing_relock_timer <= 0.0:
			homing_relock_timer = 0.3
			var to_target = target.global_position - global_position
			if absf(to_target.y) > absf(to_target.x):
				direction = Vector2.DOWN if to_target.y > 0.0 else Vector2.UP
			else:
				direction = Vector2.RIGHT if to_target.x > 0.0 else Vector2.LEFT
			rotation = direction.angle() + PI / 2.0
		trail_timer += delta
		if trail_timer >= 0.08:
			trail_timer = 0.0
			VFXAnimator.spawn_dust_puff(get_parent(), global_position - direction * 12.0)

	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == shooter and not has_bounced:
		return

	if shooter_type == "player" and (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")):
		# body == shooter only reaches here at all once has_bounced is true
		# (see the early-return above) -- a ricocheted Ricochet Rounds shot
		# can now hit the tank that fired it, which is the whole point of
		# that perk's risk half.
		if body != shooter or has_bounced:
			if body.has_method("stun"):
				body.stun(2.5)
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			var main = get_tree().current_scene if is_inside_tree() else null
			if main and main.has_method("show_toast"):
				var hit_pid = body.player_id if "player_id" in body else 2
				var shoot_pid = shooter.player_id if "player_id" in shooter else 1
				if body == shooter:
					main.show_toast("P%d 被自己的反射炮弹击中！陷入僵直 2.5 秒！" % shoot_pid)
				else:
					main.show_toast("P%d 误击友军 P%d！陷入僵直 2.5 秒！" % [shoot_pid, hit_pid])
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
			if is_aoe:
				_trigger_aoe_explosion()
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_brick(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			if armor_piercing:
				pass # keeps flying straight through -- doesn't consume a ricochet bounce
			elif _try_ricochet():
				pass
			else:
				is_destroyed = true
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
		var pierces_this_steel = armor_piercing and can_destroy_steel and not body.is_in_group("border")
		if not is_destroyed:
			if is_aoe:
				_trigger_aoe_explosion()
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			if pierces_this_steel:
				pass # keeps flying -- doesn't consume a ricochet bounce
			elif _try_ricochet():
				pass
			else:
				is_destroyed = true
				queue_free()
		if can_destroy_steel and not body.is_in_group("border"):
			if not destroyed_bodies.has(body):
				destroyed_bodies.append(body)
				VFXAnimator.spawn_shockwave(get_parent(), body.global_position)
				body.queue_free()
		return
	elif body.is_in_group("border"):
		if not is_destroyed:
			if is_aoe:
				_trigger_aoe_explosion()
			if is_inside_tree() and get_tree():
				SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			# The map boundary always stops a bullet outright, even a piercing
			# one -- ricochet can still save it from dying here, armor-piercing
			# cannot (it only pierces destructible/steel walls, not the edge).
			if not _try_ricochet():
				is_destroyed = true
				queue_free()
		return
	elif (body.is_in_group("enemy") or body.is_in_group("enemies")) and shooter_type == "player":
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion(body)
			if body.has_method("take_damage"):
				body.take_damage(damage)
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return
	elif (body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2")) and shooter_type == "enemy":
		if not is_destroyed:
			is_destroyed = true
			if is_aoe:
				_trigger_aoe_explosion(body)
			if body.has_method("take_damage"):
				body.take_damage(damage)
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
			queue_free()
		return

func _trigger_aoe_explosion(exclude_node: Node = null) -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	var exp_scene = load("res://scenes/explosion.tscn")
	if exp_scene:
		var exp_inst = exp_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position

	# Damage unique targets without duplicate hits. exclude_node is whichever
	# body/area the caller already applied a direct hit to (same group as one
	# of target_groups below) -- without excluding it, that target took the
	# direct damage() call AND the splash-radius damage() call for the same
	# impact, since it's obviously within its own aoe_radius of itself.
	var damaged_nodes: Array[Node] = []
	var target_groups = ["enemies", "enemy"] if shooter_type == "player" else ["player", "p1", "p2"]
	for grp in target_groups:
		for target_node in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(target_node) and target_node is Node2D and target_node != shooter and target_node != exclude_node:
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
			# Armor-piercing rounds don't cancel opposing fire on contact --
			# checked from both sides, since area_entered fires independently
			# on each bullet's own Area2D (this bullet returning early isn't
			# enough if the OTHER bullet's handler still destroys this one).
			if armor_piercing or bool(area.get("armor_piercing")):
				return
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

