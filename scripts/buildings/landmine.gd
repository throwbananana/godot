class_name Landmine
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

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
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		exp_inst.scale = Vector2(1.5, 1.5)
		get_parent().add_child(exp_inst)

	# 范围巨大杀伤
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) < 90.0:
			if e.has_method("take_damage"):
				e.take_damage(99)

	SoundManager.play_explosion(get_tree())
	queue_free()
