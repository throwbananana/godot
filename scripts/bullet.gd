class_name Bullet
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

@export var speed: float = 460.0
@export var damage: int = 1

var direction: Vector2 = Vector2.UP
var shooter: Node2D = null
var shooter_type: String = "player"

var explosion_scene: PackedScene

func _ready() -> void:
	explosion_scene = load("res://scenes/explosion.tscn")
	var tex = TextureHelper.get_tex("res://assets/sprites/effects/bullet.png")
	var spr = get_node_or_null("Sprite2D")
	if spr and tex:
		spr.texture = tex
	rotation = direction.angle() + PI / 2.0
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _spawn_explosion(is_small: bool = false) -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		exp_inst.global_position = global_position
		if is_small:
			exp_inst.scale = Vector2(0.5, 0.5)
		get_parent().add_child(exp_inst)

func _on_area_entered(area: Area2D) -> void:
	if area is Bullet:
		if area.shooter_type != shooter_type:
			_spawn_explosion(true)
			area.queue_free()
			queue_free()
			return
	
	if area.is_in_group("base_eagle"):
		if area.has_method("destroy"):
			area.destroy()
		_spawn_explosion()
		queue_free()
		return

func _on_body_entered(body: Node2D) -> void:
	if body == shooter:
		return
	
	if body.is_in_group("player") and shooter_type == "enemy":
		if body.has_method("take_damage"):
			body.take_damage(damage)
		_spawn_explosion()
		queue_free()
		return
	
	if body.is_in_group("enemies") and shooter_type == "player":
		if body.has_method("take_damage"):
			body.take_damage(damage)
		_spawn_explosion()
		queue_free()
		return
	
	if body.is_in_group("brick"):
		SoundManager.play_hit_brick(get_tree())
		_spawn_explosion(true)
		body.queue_free()
		queue_free()
		return
	
	if body.is_in_group("steel"):
		SoundManager.play_hit_steel(get_tree())
		_spawn_explosion(true)
		queue_free()
		return
	
	if body.is_in_group("border"):
		_spawn_explosion(true)
		queue_free()
		return
