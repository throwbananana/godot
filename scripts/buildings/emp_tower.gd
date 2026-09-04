class_name EMPTower
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_health: int = 10
@export var pulse_radius: float = 160.0
@export var pulse_interval: float = 4.5

var current_health: int = 10
var is_destroyed: bool = false
var pulse_timer: float = 0.0

var sprite: Sprite2D
var collision_shape: CollisionShape2D
var explosion_scene: PackedScene

func _ready() -> void:
	# 外观差分 (通用战损贴花 + 战区覆盖层)。延迟调用: 有的建筑在 _ready() 里
	# 才创建 sprite / 才按 rpg_mgr 改 max_health, 立即调会读到还没成形的状态。
	BuildingSkin.attach.call_deferred(self)
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("emp_tower")
	add_to_group("destructible")

	explosion_scene = load("res://scenes/explosion.tscn")

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/emp_tower.png")
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)
	add_child(sprite)

	collision_shape = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(44.0, 44.0)
	collision_shape.shape = box
	add_child(collision_shape)

	var main = get_tree().current_scene if is_inside_tree() else null
	var hp_mult = main.rpg_mgr.get_building_hp_mult() if (main and "rpg_mgr" in main and main.rpg_mgr) else 1.0
	current_health = maxi(1, int(max_health * hp_mult))
	max_health = current_health

func _process(delta: float) -> void:
	if is_destroyed:
		return
	pulse_timer += delta
	if pulse_timer >= pulse_interval:
		pulse_timer = 0.0
		_emit_emp_pulse()

func _emit_emp_pulse() -> void:
	if not is_inside_tree():
		return
	var p = get_parent()
	if p:
		# 断续弧段而不是实心冲击波: 这一下瘫痪的是电子设备, 不是物理推力。
		# destroy() 里那次仍然是 spawn_shockwave —— 塔"被炸掉"和塔"放脉冲"
		# 必须长得不一样, 否则玩家分不清刚才是自己的塔响了还是没了。
		VFXAnimator.spawn_emp_pulse(p, global_position)
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())

	# 视觉脉冲蓝光闪耀
	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(0.2, 2.5, 3.5), 0.1)
		tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.2)

	# 击晕范围内敌人
	var tree = get_tree()
	if tree:
		var enemies = tree.get_nodes_in_group("enemy") + tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Node2D:
				if global_position.distance_to(enemy.global_position) <= pulse_radius:
					if enemy.has_method("stun"):
						enemy.stun(1.2)
					if enemy.has_method("take_damage"):
						enemy.take_damage(1)

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health -= amount
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	var p = get_parent()
	if p:
		# "还能打" 和 "已经没了" 不能是同一张图 —— 活着走崩落, 死了才走碎屑。
		# 见 VFXAnimator.spawn_hit_spall 的注释。
		if current_health > 0:
			VFXAnimator.spawn_hit_spall(p, global_position)
		else:
			VFXAnimator.spawn_clay_debris(p, global_position)

	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(3.0, 0.4, 0.4), 0.06)
		tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.08)

	if current_health <= 0:
		destroy()

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	var p = get_parent()
	if p:
		if explosion_scene:
			var exp_inst = explosion_scene.instantiate()
			p.add_child(exp_inst)
			exp_inst.global_position = global_position
		VFXAnimator.spawn_shockwave(p, global_position)
		VFXAnimator.spawn_clay_debris(p, global_position)
	queue_free()
