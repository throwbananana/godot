class_name SignalJammerTower
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_hp: int = 5
@export var jam_radius: float = 150.0

var current_hp: int = 5
var dish_spin: float = 0.0

# Bodies currently inside the jam field, tracked so a tower destroyed
# mid-overlap can explicitly release anyone it's still holding jammed --
# otherwise a player caught inside when the tower dies never gets an
# exit signal and stays permanently jam_overlap_count > 0.
var jammed_bodies: Array[Node2D] = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var dish: Sprite2D = $DishSprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var jam_area: Area2D = $JamArea
@onready var jam_shape: CollisionShape2D = $JamArea/CollisionShape2D

func _ready() -> void:
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("signal_jammer")
	current_hp = max_hp

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/signal_jammer_tower.png")
	if tex and sprite:
		sprite.texture = tex
	var dish_tex = TextureHelper.get_tex("res://assets/sprites/buildings/signal_jammer_dish.png")
	if dish_tex and dish:
		dish.texture = dish_tex

	if jam_shape and jam_shape.shape is CircleShape2D:
		(jam_shape.shape as CircleShape2D).radius = jam_radius

	if jam_area:
		jam_area.body_entered.connect(_on_jam_area_entered)
		jam_area.body_exited.connect(_on_jam_area_exited)

	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _process(delta: float) -> void:
	dish_spin += delta * 2.2
	if dish:
		dish.rotation = dish_spin
	# Warning pulse tied to jam-field occupancy so it's visually obvious the
	# field is live and currently affecting someone
	if jammed_bodies.size() > 0 and sprite:
		var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.02) * 0.5
		sprite.modulate = Color(1.0 + pulse * 0.6, 1.0, 1.0, 1.0)
	elif sprite:
		sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_jam_area_entered(body: Node2D) -> void:
	if is_instance_valid(body) and body.has_method("on_enter_jam"):
		body.on_enter_jam()
		if not jammed_bodies.has(body):
			jammed_bodies.append(body)
		SoundManager.play_pickup(get_tree())

func _on_jam_area_exited(body: Node2D) -> void:
	if is_instance_valid(body) and body.has_method("on_exit_jam"):
		body.on_exit_jam()
	jammed_bodies.erase(body)

func take_damage(amount: int) -> void:
	current_hp -= amount
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var tw = create_tween()
	tw.tween_property(sprite, "position", Vector2(randf_range(-3, 3), randf_range(-3, 3)), 0.04)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.04)

	if current_hp <= 0:
		_destroy()

func take_hit(amount: int) -> void:
	take_damage(amount)

func _destroy() -> void:
	# Release anyone still standing in the field when the tower dies --
	# without this a player caught inside would never get on_exit_jam() and
	# would stay stuck with reversed controls for the rest of the battle.
	for body in jammed_bodies:
		if is_instance_valid(body) and body.has_method("on_exit_jam"):
			body.on_exit_jam()
	jammed_bodies.clear()

	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	queue_free()
