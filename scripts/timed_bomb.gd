class_name TimedBomb
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var team: String = "enemy" # "enemy" or "player"
@export var countdown: float = 2.4
@export var blast_range: int = 3 # 3 tiles cross blast
@export var damage: int = 3

var elapsed: float = 0.0
var is_exploded: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var explosion_scene: PackedScene
var flame_beam_tex: Texture2D

func _ready() -> void:
	add_to_group("timed_bomb")
	add_to_group("destructible")
	explosion_scene = load("res://scenes/explosion.tscn")
	flame_beam_tex = TextureHelper.get_tex("res://assets/sprites/effects/flame_cross_beam.png")

	var bomb_tex = TextureHelper.get_tex("res://assets/sprites/buildings/prop_timed_bomb.png")
	if bomb_tex and sprite:
		sprite.texture = bomb_tex
		sprite.scale = Vector2(0.20, 0.20)

	body_entered.connect(_on_body_entered)

	# Initial spawn pop
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _physics_process(delta: float) -> void:
	if is_exploded:
		return

	elapsed += delta
	var remaining = countdown - elapsed

	# Breathing pulse animation (speeds up as timer nears zero!)
	var freq = lerpf(8.0, 26.0, clampf(elapsed / countdown, 0.0, 1.0))
	var pulse = 0.20 + sin(elapsed * freq) * 0.035
	if sprite:
		sprite.scale = Vector2(pulse, pulse)
		if remaining < 1.0:
			sprite.modulate = Color(2.5, 0.3, 0.3, 1.0) if int(elapsed * 18.0) % 2 == 0 else Color(1.0, 1.0, 1.0, 1.0)

	# Sizzling fuse smoke
	if int(elapsed * 20.0) % 3 == 0:
		VFXAnimator.spawn_dust_puff(get_parent(), global_position + Vector2(0, -18.0))

	if elapsed >= countdown:
		detonate()

func take_damage(_amount: int) -> void:
	# Trigger instant chain explosion when shot or blasted!
	if not is_exploded:
		detonate()

func take_hit(_amount: int) -> void:
	if not is_exploded:
		detonate()

func _on_body_entered(body: Node2D) -> void:
	if body is Bullet:
		detonate()

func detonate() -> void:
	if is_exploded:
		return
	is_exploded = true
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if sprite:
		sprite.visible = false

	# 1. Central Core Explosion
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position

	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	SoundManager.play_explosion(get_tree())

	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.55)

	# 2. Bomberman 4-Way Cross Flame Propagation (UP, DOWN, LEFT, RIGHT)
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for dir in directions:
		_propagate_flame_arm(dir)

	get_tree().create_timer(0.5).timeout.connect(queue_free)

func _propagate_flame_arm(dir: Vector2) -> void:
	var tile_step = 48.0
	for step in range(1, blast_range + 1):
		var target_pos = global_position + dir * (step * tile_step)

		# Spawn fiery flame beam sprite
		_spawn_flame_vfx(target_pos, dir.angle() + PI / 2.0)

		# Hit check at this tile
		var should_stop = _resolve_flame_impact(target_pos)
		if should_stop:
			break

func _spawn_flame_vfx(pos: Vector2, rot: float) -> void:
	var f_sprite = Sprite2D.new()
	if flame_beam_tex:
		f_sprite.texture = flame_beam_tex
	f_sprite.rotation = rot
	f_sprite.scale = Vector2(0.24, 0.24)
	f_sprite.modulate = Color(2.5, 1.8, 0.8, 1.0)
	f_sprite.z_index = 45
	get_parent().add_child(f_sprite)
	f_sprite.global_position = pos

	VFXAnimator.spawn_shockwave(get_parent(), pos)

	var tw = f_sprite.create_tween()
	tw.tween_property(f_sprite, "scale", Vector2(0.28, 0.28), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(f_sprite, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(f_sprite.queue_free)

func _resolve_flame_impact(pos: Vector2) -> bool:
	var stop_flame = false
	var hit_radius = 24.0
	var main = get_tree().current_scene

	# Check Steel Walls -- 炸得开, 但地图边界永远炸不开。
	#
	# 钢墙原来只是挡住火焰而不被摧毁, 但**地雷是炸得掉的** ——
	# 四个爆炸源各写了一套地形判定, 于是 40G 的地雷能拆钢墙, 60G 的定时炸弹
	# 和 90G 的导弹反而不能。玩家看到的就是"这个炸弹炸得掉那个炸不掉"。
	# 现在统一成"爆炸物都能开钢墙", 见 tools/test_explosive_terrain_matrix.gd。
	#
	# border 组必须排除: 地图四周的边界墙也在 steel 组里, 炸穿了坦克就能开
	# 出地图外面。它仍然挡火焰, 只是不消失。
	for s in get_tree().get_nodes_in_group("steel"):
		if is_instance_valid(s) and s is Node2D:
			if pos.distance_to(s.global_position) <= hit_radius:
				if s.is_in_group("buildings"):
					# 玩家自建的炮塔/强化墙同时也在 steel 组里(为了扛住普通
					# 子弹), 不能被这条"钢墙统一炸得开"规则当无血量地形直接
					# 删掉。跟 missile_strike.gd 一样按 team 免友伤: 玩家自己
					# 的定时炸弹伤不到自己的建筑, 只有敌方炸弹会真的扣血。
					if team == "enemy" and s.has_method("take_damage"):
						VFXAnimator.spawn_shockwave(get_parent(), s.global_position)
						s.take_damage(damage)
				elif not s.is_in_group("border"):
					VFXAnimator.spawn_shockwave(get_parent(), s.global_position)
					s.queue_free()
				stop_flame = true

	# Check Bricks (destroys and stops flame)
	for b in get_tree().get_nodes_in_group("brick"):
		if is_instance_valid(b) and b is Node2D:
			if pos.distance_to(b.global_position) <= hit_radius:
				if main and main.has_method("check_key_drop"):
					main.check_key_drop(b, b.global_position)
				if main and main.has_method("try_spawn_block_loot"):
					main.try_spawn_block_loot(b.global_position)
				VFXAnimator.spawn_dust_puff(get_parent(), b.global_position)
				b.queue_free()
				stop_flame = true

	# Check Hard Clay
	for h in get_tree().get_nodes_in_group("hard_clay"):
		if is_instance_valid(h) and h is Node2D:
			if pos.distance_to(h.global_position) <= hit_radius:
				if h.has_method("take_hit"):
					h.take_hit(99)
				stop_flame = true

	# Check Other Timed Bombs (Chain Reaction!)
	for tb in get_tree().get_nodes_in_group("timed_bomb"):
		if is_instance_valid(tb) and tb != self and tb is Node2D:
			if pos.distance_to(tb.global_position) <= hit_radius:
				if tb.has_method("detonate"):
					tb.detonate()

	# Check Players
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node2D:
			if pos.distance_to(p.global_position) <= hit_radius:
				if p.has_method("take_damage"):
					p.take_damage(damage)

	# Check Enemies
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e is Node2D:
			if pos.distance_to(e.global_position) <= hit_radius:
				if e.has_method("take_damage"):
					e.take_damage(damage + (2 if team == "player" else 0))

	# Check Base Eagle
	for be in get_tree().get_nodes_in_group("base_eagle"):
		if is_instance_valid(be) and not be.is_destroyed:
			if pos.distance_to(be.global_position) <= hit_radius:
				be.take_damage_hit()

	return stop_flame
