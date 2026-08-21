class_name Wormhole
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

var cooldowns: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var trigger_area: Area2D = $TriggerArea

func _ready() -> void:
	add_to_group("wormholes")
	var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_wormhole.png")
	if tex and sprite:
		sprite.texture = tex
		sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)

	if trigger_area:
		trigger_area.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# Continuous cosmic vortex rotation
	if sprite:
		sprite.rotation += delta * 1.6
		var pulse = sin(Time.get_ticks_msec() * 0.006) * 0.20
		sprite.modulate = Color(1.0 + pulse * 0.3, 0.95 + pulse * 0.1, 1.2 + pulse * 0.4)

	# Update teleport cooldowns
	var finished_ids: Array = []
	for id in cooldowns.keys():
		cooldowns[id] -= delta
		if cooldowns[id] <= 0.0:
			finished_ids.append(id)
	for id in finished_ids:
		cooldowns.erase(id)

func _on_body_entered(body: Node2D) -> void:
	if not is_instance_valid(body) or body == self:
		return

	var body_id = body.get_instance_id()
	if cooldowns.has(body_id) and cooldowns[body_id] > 0.0:
		return

	var is_unit = (body.is_in_group("player") or body.is_in_group("enemies") or body.is_in_group("player_carriage"))
	var is_bullet = body.is_in_group("bullet") or body.is_in_group("bullets") or ("shooter" in body)

	if not is_unit and not is_bullet:
		return

	# Put on cooldown
	cooldowns[body_id] = 2.0

	var main = get_tree().current_scene
	var target_pos = Vector2.ZERO
	if main and main.has_method("get_random_empty_tile_position"):
		target_pos = main.get_random_empty_tile_position()
	else:
		target_pos = Vector2(randf_range(100.0, 500.0), randf_range(100.0, 500.0))

	# 1. Sound & Entrance VFX
	SoundManager.play_teleport(get_tree())
	VFXAnimator.spawn_wormhole_swirl(get_parent(), global_position)

	if is_unit:
		# 2. Implosion squeeze animation
		var tw = create_tween()
		tw.tween_property(body, "scale", Vector2(0.01, 0.01), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if is_instance_valid(body):
				body.global_position = target_pos
				
				# Exit sound & burst VFX
				SoundManager.play_teleport(get_tree())
				VFXAnimator.spawn_teleport_burst(get_parent(), target_pos)

				# Check warp_drive perk
				if main and main.rpg_mgr and body.has_method("set_invulnerable") and ("player_id" in body):
					if main.rpg_mgr.has_perk("warp_drive", body.player_id):
						body.set_invulnerable(3.0)
						VFXAnimator.spawn_shockwave(get_parent(), target_pos)

				# Pop-in expansion animation
				var tw_out = create_tween()
				tw_out.tween_property(body, "scale", Vector2(1.20, 1.20), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw_out.tween_property(body, "scale", Vector2(1.0, 1.0), 0.08)

				# Reposition follower train carriages if applicable
				if "attached_carriages" in body and body.attached_carriages is Array:
					for idx in range(body.attached_carriages.size()):
						var c = body.attached_carriages[idx]
						if is_instance_valid(c):
							c.global_position = target_pos - body.facing_direction * (32.0 * float(idx + 1))
		)
	elif is_bullet:
		body.global_position = target_pos
		SoundManager.play_teleport(get_tree())
		VFXAnimator.spawn_teleport_burst(get_parent(), target_pos)
