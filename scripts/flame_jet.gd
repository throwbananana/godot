class_name FlameJet
extends Node2D

## 喷火坦克的持续火舌 —— 一直朝正前方喷, 范围伤害。
##
## 为什么做成"车体的子节点"而不是像 laser_piercer.gd 那样每次开火生成一个独立
## 节点: 火舌是*持续*存在的, 而且必须永远贴在喷嘴上跟着车体转。挂成子节点后
## 位置和旋转由父节点的变换自动带着走, 完全不需要每帧同步坐标 —— 也就顺便
## 绕开了这个项目里踩过两次的坑 (laser_piercer 把局部坐标当全局、传送落点差
## 一整格, 见 CLAUDE.md 的坐标系一节)。
##
## 与其它敌人的区别在于*counterplay*而不是数值: 别的敌人都是打一发躲一下,
## 这个的正面是一条持续的死亡区域, 玩家必须绕侧面。所以射程刻意做短 (2.75 格),
## 绕过去才是可行解; 做长了就变成"隔着半张地图秒人"的数值怪。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

const RANGE: float = 132.0          # 2.75 格 —— 短到可以绕开
const MUZZLE_OFFSET: float = 30.0   # 喷嘴到车体中心的距离
const TICK_INTERVAL: float = 0.30   # 伤害结算间隔
const DAMAGE: float = 1.0
const FRAME_FPS: float = 14.0

## 沿火舌轴线的采样点。半径随距离变宽, 复刻锥形的判定范围。
## 用一串圆而不是一个矩形: 矩形会让"贴着火舌边缘擦过去"也吃满伤害,
## 一串由窄到宽的圆更接近玩家看到的形状。
const SAMPLES: int = 6
const R_NEAR: float = 11.0
const R_FAR: float = 30.0

var is_burning: bool = false
var shooter: Node2D = null

var _frames: Array[Texture2D] = []
var _frame_idx: int = 0
var _anim_t: float = 0.0
var _tick_t: float = 0.0
var _sprite: Sprite2D = null


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.z_index = 20          # 压在坦克之上
	add_child(_sprite)

	for i in range(4):
		var tex = TextureHelper.get_tex("res://assets/sprites/effects/vfx_flame_f%d.png" % i)
		if tex:
			_frames.append(tex)
	if _frames.size() > 0:
		_sprite.texture = _frames[0]

	# 火舌沿本地 +Y 向"前"。坦克精灵是朝上绘制的 (rotation = 朝向角 + PI/2),
	# 所以在父节点的本地空间里, 前方是 -Y —— 精灵要转 180 度, 并把中心放在
	# 喷嘴与射程末端的中点上。
	_sprite.rotation = PI
	_sprite.position = Vector2(0, -(MUZZLE_OFFSET + RANGE * 0.5))
	# 贴图 256px 高, 拉伸到实际射程长度; 横向按火舌宽度收一点
	_sprite.scale = Vector2(0.30, RANGE / 256.0)
	_sprite.visible = false


func set_burning(on: bool) -> void:
	if is_burning == on:
		return
	is_burning = on
	if _sprite:
		_sprite.visible = on
	if not on:
		_tick_t = 0.0


func _process(delta: float) -> void:
	if not is_burning or _frames.is_empty() or not _sprite:
		return
	_anim_t += delta * FRAME_FPS
	if _anim_t >= 1.0:
		_anim_t = 0.0
		_frame_idx = (_frame_idx + 1) % _frames.size()
		_sprite.texture = _frames[_frame_idx]


func _physics_process(delta: float) -> void:
	if not is_burning:
		return
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK_INTERVAL
	_apply_damage()


func _apply_damage() -> void:
	if not is_inside_tree():
		return
	var space = get_world_2d().direct_space_state
	if not space:
		return

	# 本地 -Y 就是车体正前方 (见 _ready 里的说明)
	var dir: Vector2 = Vector2.UP.rotated(global_rotation)
	var origin: Vector2 = global_position + dir * MUZZLE_OFFSET

	var already: Array[Node] = []
	for i in range(SAMPLES):
		var t := float(i) / float(SAMPLES - 1)
		var pos: Vector2 = origin + dir * (RANGE * t)
		var radius: float = lerpf(R_NEAR, R_FAR, t)

		var shape := CircleShape2D.new()
		shape.radius = radius
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = shape
		q.transform = Transform2D(0.0, pos)
		# 1 = 地形/玩家/鹰巢/建筑, 16 = 建筑与平台。不查 2 (敌人) —— 火焰不伤友军。
		q.collision_mask = 1 | 16
		q.collide_with_bodies = true
		q.collide_with_areas = true

		for res in space.intersect_shape(q, 8):
			var body = res.get("collider")
			if not body or not is_instance_valid(body) or body == shooter or already.has(body):
				continue
			already.append(body)
			_burn(body, pos)


func _burn(body: Node, at: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	# 往上找一层能承载 VFX 的容器 —— 火焰挂在坦克身上, 特效不能也挂在坦克身上,
	# 否则坦克一死特效跟着消失。
	var vfx_parent: Node = parent.get_parent() if parent.get_parent() else parent

	if body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2"):
		if body.has_method("take_damage"):
			body.take_damage(DAMAGE)
		VFXAnimator.spawn_clay_debris(vfx_parent, at)
	elif body.is_in_group("base") or body.is_in_group("base_eagle"):
		if body.has_method("destroy"):
			body.destroy()
		elif body.has_method("take_damage_hit"):
			body.take_damage_hit()
	elif body.is_in_group("buildings") or body.is_in_group("building"):
		# 有墙属性的建筑 (防御炮台/加固墙/电墙) 同时在 steel 组, 烧不动 ——
		# 和 bullet.gd 对 steel 的处理保持一致。
		if not body.is_in_group("steel") and body.has_method("take_damage"):
			body.take_damage(DAMAGE)
	elif body.is_in_group("brick"):
		# 烧穿砖墙 —— 这是喷火兵独有的战场改造能力: 它会把掩体烧没, 逼玩家换位。
		# hard_clay 同时在 brick 组但能扛 3 下, 走 take_hit 而不是直接删,
		# 与 bullet.gd 的处理一致。
		if body.has_method("take_hit"):
			body.take_hit(1)
		else:
			VFXAnimator.spawn_dust_puff(vfx_parent, body.global_position)
			body.queue_free()
