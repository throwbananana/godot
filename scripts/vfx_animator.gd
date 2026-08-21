class_name VFXAnimator
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")

@export var frame_textures: Array[Texture2D] = []
@export var fps: float = 16.0
@export var is_looping: bool = false
@export var auto_destroy: bool = true

var current_frame: int = 0
var timer: float = 0.0
var sprite: Sprite2D

func _ready() -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	if frame_textures.size() > 0:
		sprite.texture = frame_textures[0]

func _process(delta: float) -> void:
	if frame_textures.is_empty():
		return
	
	timer += delta
	var frame_dur = 1.0 / fps
	if timer >= frame_dur:
		timer -= frame_dur
		current_frame += 1
		if current_frame >= frame_textures.size():
			if is_looping:
				current_frame = 0
			else:
				if auto_destroy:
					queue_free()
				return
		sprite.texture = frame_textures[current_frame]

const SelfScript = preload("res://scripts/vfx_animator.gd")

static func create_anim(tree_parent: Node, pos: Vector2, paths: Array[String], scale_factor: float = 0.1875, fps_val: float = 16.0, rot: float = 0.0) -> Node2D:
	var node = SelfScript.new()
	node.rotation = rot
	node.fps = fps_val
	node.scale = Vector2(scale_factor, scale_factor)
	for p in paths:
		var tex = TextureHelper.get_tex(p)
		if tex:
			node.frame_textures.append(tex)
	tree_parent.add_child(node)
	node.global_position = pos
	return node

static func spawn_muzzle_flash(parent: Node, pos: Vector2, rot: float) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/muzzle_flash_0.png",
		"res://assets/sprites/effects/muzzle_flash_1.png",
		"res://assets/sprites/effects/muzzle_flash_2.png",
		"res://assets/sprites/effects/muzzle_flash_3.png",
		"res://assets/sprites/effects/muzzle_flash_4.png",
		"res://assets/sprites/effects/muzzle_flash_5.png"
	]
	create_anim(parent, pos, paths, 0.1875, 24.0, rot)

static func spawn_clay_debris(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/clay_debris_0.png",
		"res://assets/sprites/effects/clay_debris_1.png",
		"res://assets/sprites/effects/clay_debris_2.png",
		"res://assets/sprites/effects/clay_debris_3.png",
		"res://assets/sprites/effects/clay_debris_4.png",
		"res://assets/sprites/effects/clay_debris_5.png"
	]
	create_anim(parent, pos, paths, 0.1875, 18.0)

static func spawn_dust_puff(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/dust_puff_0.png",
		"res://assets/sprites/effects/dust_puff_1.png",
		"res://assets/sprites/effects/dust_puff_2.png",
		"res://assets/sprites/effects/dust_puff_3.png",
		"res://assets/sprites/effects/dust_puff_4.png",
		"res://assets/sprites/effects/dust_puff_5.png"
	]
	create_anim(parent, pos, paths, 0.1875, 18.0)

static func spawn_shockwave(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/shockwave_0.png",
		"res://assets/sprites/effects/shockwave_1.png",
		"res://assets/sprites/effects/shockwave_2.png",
		"res://assets/sprites/effects/shockwave_3.png",
		"res://assets/sprites/effects/shockwave_4.png",
		"res://assets/sprites/effects/shockwave_5.png"
	]
	create_anim(parent, pos, paths, 0.25, 16.0)
