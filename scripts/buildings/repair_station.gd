class_name RepairStation
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@onready var sprite: Sprite2D = $Sprite2D
var heal_timer: float = 0.0
var heal_interval: float = 1.4
var heal_radius: float = 160.0

func _ready() -> void:
	add_to_group("buildings")
	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/repair_station.png")
	if tex: sprite.texture = tex

func _process(delta: float) -> void:
	sprite.rotation += delta * 1.5
	heal_timer += delta
	if heal_timer >= heal_interval:
		heal_timer = 0.0
		_pulse_heal()

func _pulse_heal() -> void:
	# 范围治疗友方坦克与建筑
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and global_position.distance_to(p.global_position) < heal_radius:
			if p.has_method("heal"):
				p.heal(1)
				VFXAnimator.spawn_dust_puff(get_parent(), p.global_position)

	var blds = get_tree().get_nodes_in_group("buildings")
	for b in blds:
		if is_instance_valid(b) and b != self and global_position.distance_to(b.global_position) < heal_radius:
			if b.has_method("heal"):
				b.heal(1)

	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.5, 2.5, 0.8), 0.15)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.25)
