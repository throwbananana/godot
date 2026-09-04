class_name ShieldStation
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_hp: int = 6
@export var recharge_cooldown: float = 6.0
@export var shield_duration: float = 5.0

var current_hp: int = 6
var recharge_timer: float = 6.0
var is_charged: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("shield_station")
	current_hp = max_hp
	recharge_timer = recharge_cooldown
	is_charged = true

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/shield_station.png")
	if tex:
		sprite.texture = tex

	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if is_charged:
		# Rotating high-energy core
		sprite.rotation += delta * 2.2
		var pulse = 0.1875 + sin(Time.get_ticks_msec() * 0.008) * 0.015
		sprite.scale = Vector2(pulse, pulse)
		sprite.modulate = Color(1.0, 1.3, 1.6, 1.0)
	else:
		recharge_timer += delta
		sprite.rotation += delta * 0.6
		sprite.scale = Vector2(0.18, 0.18)
		var progress = clampf(recharge_timer / recharge_cooldown, 0.0, 1.0)
		sprite.modulate = Color(0.4 + 0.6 * progress, 0.4 + 0.6 * progress, 0.6 + 0.4 * progress, 0.6 + 0.4 * progress)

		if recharge_timer >= recharge_cooldown:
			is_charged = true
			SoundManager.play_pickup(get_tree())
			# 充能完成 = 增益可领取, 走上行光点。take_damage() 里挨打那次
			# 仍然是 spawn_shockwave, 两者必须区分开。
			VFXAnimator.spawn_heal_pulse(get_parent(), global_position)
			var tw = create_tween()
			tw.tween_property(sprite, "scale", Vector2(0.24, 0.24), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(sprite, "scale", Vector2(0.1875, 0.1875), 0.10)

func _on_body_entered(body: Node2D) -> void:
	if not is_charged:
		return
	if body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2"):
		_grant_shield_to(body)

func _grant_shield_to(player_body: Node2D) -> void:
	is_charged = false
	recharge_timer = 0.0

	# 赋予无敌护盾
	if player_body.has_method("set_invulnerable"):
		player_body.set_invulnerable(shield_duration)
	
	SoundManager.play_shield_hit(get_tree())
	VFXAnimator.spawn_heal_pulse(get_parent(), global_position)
	VFXAnimator.spawn_heal_pulse(get_parent(), player_body.global_position, 0.85)

	# 充能所震动弹跳特效
	var tw = create_tween()
	tw.tween_property(sprite, "scale", Vector2(0.12, 0.12), 0.10)
	tw.tween_property(sprite, "scale", Vector2(0.18, 0.18), 0.15)

func take_damage(dmg: int) -> void:
	current_hp -= dmg
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	
	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color(3.0, 0.5, 0.5), 0.08)
	tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.12)

	if current_hp <= 0:
		SoundManager.play_explosion(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		queue_free()

func heal(amt: int) -> void:
	current_hp = mini(current_hp + amt, max_hp)
