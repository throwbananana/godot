class_name Wormhole
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

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

	# 车厢不能自己传送。它的位置每个物理帧都被 leader 的历史路径整段覆写
	# (train_carriage.gd::_physics_process), 所以把一节车厢挪到别处根本不成立 ——
	# 下一帧就被拉回队列里。之前没挡住, 于是车厢压过传送门时会: 在地图另一头白播
	# 一次传送音效和特效、烧掉 2 秒冷却、跑一次 0.12 秒缩到 0.01 的挤压动画,
	# 还顺手清空自己的历史, 把跟在它后面的那节车厢一起打乱。
	# 整列车的传送由机车触发, 见下面的 teleport_train_chain()。
	if "leader_node" in body and is_instance_valid(body.leader_node):
		return

	var is_unit = (body.is_in_group("player") or body.is_in_group("enemies"))
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

				# 整列车一起搬过来, 而不是只处理机车自己。
				#
				# 这里以前是 body.history_positions.clear() 两行, 并不够:
				#   - 清空后 sample_at_distance 拿到空数组会返回 {}, 第一节车厢
				#     那一帧完全不动; 下一帧历史只剩一个点, 它又会精确叠在机车
				#     身上 —— 和当时注释里写的"出现在 leader 正后方"不一样。
				#   - 更要命的是只清了机车。第二节车厢跟的是第一节, 而第一节的
				#     历史里仍然留着"传送前最后一点 -> 传送后第一点"那条跨图线段,
				#     采样时第一条就撞上它, 于是被插值到入口和出口之间的连线上,
				#     穿墙横跨半张地图。问题没修好, 只是从第一节挪到了第二节。
				# teleport_train_chain() 给链上每一节都重铺一条笔直的合成尾迹,
				# 整列车在出口处直接以正确队形成形。
				TrainFollowHelper.teleport_train_chain(body)

				# Exit sound & burst VFX
				SoundManager.play_teleport(get_tree())
				VFXAnimator.spawn_teleport_burst(get_parent(), target_pos)

				# Check warp_drive perk -- duration scales with stacks (base 3.0s,
				# up to +2.1s at 3 stacks via RPGManager's diminishing curve)
				if main and main.rpg_mgr and body.has_method("set_invulnerable") and ("player_id" in body):
					if main.rpg_mgr.has_perk("warp_drive", body.player_id):
						var shield_dur = 3.0 + main.rpg_mgr.get_perk_value("warp_drive", 1.0, body.player_id)
						body.set_invulnerable(shield_dur)
						VFXAnimator.spawn_shockwave(get_parent(), target_pos)

				# Pop-in expansion animation
				var tw_out = create_tween()
				tw_out.tween_property(body, "scale", Vector2(1.20, 1.20), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw_out.tween_property(body, "scale", Vector2(1.0, 1.0), 0.08)
		)
	elif is_bullet:
		body.global_position = target_pos
		SoundManager.play_teleport(get_tree())
		VFXAnimator.spawn_teleport_burst(get_parent(), target_pos)
