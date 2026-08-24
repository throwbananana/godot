class_name FortifiedWall
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_health: int = 3

class Piece extends StaticBody2D:
	var max_health: int = 3
	var current_health: int = 3
	var sprite: Sprite2D
	var explosion_scene: PackedScene

	func _init(p_r: int, p_c: int, p_tex: Texture2D, p_max_hp: int) -> void:
		add_to_group("buildings")
		add_to_group("steel")
		max_health = p_max_hp
		current_health = p_max_hp
		position = Vector2((p_c - 0.5) * 24.0, (p_r - 0.5) * 24.0)

		sprite = Sprite2D.new()
		sprite.texture = p_tex
		sprite.region_enabled = true
		sprite.region_rect = Rect2(p_c * 128.0, p_r * 128.0, 128.0, 128.0)
		sprite.scale = Vector2(0.1875, 0.1875)
		add_child(sprite)

		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(24.0, 24.0)
		col.shape = shape
		add_child(col)

	func _ready() -> void:
		explosion_scene = load("res://scenes/explosion.tscn")

	func heal(amount: int) -> void:
		current_health = mini(current_health + amount, max_health)
		if sprite:
			var tween = create_tween()
			tween.tween_property(sprite, "modulate", Color(0.4, 2.0, 0.6), 0.1)
			tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.1)

	func take_damage(amount: int) -> void:
		current_health -= amount
		SoundManager.play_hit_steel(get_tree())
		if sprite:
			var tween = create_tween()
			tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0), 0.06)
			tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.06)
		if current_health <= 0:
			if explosion_scene:
				var exp_inst = explosion_scene.instantiate()
				var parent_node = get_parent()
				var grandparent = parent_node.get_parent() if parent_node else null
				if grandparent:
					grandparent.add_child(exp_inst)
				elif parent_node:
					parent_node.add_child(exp_inst)
				exp_inst.global_position = global_position
			var spawn_parent = get_parent()
			if spawn_parent:
				VFXAnimator.spawn_clay_debris(spawn_parent.get_parent() if spawn_parent.get_parent() else spawn_parent, global_position)
			queue_free()
			var p_wall = get_parent()
			if p_wall and p_wall.has_method("_check_empty"):
				p_wall.call_deferred("_check_empty")

func _ready() -> void:
	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/fortified_wall.png")
	var main = get_tree().current_scene
	var hp_mult = main.rpg_mgr.get_building_hp_mult() if (main and main.rpg_mgr) else 1.0
	var final_hp = maxi(1, int(max_health * hp_mult))

	for r in range(2):
		for c in range(2):
			var piece = Piece.new(r, c, tex, final_hp)
			add_child(piece)

func _check_empty() -> void:
	var pieces_left = 0
	for child in get_children():
		if child is Piece and not child.is_queued_for_deletion():
			pieces_left += 1
	if pieces_left == 0:
		queue_free()

func destroy() -> void:
	for child in get_children():
		if child is Piece:
			child.queue_free()
	queue_free()

func heal(amount: int) -> void:
	for child in get_children():
		if child.has_method("heal"):
			child.heal(amount)
