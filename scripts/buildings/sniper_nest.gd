class_name SniperNest
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_health: int = 8
@export var fire_direction: Vector2 = Vector2.UP
@export var fire_interval: float = 3.2

var current_health: int = 8
var is_destroyed: bool = false
var shoot_timer: float = 0.0

var sprite: Sprite2D
var collision_shape: CollisionShape2D
var explosion_scene: PackedScene
var bullet_scene: PackedScene

func _ready() -> void:
	# 外观差分 (通用战损贴花 + 战区覆盖层)。延迟调用: 有的建筑在 _ready() 里
	# 才创建 sprite / 才按 rpg_mgr 改 max_health, 立即调会读到还没成形的状态。
	BuildingSkin.attach.call_deferred(self)
	add_to_group("building")
	add_to_group("buildings")
	add_to_group("sniper_nest")
	add_to_group("destructible")

	explosion_scene = load("res://scenes/explosion.tscn")
	bullet_scene = load("res://scenes/bullet.tscn")

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/sniper_nest.png")
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

	# 随机微偏移初次射击时间，避免全场碉堡同步齐射
	shoot_timer = randf_range(0.5, fire_interval)
	_update_rotation()

func set_fire_direction(dir: Vector2) -> void:
	fire_direction = dir.normalized()
	_update_rotation()

func _update_rotation() -> void:
	if sprite:
		sprite.rotation = fire_direction.angle() + PI / 2.0

func _process(delta: float) -> void:
	if is_destroyed:
		return
	shoot_timer += delta
	if shoot_timer >= fire_interval:
		shoot_timer = 0.0
		_fire_sniper_round()

func _fire_sniper_round() -> void:
	if not is_inside_tree() or not bullet_scene:
		return
	var main = get_tree().current_scene
	if not main or not ("actors_container" in main) or not main.actors_container:
		return

	var b = bullet_scene.instantiate()
	b.shooter = self
	b.shooter_type = "enemy"
	b.direction = fire_direction
	b.speed = 560.0
	b.damage = 2
	b.position = global_position + fire_direction * 28.0
	main.actors_container.add_child(b)

	if is_inside_tree() and get_tree():
		SoundManager.play_shot(get_tree())
	var p = get_parent()
	if p:
		VFXAnimator.spawn_dust_puff(p, global_position + fire_direction * 24.0)

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health -= amount
	if is_inside_tree() and get_tree():
		SoundManager.play_hit_steel(get_tree())
	var p = get_parent()
	if p:
		# "还能打" 和 "已经没了" 不能是同一张图 —— 活着走崩落, 死了才走碎屑。
		# 见 VFXAnimator.spawn_hit_spall 的注释。
		if current_health > 0:
			VFXAnimator.spawn_hit_spall(p, global_position)
		else:
			VFXAnimator.spawn_clay_debris(p, global_position)

	if sprite:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(3.0, 0.5, 0.5), 0.06)
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
	queue_free()
