class_name LaserRingCutter
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const GameState = preload("res://scripts/game_state.gd")

## 壕沟战激光环形切割光刃 (Laser Ring Cutter)
## 
## 核心机制：
## 1. 往前方向短距离释放高频环形激光光刃，环形高速旋转扫过前方扇区。
## 2. 切割等级与当前炮弹破坏等级严格相等：
##    - 普通破坏等级 (can_destroy_steel == false): 瞬间切割粉碎砖块、硬泥、木墙、滑轮墙等普通障碍。
##    - 破钢破坏等级 (can_destroy_steel == true):  高能等离子环刃直接贯穿切碎钢铁掩体与防御建筑！
## 3. 切割拦截炮弹 (Bullet Slicing):
##    - 扫荡路径上碰到的一切敌方来袭炮弹均被瞬间切碎消散并迸发陶泥火花，形成极佳的近身攻防一体屏障！
## 4. 单位伤害与击退：
##    - 命中敌方单位造成强力切割伤害与短距后坐击退。

@export var team: String = "player" # "player" or "enemy"
@export var damage: int = 2
@export var can_destroy_steel: bool = false
@export var cutting_radius: float = 44.0
@export var duration: float = 0.26

var shooter: Node2D = null
var facing_direction: Vector2 = Vector2.UP
var elapsed: float = 0.0
var initial_offset: float = 34.0

var sprite: Sprite2D = null
var aura_light: PointLight2D = null
var col_shape: CollisionShape2D = null
var damaged_nodes: Array[Node] = []
var destroyed_blocks: Array[Node] = []
var cut_bullets: Array[Node] = []

static func create_cut(parent: Node, origin_pos: Vector2, direction: Vector2, shooter_node: Node2D, team_str: String, dmg: int, break_steel: bool, radius: float = 44.0) -> Node2D:
	if not parent or not is_instance_valid(parent):
		return null

	var scene: PackedScene = load("res://scenes/laser_ring_cutter.tscn")
	var cutter = scene.instantiate() if scene else null
	if not cutter:
		return null

	cutter.team = team_str
	cutter.damage = dmg
	cutter.can_destroy_steel = break_steel
	cutter.cutting_radius = radius
	cutter.shooter = shooter_node
	cutter.facing_direction = direction.normalized()
	cutter.global_position = origin_pos + cutter.facing_direction * cutter.initial_offset

	parent.add_child(cutter)
	SoundManager.play_laser(parent.get_tree())
	var main = parent.get_tree().current_scene if (parent.is_inside_tree() and parent.get_tree()) else null
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.18)

	return cutter

func _ready() -> void:
	add_to_group("laser_cutter")
	add_to_group("laser_ring_cutter")

	# 1. 物理碰撞形状
	col_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col_shape:
		col_shape = CollisionShape2D.new()
		add_child(col_shape)
	var circle = CircleShape2D.new()
	circle.radius = cutting_radius
	col_shape.shape = circle

	# 2. 视觉环形激光刀刃精灵
	sprite = Sprite2D.new()
	var tex = TextureHelper.get_tex("res://assets/sprites/effects/laser_ring_cutter.png")
	if tex:
		sprite.texture = tex
	
	# 初始极小，高速膨胀
	sprite.scale = Vector2(0.2, 0.2)
	if team == "player":
		# 我方高频超导青蓝/等离子白色能量环
		sprite.modulate = Color(0.4, 2.2, 2.6, 1.0)
	else:
		# 敌方猩红琥珀高热激光切割刃
		sprite.modulate = Color(2.6, 0.9, 0.35, 1.0)
	add_child(sprite)

	# 3. 动态光照
	aura_light = PointLight2D.new()
	aura_light.color = Color(0.35, 0.85, 1.0, 1.0) if team == "player" else Color(1.0, 0.45, 0.2, 1.0)
	aura_light.energy = 1.4
	var grad = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var gtex = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 128
	gtex.height = 128
	aura_light.texture = gtex
	add_child(aura_light)

	# 启动即刻执行首轮碰撞结算
	_perform_slice_sweep()

func _process(delta: float) -> void:
	elapsed += delta

	# 跟随战车车头移动
	if is_instance_valid(shooter):
		global_position = shooter.global_position + facing_direction * initial_offset

	# 视觉动画：高速旋转与膨胀消散
	if sprite:
		sprite.rotation += delta * 28.0
		var progress = clampf(elapsed / duration, 0.0, 1.0)
		var target_scale = (cutting_radius * 2.2) / 256.0
		var cur_scale = lerpf(0.25, target_scale, ease(progress, 0.4))
		sprite.scale = Vector2(cur_scale, cur_scale)
		sprite.modulate.a = 1.0 - (progress * progress)

	if aura_light:
		aura_light.energy = maxf(0.0, 1.4 * (1.0 - (elapsed / duration)))

	# 持续多帧切割检测（拦截在切割持续期内飞入的子弹或冲入的敌人）
	_perform_slice_sweep()

	if elapsed >= duration:
		queue_free()

