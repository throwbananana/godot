class_name BaseEagle
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal destroyed

@onready var sprite: Sprite2D = $Sprite2D
var is_destroyed: bool = false

var tex_alive: Texture2D
var tex_damaged: Texture2D
var tex_destroyed: Texture2D
var explosion_scene: PackedScene
var aura_light: PointLight2D = null

func _ready() -> void:
	add_to_group("base_eagle")
	tex_alive = TextureHelper.get_tex("res://assets/sprites/tiles/base_eagle.png")
	tex_damaged = TextureHelper.get_tex("res://assets/sprites/tiles/base_damaged.png")
	tex_destroyed = TextureHelper.get_tex("res://assets/sprites/tiles/base_destroyed.png")
	explosion_scene = load("res://scenes/explosion.tscn")
	if tex_alive:
		sprite.texture = tex_alive
	_setup_aura_light()

func _setup_aura_light() -> void:
	aura_light = PointLight2D.new()
	aura_light.color = Color(1.0, 0.85, 0.45, 0.8)
	aura_light.energy = 0.85
	
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var g_tex = GradientTexture2D.new()
	g_tex.gradient = grad
	g_tex.fill = GradientTexture2D.FILL_RADIAL
	g_tex.fill_from = Vector2(0.5, 0.5)
	g_tex.fill_to = Vector2(0.5, 0.0)
	g_tex.width = 128
	g_tex.height = 128
	
	aura_light.texture = g_tex
	aura_light.texture_scale = 1.6
	add_child(aura_light)
	
	var tw = create_tween().set_loops()
	tw.tween_property(aura_light, "energy", 1.15, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(aura_light, "energy", 0.75, 1.2).set_trans(Tween.TRANS_SINE)

func take_damage_hit() -> void:
	if is_destroyed: return
	if tex_damaged:
		sprite.texture = tex_damaged
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	var tw = create_tween()
	tw.tween_property(sprite, "position", Vector2(randf_range(-4, 4), randf_range(-4, 4)), 0.05)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.05)

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if aura_light and is_instance_valid(aura_light):
		aura_light.queue_free()
	if tex_destroyed:
		sprite.texture = tex_destroyed
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	SoundManager.play_game_over(get_tree())
	destroyed.emit()
