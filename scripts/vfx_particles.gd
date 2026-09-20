class_name VFXParticles
extends Node2D

## 运行时粒子层 —— 这个项目原先**没有**粒子系统。
##
## 在这之前, "粒子效果"全部是 VFXAnimator: 一个 Sprite2D 翻六帧预渲染图然后
## 自毁。那是一张会动的**图章**, 不是粒子 —— 每颗碎片的轨迹在 Blender 里就
## 烤死了, 所以同一个效果每次出现都逐像素相同, 碎片也不可能朝着"这一发子弹
## 打来的方向"飞。本文件补的就是这一层: 每颗粒子有自己的速度、重力、阻力、
## 自旋和淡出, 由运行时积分。
##
## 两层是互补的, 不是替代关系。翻书那层继续负责"有明确造型语义"的东西
## (冲击波环、EMP 弧段、建造收束), 因为那些形状是设计出来的, 不是模拟出来的;
## 粒子层负责"一堆小东西按物理散开"的部分。
##
## --- 渲染方式 ---
## 整发粒子只占**一个 CanvasItem**: 所有粒子在本节点的 _draw() 里画,
## 而不是每颗一个 Sprite2D 节点。N 个 Sprite2D 意味着 N 个节点 + N 个
## CanvasItem + N 次变换传播, 一发 24 颗的碎片就是 24 个节点; 本项目刚做过
## 一轮性能修复 (见 CLAUDE.md "卡顿" 一节), 不该在这里把它吐回去。
##
## --- 确定性 ---
## 绝不用 randf()。每日挑战在 start_game() 里 seed() 了全局 RNG 流并依赖它
## 全程确定, 而粒子每帧都在生成 —— 从那条流里抽数会让所有人的当日局面分叉。
## 这里用**自带种子的局部 RandomNumberGenerator**, 种子来自一个静态计数器,
## 和 explosion.gd 轮换爆炸变体、SoundManager 轮换噪声变体是同一条规矩。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SelfScript = preload("res://scripts/vfx_particles.gd")

## 同屏粒子总量上限。超出之后新的发射会被拒绝 —— 宁可少一团碎屑, 也不要在
## 连环爆炸时掉帧: 粒子是纯表现, 丢掉不影响任何判定。
##
## 420 这个数是这么定的: 正常战斗同屏大约 50~150 颗 (一发 4~11 颗, 同时活着
## 的发数有限), 所以上限只在极端连环爆炸时才会碰到, 日常观感不受影响。
## 积分开销实测每颗远小于 1us (900 颗时净增 0.17ms/帧), 真正没法在这里量的是
## **绘制成本** —— headless 不渲染, _draw() 根本不会被调用 (见 CLAUDE.md
## "卡顿" 一节的同一条告诫)。所以这里取一个保守值: 把最坏情况的绘制量压到
## 一半, 而正常游玩根本碰不到这条线。要调高的话, 请在**带窗口**的构建里
## 量过 draw 成本之后再动。
const GLOBAL_MAX_PARTICLES := 420
static var _live_particles: int = 0

## 发射序号, 用来给每一发派一个种子。静态计数器而不是 randi(), 理由见文件头。
static var _burst_counter: int = 0

const ATOM_CHUNK_A := "res://assets/sprites/effects/particle_clay_chunk_a.png"
const ATOM_CHUNK_B := "res://assets/sprites/effects/particle_clay_chunk_b.png"
const ATOM_CHUNK_C := "res://assets/sprites/effects/particle_clay_chunk_c.png"
const ATOM_SPARK := "res://assets/sprites/effects/particle_spark.png"
const ATOM_EMBER := "res://assets/sprites/effects/particle_ember.png"
const ATOM_SMOKE := "res://assets/sprites/effects/particle_smoke.png"

