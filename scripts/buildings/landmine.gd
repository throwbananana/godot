class_name Landmine
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@onready var sprite: Sprite2D = $Sprite2D
var explosion_scene: PackedScene
var is_triggered: bool = false

func _ready() -> void:
	add_to_group("buildings")
	explosion_scene = load("res://scenes/explosion.tscn")
	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/landmine.png")
	if tex: sprite.texture = tex
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# 微光脉冲呼吸
	sprite.modulate.a = 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25

func _on_body_entered(body: Node2D) -> void:
	if is_triggered:
		return
	if body.is_in_group("enemies"):
		is_triggered = true
		sprite.modulate = Color(3.0, 0.2, 0.2)
		get_tree().create_timer(0.12).timeout.connect(_detonate)

func _detonate() -> void:
	var parent = get_parent()
	if explosion_scene and parent:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.scale = Vector2(1.5, 1.5)
		parent.add_child(exp_inst)
		exp_inst.global_position = global_position
	VFXAnimator.spawn_shockwave(parent, global_position)
	VFXAnimator.spawn_clay_debris(parent, global_position)

	# 范围巨大杀伤敌军
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) < 90.0:
			if e.has_method("take_damage"):
				e.take_damage(99)

	# 摧毁周围砖块与非边界铁墙
	var space_state = get_world_2d().direct_space_state
	if space_state:
		var shape = CircleShape2D.new()
		shape.radius = 70.0
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, global_position)
		query.collision_mask = 1 | 2 | 16
		query.collide_with_bodies = true

		var results = space_state.intersect_shape(query, 16)
		for res in results:
			var collider = res.get("collider")
			if not collider or not is_instance_valid(collider) or collider == self:
				continue
			if collider.is_in_group("brick"):
				VFXAnimator.spawn_dust_puff(parent, collider.global_position)
				collider.queue_free()
			elif collider.is_in_group("steel") and not collider.is_in_group("border"):
				VFXAnimator.spawn_shockwave(parent, collider.global_position)
				collider.queue_free()

	SoundManager.play_explosion(get_tree())
	queue_free()
