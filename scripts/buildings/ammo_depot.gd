class_name AmmoDepot
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_health: int = 6
var current_health: int = 6
var is_destroyed: bool = false

var sprite: Sprite2D
var collision_shape: CollisionShape2D
var explosion_scene: PackedScene

func _ready() -> void:
	# 外观差分 (通用战损贴花 + 战区覆盖层)。延迟调用: 有的建筑在 _ready() 里
	# 才创建 sprite / 才按 rpg_mgr 改 max_health, 立即调会读到还没成形的状态。
	BuildingSkin.attach.call_deferred(self)
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("ammo_depot")
	add_to_group("destructible")

	explosion_scene = load("res://scenes/explosion.tscn")

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/ammo_depot.png")
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

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health -= amount
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	var p = get_parent()
	if p:
		VFXAnimator.spawn_clay_debris(p, global_position)

	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(3.0, 1.8, 0.2), 0.06)
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

		# 弹药库殉爆向四周释放破片冲击
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			VFXAnimator.spawn_dust_puff(p, global_position + dir * 32.0)
			VFXAnimator.spawn_clay_debris(p, global_position + dir * 24.0)

	# 尝试对周围 72px 范围内的敌人造成殉爆伤害
	var tree = get_tree()
	if tree:
		for enemy in tree.get_nodes_in_group("enemy") + tree.get_nodes_in_group("enemies"):
			if is_instance_valid(enemy) and enemy is Node2D:
				if global_position.distance_to(enemy.global_position) <= 72.0:
					if enemy.has_method("take_damage"):
						enemy.take_damage(3)

	queue_free()