## 预设表。**两端跑的是同一份常量**, 所以联机回声只需要发预设名 + 少量参数,
## 客户端用同一个种子重放就能得到逐颗一致的结果。
##
## 这看起来像 CLAUDE.md 反复警告的"名字 -> 效果映射表会烂掉", 但不是同一回事:
## 那条警告针对的是**平行维护的第二张表** (一边加效果、另一边忘了补)。这里只有
## 一张表, 主机和客户端读的是同一个 const, 新加一个预设两端同时就有了。
##
##   cone       发射锥半角 (弧度)。PI 表示各向同性
##   speed      初速范围 px/s
##   gravity    每秒加速度 (正 y 向下)
##   drag       每秒速度保留比例 (0.1 = 每秒剩 10%)
##   size       屏幕尺寸范围 (px), 按原子贴图的短边折算
##   life       存活时间范围 (秒)
##   spin       自旋角速度范围 (弧度/秒)
##   grow       尺寸随寿命的变化 (1.0 恒定, >1 膨胀, <1 收缩)
##   align_vel  true = 贴图朝向跟着速度方向走 (火星专用: 细长体要顺着飞)
const PRESETS := {
	# 撞击火星: 沿撞击法线反向喷出的一小撮热屑, 快、短命、无重力感。
	"impact_spark": {
		"atoms": [ATOM_SPARK],
		"count": [5, 9], "cone": 0.62, "speed": [190.0, 340.0],
		"gravity": 0.0, "drag": 0.04, "size": [7.0, 11.0],
		"life": [0.16, 0.30], "spin": [0.0, 0.0], "grow": 0.55, "align_vel": true,
	},
	# 碎块: 有重量的黏土屑, 受重力、落地前减速、自旋。
	"debris": {
		"atoms": [ATOM_CHUNK_A, ATOM_CHUNK_B, ATOM_CHUNK_C],
		"count": [6, 11], "cone": 1.05, "speed": [90.0, 210.0],
		"gravity": 520.0, "drag": 0.35, "size": [6.0, 11.0],
		"life": [0.40, 0.72], "spin": [-9.0, 9.0], "grow": 0.9, "align_vel": false,
	},
	# 余烬: 爆炸后向上飘散的火点, 反重力 + 强阻力。
	"ember": {
		"atoms": [ATOM_EMBER],
		"count": [7, 12], "cone": 3.15, "speed": [40.0, 130.0],
		"gravity": -80.0, "drag": 0.25, "size": [5.0, 9.0],
		"life": [0.45, 0.85], "spin": [-3.0, 3.0], "grow": 0.6, "align_vel": false,
	},
	# 余烟: 慢、膨胀、长命。爆炸和建筑残骸之后留在原地的那口气。
	"smoke": {
		"atoms": [ATOM_SMOKE],
		"count": [4, 7], "cone": 3.15, "speed": [12.0, 40.0],
		"gravity": -26.0, "drag": 0.5, "size": [12.0, 20.0],
		"life": [0.7, 1.25], "spin": [-1.2, 1.2], "grow": 1.9, "align_vel": false,
	},
}

# --- 粒子状态 (并行数组, 不是每颗一个对象) ---
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _life := PackedFloat32Array()
var _life0 := PackedFloat32Array()
var _size := PackedFloat32Array()
var _atom := PackedInt32Array()

var _textures: Array[Texture2D] = []
var _gravity: float = 0.0
var _drag: float = 0.0
var _grow: float = 1.0
var _align_vel: bool = false

func _ready() -> void:
	# 粒子画在角色之上、树冠之下。树冠是 z_index 10 且刻意盖住坦克
	# (见 CLAUDE.md "Trees conceal, but must not erase"), 碎屑盖过树冠会
	# 把那层遮蔽关系拆掉。
	z_index = 9

func _process(delta: float) -> void:
	var n := _pos.size()
	if n == 0:
		queue_free()
		return

	# 阻力用"每秒保留比例"而不是线性减速: 线性减速在低速时会把速度拉成负数,
	# 碎片会倒着飞回来。pow 形式对任意 delta 都稳定, 也不依赖帧率。
	var keep := pow(_drag, delta) if _drag > 0.0 else 1.0

	var i := 0
	while i < n:
		var life: float = _life[i] - delta
		if life <= 0.0:
			# 交换删除: 粒子之间没有绘制顺序要求, 不需要保序, 省一次 O(n) 移位。
			var last := n - 1
			_pos[i] = _pos[last]; _vel[i] = _vel[last]
			_rot[i] = _rot[last]; _spin[i] = _spin[last]
			_life[i] = _life[last]; _life0[i] = _life0[last]
			_size[i] = _size[last]; _atom[i] = _atom[last]
			_pos.resize(last); _vel.resize(last); _rot.resize(last); _spin.resize(last)
			_life.resize(last); _life0.resize(last); _size.resize(last); _atom.resize(last)
			n = last
			_live_particles = maxi(0, _live_particles - 1)
			continue

		var v: Vector2 = _vel[i]
		v.y += _gravity * delta
		v *= keep
		_vel[i] = v
		_pos[i] = _pos[i] + v * delta
		_life[i] = life
		if _align_vel:
			if v.length_squared() > 1.0:
				_rot[i] = v.angle()
		else:
			_rot[i] = _rot[i] + _spin[i] * delta
		i += 1

	queue_redraw()

