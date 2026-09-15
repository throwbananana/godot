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

## 默认恒为 true (地图 13 号地块和玩家建造的充能站都不受影响)。只有
## main.gd::_spawn_gated_shield_station() 生成的"受电路控制"变体会在没接通
## 电路之前保持 false——充能站本身默认是奖励, 电路要做的是**接通**它,
## 跟 electric_wall 的方向正好相反(那边默认通电, 电路负责切断)。
var is_powered: bool = true

## 电路接通: 直接给到"充能完毕、随时可用"的状态, 而不是接通后还要再等一次
## recharge_cooldown——这是解谜给的即时回报, 不是又一次计时器。
func set_circuit_solved(solved: bool) -> void:
	is_powered = solved
	if solved:
		is_charged = true
		recharge_timer = recharge_cooldown

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	GameState.discover_encyclopedia_entry("bld_shield_station")
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("shield_station")
	current_hp = max_hp
	# is_powered 可能在 add_child() 之前就被 main.gd::_spawn_gated_shield_station()
	# 改成 false 了 (那是纯实例变量赋值, 不需要节点已经在树里, 跟 global_position
	# 那种必须先 add_child 的情况不一样)——这里要认它, 不能无条件把 is_charged
	# 钉回 true, 否则电路型充能站一出生就是可用状态, 电路形同虚设。
	if is_powered:
		recharge_timer = recharge_cooldown
		is_charged = true
	else:
		is_charged = false
		recharge_timer = 0.0

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/shield_station.png")
	if tex:
		sprite.texture = tex

	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if not is_powered:
		# 电路没接通: 彻底静止, 不转、不缩放脉动、不试图回充——跟"正在冷却"
		# (下面 else 分支) 是两码事, 用一套更暗、不带蓝色高光的死气配色区分开,
		# 免得玩家把"电路没解"误读成"刚被人摸过, 等一下就好"。
		sprite.modulate = Color(0.28, 0.28, 0.3, 0.55)
		return
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
	if not is_powered or not is_charged:
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
