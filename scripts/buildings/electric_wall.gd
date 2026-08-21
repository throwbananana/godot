class_name ElectricWall
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var damage: int = 1
@export var shock_cooldown: float = 0.65

var sprite: Sprite2D
var shock_area: Area2D
var collision_shape: CollisionShape2D

var frames: Array[Texture2D] = []
var cur_frame: int = 0
var anim_timer: float = 0.0
var shock_timers: Dictionary = {} # target_instance_id -> cooldown_remaining

func _ready() -> void:
	add_to_group("electric_wall")
	add_to_group("steel")
	add_to_group("hazard")

	# Load 4 electric animation frames
	for i in range(4):
		var tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_electric_wall_f%d.png" % i)
		if tex:
			frames.append(tex)

	sprite = Sprite2D.new()
	if frames.size() > 0:
		sprite.texture = frames[0]
	sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)
	add_child(sprite)

	# Main Collision Shape (Tank obstacle)
	collision_shape = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(46.0, 46.0)
	collision_shape.shape = box
	add_child(collision_shape)

	# Shock Hazard Area
	shock_area = Area2D.new()
	var area_shape = CollisionShape2D.new()
	var area_box = RectangleShape2D.new()
	area_box.size = Vector2(50.0, 50.0)
	area_shape.shape = area_box
	shock_area.add_child(area_shape)
	add_child(shock_area)

	shock_area.body_entered.connect(_on_shock_body_entered)

func _process(delta: float) -> void:
	# 1. Electric Lightning Animation Loop
	if frames.size() > 0:
		anim_timer += delta
		if anim_timer >= 0.08:
			anim_timer = 0.0
			cur_frame = (cur_frame + 1) % frames.size()
			sprite.texture = frames[cur_frame]

			# Energetic electric flicker
			var flash = 1.0 + randf_range(-0.15, 0.25)
			sprite.modulate = Color(flash, flash * 1.1, flash * 1.3, 1.0)

	# 2. Update shock cooldown timers
	var expired = []
	for k in shock_timers.keys():
		shock_timers[k] -= delta
		if shock_timers[k] <= 0:
			expired.append(k)
	for k in expired:
		shock_timers.erase(k)

	# Check overlapping bodies for continuous contact shock
	if shock_area:
		for body in shock_area.get_overlapping_bodies():
			_try_shock_body(body)

func _on_shock_body_entered(body: Node2D) -> void:
	_try_shock_body(body)

func _try_shock_body(body: Node2D) -> void:
	if not body or not is_instance_valid(body) or body == self:
		return

	# Handle Bullet vaporization
	if body is Bullet or body.is_in_group("bullet"):
		SoundManager.play_shield_hit(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), body.global_position)
		body.queue_free()
		return

	# Handle Tank Shock (Player or Enemy)
	var body_id = body.get_instance_id()
	if shock_timers.has(body_id):
		return

	if body is PlayerTank or body is EnemyTank or body.has_method("take_damage"):
		shock_timers[body_id] = shock_cooldown
		body.take_damage(damage)
		SoundManager.play_shield_hit(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), body.global_position)

		# Light flash in darkness fog
		var main = get_tree().current_scene
		if main and "darkness_fog_instance" in main and main.darkness_fog_instance:
			var local_p = global_position - main.game_area.global_position
			main.darkness_fog_instance.add_flash(local_p, 160.0, 0.3)
