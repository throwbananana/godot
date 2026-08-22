class_name DiamondGem
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

@export var gold_value: int = 60
@export var xp_value: int = 30

var lifetime: float = 30.0
var move_speed: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("collectibles")
	add_to_group("diamond_gem")
	var tex = TextureHelper.get_tex("res://assets/sprites/powerups/diamond_gem.png")
	if tex:
		sprite.texture = tex
	body_entered.connect(_on_body_entered)

	# Initial spawn pop
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.35, 1.35), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.10)

func _physics_process(delta: float) -> void:
	lifetime -= delta

	# Sparkling facet rotation & crystal pulse
	sprite.rotation = sin(Time.get_ticks_msec() * 0.006) * 0.18
	var pulse = 0.1875 + sin(Time.get_ticks_msec() * 0.01) * 0.015
	sprite.scale = Vector2(pulse, pulse)

	# Magnetic pull towards player
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and p is Node2D:
			var main = get_tree().current_scene
			var magnet_dist = 220.0
			if main and main.rpg_mgr:
				magnet_dist += main.rpg_mgr.get_perk_value("magnetic_salvage", 95.0, p.player_id if "player_id" in p else 1)

			var dist = global_position.distance_to(p.global_position)
			if dist < magnet_dist:
				move_speed = move_toward(move_speed, 520.0, 1500.0 * delta)
				var dir = (p.global_position - global_position).normalized()
				position += dir * move_speed * delta
				break

	if lifetime < 5.0:
		modulate.a = 0.4 if int(lifetime * 8.0) % 2 == 0 else 1.0
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2"):
		var main = get_tree().current_scene
		if main:
			var g_val = gold_value + (GameState.current_act - 1) * 20
			if main.rpg_mgr:
				# 同 gold_coin.gd: 车厢在"player"组里却没有 player_id,
				# 直接读会让 magnetic_salvage 加成静默丢失。
				var picker := TrainFollowHelper.resolve_train_owner(body)
				if picker and ("player_id" in picker):
					g_val = int(g_val * (1.0 + main.rpg_mgr.get_perk_value("magnetic_salvage", 0.35, picker.player_id)))
				main.rpg_mgr.add_xp(xp_value)
			if main.has_method("add_gold"):
				main.add_gold(g_val)
			if main.has_method("show_toast"):
				main.show_toast("获得稀有钻石！+%dG & +%d XP！" % [g_val, xp_value])

		SoundManager.play_level_up(get_tree())
		VFXAnimator.spawn_teleport_burst(get_parent(), global_position)
		queue_free()