func _draw() -> void:
	for i in range(_pos.size()):
		var tex: Texture2D = _textures[_atom[i]]
		if tex == null:
			continue
		var t: float = clampf(_life[i] / maxf(_life0[i], 0.0001), 0.0, 1.0) # 1 -> 0
		# 淡出集中在后 55%: 一出生就开始变淡的话, 最亮的那一瞬间看不见,
		# 而撞击反馈的全部价值就在最初两三帧。
		var alpha: float = clampf(t / 0.55, 0.0, 1.0)
		var grow: float = lerp(_grow, 1.0, t) # t=1 (刚生) -> 1.0, t=0 (将死) -> _grow
		var px: float = _size[i] * grow
		var ts: Vector2 = tex.get_size()
		var s: float = px / maxf(ts.x, 1.0)
		draw_set_transform(_pos[i], _rot[i], Vector2(s, s))
		draw_texture(tex, -ts * 0.5, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 发射一团粒子。**全项目唯一的发射入口** —— 联机回声挂在这里, 所以
## 任何新增的调用点自动就会同步给客户端, 不需要再去别的地方补登记。
##
## dir 是效果的主方向 (撞击法线、冲击方向)。传 Vector2.ZERO 表示各向同性。
## seed_override >= 0 时用给定种子 (客户端重放主机那一发时用), 否则自取。
static func emit(preset: String, parent: Node, pos: Vector2, dir: Vector2 = Vector2.ZERO,
		scale_mult: float = 1.0, seed_override: int = -1) -> Node2D:
	if not PRESETS.has(preset):
		push_warning("VFXParticles: 未知预设 '%s'" % preset)
		return null
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null

	var use_seed := seed_override
	if use_seed < 0:
		_burst_counter += 1
		# 只取种子, 不碰全局 RNG。乘一个大奇数把相邻序号打散, 否则连续几发
		# 的种子只差 1, RandomNumberGenerator 的头几个输出会高度相关,
		# 表现出来就是连续几发碎片朝同一个方向飞。
		use_seed = (_burst_counter * 2654435761) & 0x7FFFFFFF

	var node: VFXParticles = SelfScript.new()
	node._configure(preset, dir, scale_mult, use_seed)
	parent.add_child(node)
	node.global_position = pos
	if node._pos.is_empty():
		node.queue_free()
		return null

	_net_echo(preset, parent, pos, dir, scale_mult, use_seed)
	return node

func _configure(preset: String, dir: Vector2, scale_mult: float, use_seed: int) -> void:
	var p: Dictionary = PRESETS[preset]
	var rng := RandomNumberGenerator.new()
	rng.seed = use_seed

	for a in p["atoms"]:
		_textures.append(TextureHelper.get_tex(String(a)))

	_gravity = float(p["gravity"])
	_drag = float(p["drag"])
	_grow = float(p["grow"])
	_align_vel = bool(p["align_vel"])

	var cnt_range: Array = p["count"]
	var want: int = rng.randi_range(int(cnt_range[0]), int(cnt_range[1]))
	# 全局配额: 连环爆炸时宁可少画几颗, 也不要让粒子挤掉帧预算。
	want = mini(want, maxi(0, GLOBAL_MAX_PARTICLES - _live_particles))
	if want <= 0:
		return

	var base_angle: float = dir.angle() if dir.length_squared() > 0.0001 else 0.0
	var cone: float = float(p["cone"])
	if dir.length_squared() <= 0.0001:
		cone = PI # 没给方向就各向同性

	var spd: Array = p["speed"]
	var sz: Array = p["size"]
	var lf: Array = p["life"]
	var sp: Array = p["spin"]

	for _i in range(want):
		var ang: float = base_angle + rng.randf_range(-cone, cone)
		var speed: float = rng.randf_range(float(spd[0]), float(spd[1])) * scale_mult
		var v := Vector2(cos(ang), sin(ang)) * speed
		var life: float = rng.randf_range(float(lf[0]), float(lf[1]))
		_pos.append(Vector2.ZERO)
		_vel.append(v)
		_rot.append(v.angle() if _align_vel else rng.randf_range(-PI, PI))
		_spin.append(rng.randf_range(float(sp[0]), float(sp[1])))
		_life.append(life)
		_life0.append(life)
		_size.append(rng.randf_range(float(sz[0]), float(sz[1])) * scale_mult)
		_atom.append(rng.randi_range(0, maxi(0, _textures.size() - 1)))

	_live_particles += want

func _exit_tree() -> void:
	_live_particles = maxi(0, _live_particles - _pos.size())

## 联机: 把这一发回声给客户端。
##
## 发的是 (预设名, 局部坐标, 方向, 缩放, 种子) —— 不是逐颗粒子的状态。
## 两端跑同一份 PRESETS 和同一个 RandomNumberGenerator 种子, 所以客户端
## 重放出来的每一颗都和主机一致, 每发只要一个小包。逐帧同步几百颗粒子的
## 位置是荒谬的, 而粒子是纯表现, 丢包也无所谓 (走 unreliable)。
##
## 坐标转成 parent 的局部坐标再发, 理由同 VFXAnimator._net_echo:
## GameArea 的位置随窗口分辨率变化, 两端分辨率不同时全局坐标对不上。
static func _net_echo(preset: String, parent: Node, pos: Vector2, dir: Vector2,
		scale_mult: float, use_seed: int) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var net = parent.get_node_or_null("/root/Net")
	if net == null or not net.has_method("echo_particles"):
		return
	var local_pos: Vector2 = pos
	if parent is Node2D:
		local_pos = (parent as Node2D).to_local(pos)
	net.echo_particles(preset, local_pos, dir, scale_mult, use_seed)
