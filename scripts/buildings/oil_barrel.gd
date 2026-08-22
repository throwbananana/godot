class_name OilBarrel
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var blast_radius: float = 76.0 # 3x3 surrounding grid area (1.5 tiles radius)
@export var blast_damage: int = 4

var is_exploded: bool = false
var sprite: Sprite2D
var collision_shape: CollisionShape2D
var explosion_scene: PackedScene

func _ready() -> void:
	add_to_group("oil_barrel")
	add_to_group("destructible")
	add_to_group("obstacle")

	explosion_scene = load("res://scenes/explosion.tscn")

	var tex = TextureHelper.get_tex("res://assets/sprites/buildings/oil_barrel.png")
	sprite = Sprite2D.new()
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(0.1875, 0.1875)
	add_child(sprite)

	collision_shape = CollisionShape2D.new()
	var box = RectangleShape2D.new()
	box.size = Vector2(42.0, 42.0)
	collision_shape.shape = box
	add_child(collision_shape)

	# Initial spawn pop
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func take_damage(_amount: int) -> void:
	detonate()

func take_hit(_amount: int) -> void:
	detonate()

func detonate() -> void:
	if is_exploded:
		return
	is_exploded = true

	# Disable collision immediately
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if sprite:
		sprite.visible = false

	# 1. Spawn Core Fiery Explosion & VFX
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		# 必须先 add_child 再设 global_position。节点还没进场景树时,
		# 它没有父级变换可言, 赋 global_position 等同于赋 position ——
		# 随后挂到 actors_container (在 GameArea 下, 偏移 48,48) 上时那份
		# 偏移又叠了一次, 火球会画到桶的右下方整整一格。同一个函数里的
		# 震波/碎屑/尘土走 VFXAnimator (内部就是先入树再设全局坐标), 伤害
		# 判定的 query.transform 也用的是真全局坐标, 所以错位的只有火球
		# 自己 —— 玩家看到的爆心和实际杀伤范围对不上。见 CLAUDE.md 坐标系一节。
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position

	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)

	# Screen Trauma
	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.55)

	# Light up Night Fog
	if main and "darkness_fog_instance" in main and main.darkness_fog_instance:
		var local_p = global_position - main.game_area.global_position
		main.darkness_fog_instance.add_flash(local_p, 220.0, 0.45)

	# 2. Blast 3x3 Surrounding Grid Objects (Tiles, Blocks, Barrels, Tanks)
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = blast_radius
	query.shape = circle_shape
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var results = space_state.intersect_shape(query, 32)
	for hit in results:
		var collider = hit.get("collider")
		if not collider or not is_instance_valid(collider) or collider == self:
			continue

		# A. Chain detonate adjacent oil barrels
		if collider is OilBarrel or collider.is_in_group("oil_barrel"):
			if collider.has_method("detonate"):
				collider.call_deferred("detonate")
		# B. Chain detonate timed bombs
		elif collider.is_in_group("timed_bomb") and collider.has_method("detonate"):
			collider.call_deferred("detonate")
		# C. Destroy destructible tiles (Brick walls, hard clay, sand dunes)
		#
		# 这里曾经还检查过 is_in_group("trees"), 那是个永远为假的死分支:
		# 树瓦片在 main.gd::_spawn_tile() 里是一个提前 return 的裸 Sprite2D,
		# 没有碰撞体也没有分组, 根本不会出现在 intersect_shape 的结果里。
		# 没有反过来"给树加碰撞", 是因为树的整个存在意义就是可穿行的伪装掩体
		# (z_index=10 画在坦克之上, 靠 _update_tree_transparency 淡出),
		# 给它加碰撞等于把掩体变成墙, 顺带废掉 MIRAGE 的伪装机制。
		elif collider.is_in_group("brick") or collider.is_in_group("hard_clay") or collider.is_in_group("sand_dune"):
			if collider.has_method("take_hit"):
				collider.take_hit(blast_damage)
			elif collider.has_method("take_damage"):
				collider.take_damage(blast_damage)
			else:
				collider.queue_free()
		# D. Deal heavy blast damage to tanks
		elif collider is PlayerTank or collider is EnemyTank or collider.has_method("take_damage"):
			collider.take_damage(blast_damage)
			if collider.has_method("add_trauma"):
				collider.add_trauma(0.35)

	queue_free()