func _perform_slice_sweep() -> void:
	if not is_inside_tree():
		return
	var tree = get_tree()
	if not tree:
		return
	var parent_node = get_parent() if get_parent() else self
	var main = tree.current_scene

	# =========================================================================
	# A. 切割拦截敌对炮弹 (Bullet Slicing)
	# =========================================================================
	for b in tree.get_nodes_in_group("bullet"):
		if not is_instance_valid(b) or b in cut_bullets:
			continue
		if "is_destroyed" in b and b.is_destroyed:
			continue
		var b_team = str(b.get("shooter_type"))
		if b_team != team:
			if global_position.distance_to(b.global_position) <= cutting_radius + 12.0:
				cut_bullets.append(b)
				b.set("is_destroyed", true)
				VFXAnimator.spawn_clay_debris(parent_node, b.global_position)
				VFXAnimator.spawn_dust_puff(parent_node, b.global_position)
				SoundManager.play_hit_steel(tree)
				b.queue_free()

	# 拦截引爆敌对定时炸弹
	for tb in tree.get_nodes_in_group("timed_bomb"):
		if not is_instance_valid(tb) or tb in cut_bullets:
			continue
		var tb_team = str(tb.get("team"))
		if tb_team != team:
			if global_position.distance_to(tb.global_position) <= cutting_radius + 8.0:
				cut_bullets.append(tb)
				if tb.has_method("detonate"):
					tb.detonate()
				else:
					tb.queue_free()

	# =========================================================================
	# B. 切割地形与方块 (Terrain Slicing) - 切割等级与当前炮弹等级相等
	# =========================================================================
	var slice_candidates = ["brick", "hard_clay", "wooden_wall", "roller_wall", "oil_barrel", "street_lamp"]
	for grp in slice_candidates:
		for block in tree.get_nodes_in_group(grp):
			if not is_instance_valid(block) or block in destroyed_blocks:
				continue
			if global_position.distance_to(block.global_position) <= cutting_radius + 6.0:
				destroyed_blocks.append(block)
				if block.has_method("take_hit"):
					block.take_hit(damage)
				elif block.has_method("take_damage"):
					block.take_damage(damage)
				else:
					if main and main.has_method("try_spawn_block_loot") and team == "player":
						main.try_spawn_block_loot(block.global_position)
					VFXAnimator.spawn_dust_puff(parent_node, block.global_position)
					block.queue_free()

	# 破钢等级切割高阶钢墙与防御建筑
	if can_destroy_steel:
		for steel in tree.get_nodes_in_group("steel"):
			if not is_instance_valid(steel) or steel in destroyed_blocks:
				continue
			if steel.is_in_group("border"):
				continue
			if global_position.distance_to(steel.global_position) <= cutting_radius + 6.0:
				destroyed_blocks.append(steel)
				VFXAnimator.spawn_shockwave(parent_node, steel.global_position)
				if steel.has_method("destroy"):
					steel.destroy()
				elif steel.has_method("take_damage"):
					steel.take_damage(999)
				else:
					steel.queue_free()

		for bld in tree.get_nodes_in_group("buildings"):
			if not is_instance_valid(bld) or bld in destroyed_blocks:
				continue
			if bld.is_in_group("border"):
				continue
			if global_position.distance_to(bld.global_position) <= cutting_radius + 6.0:
				destroyed_blocks.append(bld)
				VFXAnimator.spawn_shockwave(parent_node, bld.global_position)
				if bld.has_method("take_damage"):
					bld.take_damage(damage)
				elif bld.has_method("destroy"):
					bld.destroy()
				else:
					bld.queue_free()

	# =========================================================================
	# C. 切割伤害单位 (Unit Slicing)
	# =========================================================================
	if team == "player":
		# 伤害敌方坦克与车厢
		for target_grp in ["enemy", "enemies"]:
			for e in tree.get_nodes_in_group(target_grp):
				if not is_instance_valid(e) or e in damaged_nodes or e == shooter:
					continue
				if global_position.distance_to(e.global_position) <= cutting_radius + 8.0:
					damaged_nodes.append(e)
					if e.has_method("take_damage"):
						e.take_damage(damage)
					VFXAnimator.spawn_clay_debris(parent_node, e.global_position)
					# 轻度战壕冲击击退
					if "global_position" in e:
						e.global_position += facing_direction * 14.0

	else:
		# 敌方切割光刃伤害玩家
		for p in tree.get_nodes_in_group("player"):
			if not is_instance_valid(p) or p in damaged_nodes or p == shooter:
				continue
			if global_position.distance_to(p.global_position) <= cutting_radius + 8.0:
				damaged_nodes.append(p)
				if p.has_method("take_damage"):
					p.take_damage(damage)
				VFXAnimator.spawn_clay_debris(parent_node, p.global_position)
				if "global_position" in p:
					p.global_position += facing_direction * 14.0

		# 敌方切割伤害基地老鹰（检查友军标识旗）
		for be in tree.get_nodes_in_group("base_eagle"):
			if not is_instance_valid(be) or be in damaged_nodes:
				continue
			if global_position.distance_to(be.global_position) <= cutting_radius + 10.0:
				damaged_nodes.append(be)
				if be.has_method("take_damage_hit"):
					be.take_damage_hit()
				elif be.has_method("destroy"):
					be.destroy()
