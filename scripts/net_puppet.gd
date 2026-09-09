class_name NetPuppet
extends RefCounted

## 客户端侧的"傀儡"实体: 一个只负责长得对、动得对, 完全不跑逻辑的节点。
##
## 联机采用主机权威 —— 敌人 AI、子弹碰撞、掉落、刷怪全部只在主机上跑。
## 客户端拿到的是同样的场景实例, 但被这里剥掉了三样东西:
##
## 1. **碰撞**。傀儡不参与任何物理查询, 否则客户端本地的一次 move_and_slide
##    会把它推到和主机不一致的位置, 下一帧再被快照拽回来, 表现为抖动。
## 2. **逻辑**。各自脚本的 `_physics_process` 顶上加了 `if net_puppet:` 的
##    早退分支 (player.gd / enemy.gd / bullet.gd), 没有这个分支的类型
##    (友军坦克) 则直接 set_physics_process(false)。
## 3. **权威**。位置只从快照来。
##
## 保留下来的是贴图、动画、粒子、音效这些纯表现的东西 —— 傀儡走的是和
## 主机一模一样的场景和 _ready(), 所以美术表现不需要任何一份副本。
##
## ## 为什么不是"客户端也跑一遍模拟"
##
## 那需要全项目确定性 (同样的随机数、同样的浮点、同样的物理步进)。这个项目
## 里到处是 `randf()`、`Time.get_ticks_msec()` 驱动的动画、以及 Godot 自己的
## 物理求解 —— 任何一处不一致都会让两端在几秒内漂开, 而且漂开之后**没有
## 任何报错**, 只有"他那边我明明打中了"。主机权威把这个问题从根上消掉。

const NetSession = preload("res://scripts/net_session.gd")

## 子弹是匀速直线运动, 客户端的推算和主机的实际位置在数学上完全一致,
## 所以可以用很硬的收敛系数 (基本等于直接贴上去)。坦克会因为输入延迟和
## 碰撞而偏离推算, 用软一点的系数把纠正抹平。
const CONVERGE_BULLET := 60.0
const CONVERGE_DEFAULT := NetSession.PUPPET_CONVERGE


## 把一个刚实例化 (但还没 add_child) 的节点变成傀儡。
##
## 必须在进入场景树之前调用: 碰撞层要在第一次物理帧之前就清掉, 不然
## 傀儡会在生成的那一帧真的撞到东西。
static func make_puppet(node: Node, kind: int) -> void:
	node.set_meta("net_puppet", true)
	node.set_meta("net_kind", kind)
	node.set_meta("net_tpos", Vector2.ZERO)
	node.set_meta("net_trot", 0.0)
	node.set_meta("net_vel", Vector2.ZERO)
	node.set_meta("net_primed", false)

	# player.gd / enemy.gd / bullet.gd 里有 net_puppet 早退分支, 让它们
	# 继续跑 _physics_process (履带动画、闪烁这些还要靠它); 其余类型没有
	# 分支可依靠, 只能整个关掉, 由 net_manager 代跑插值。
	if not (kind in NetSession.SELF_DRIVEN_KINDS):
		node.set_physics_process(false)
	# 兜底档 (玩家造的炮塔、地雷、导弹标记……) 连 _process 也要关。
	# 只关物理是不够的: 自动炮塔的索敌开火如果写在 _process 里, 客户端上
	# 那门傀儡炮塔会自己开火, 打出一串只有它自己看得见的子弹 —— 而那些
	# 子弹在主机上不存在, 玩家会以为自己在掩护, 其实什么都没发生。
	# 代价是这类傀儡不播自己的动画; 位置和朝向仍然跟着快照走。
	if kind == NetSession.Kind.SCENE_NODE:
		node.set_process(false)

	_strip_interaction(node)


## 递归剥掉碰撞与信号监听。
##
## **只清 mask, 保留 layer。** 这两者不对称是有原因的:
##
## - `collision_mask` = 0 —— 傀儡自己不撞任何东西。它的位置完全由快照决定,
##   本地再算一次碰撞只会把它推到和主机不一致的地方, 下一帧又被快照拽回来,
##   表现为抖动。
## - `collision_layer` **保留** —— 客户端本地预测的那辆坦克 (见
##   make_predicted) 要能撞到墙、撞到敌人、撞到队友。layer 一起清零的话,
##   预测出来的坦克会从所有单位身上直接穿过去, 然后被回拉逻辑硬扯回来,
##   在每一次贴身接触时橡皮筋一下。
##
## Area2D 的 monitoring/monitorable 两个都要关: 前者决定它会不会触发自己的
## body_entered (客户端不做任何判定), 后者决定它会不会被别的 Area 检测到。
## Area 不阻挡 CharacterBody2D, 所以关掉它们不影响上面的预测碰撞。
static func _strip_interaction(node: Node) -> void:
	if node is CollisionObject2D:
		var co := node as CollisionObject2D
		# 记下原值, make_predicted() 要把它们还回去。
		co.set_meta("net_layer0", co.collision_layer)
		co.set_meta("net_mask0", co.collision_mask)
		co.collision_mask = 0
	if node is Area2D:
		var a := node as Area2D
		a.monitoring = false
		a.monitorable = false
	for child in node.get_children():
		_strip_interaction(child)


## 把客户端**自己那辆**坦克标成"本地预测": 它按本地输入立刻走, 而不是等
## 快照。碰撞要还回去 —— 预测的全部意义就是本地立刻得到一个**正确的**结果,
## 一个会穿墙的预测比没有预测更糟。
static func make_predicted(node: Node) -> void:
	if not NetSession.prediction_enabled:
		return
	node.set_meta("net_predicted", true)
	_restore_interaction(node)


static func _restore_interaction(node: Node) -> void:
	if node is CollisionObject2D:
		var co := node as CollisionObject2D
		co.collision_layer = int(co.get_meta("net_layer0", co.collision_layer))
		co.collision_mask = int(co.get_meta("net_mask0", co.collision_mask))
	for child in node.get_children():
		_restore_interaction(child)


static func is_predicted(node: Node) -> bool:
	return node != null and bool(node.get_meta("net_predicted", false))


## 权威位置往前推一格 delta, 返回推完之后的目标点。
##
## 插值 (update) 和预测 (reconcile) 都要做这件事, 但只能做一次 —— 同一帧
## 推两遍等于把速度算成两倍。
static func _advance_target(node: Node2D, delta: float) -> Vector2:
	var vel: Vector2 = node.get_meta("net_vel", Vector2.ZERO)
	var tpos: Vector2 = node.get_meta("net_tpos", node.position)
	tpos += vel * delta
	node.set_meta("net_tpos", tpos)
	return tpos


## 本地预测之后的对账: 把预测位置往权威位置拉。
##
## 调用点在 player.gd::_net_predict_step 里, **必须在 move_and_slide 之后** ——
## 先移动再纠偏, 反过来的话这一帧的纠偏会立刻被移动覆盖掉。
static func reconcile(node: Node, delta: float) -> void:
	if node == null or not is_instance_valid(node) or not (node is Node2D):
		return
	var n2 := node as Node2D
	var tpos := _advance_target(n2, delta)
	var err := tpos - n2.position
	if err.length() > NetSession.PREDICT_SNAP_DIST:
		# 分岔了 (被眩晕/被推/撞上了本地判定不到的东西), 直接认账。
		n2.position = tpos
		return
	n2.position += err * (1.0 - exp(-NetSession.PREDICT_PULL * delta))


static func is_puppet(node: Node) -> bool:
	return node != null and node.has_meta("net_puppet")


## 收到一条快照记录时调用。只写目标, 不直接挪节点 —— 真正的移动在
## update() 里按帧做, 否则 30Hz 的快照会让实体一跳一跳地走。
static func set_target(node: Node, pos: Vector2, rot: float, vel: Vector2, extra: float = 0.0, flags: int = 0) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.set_meta("net_flags", flags)
	node.set_meta("net_tpos", pos)
	node.set_meta("net_trot", rot)
	node.set_meta("net_vel", vel)
	# PLAYER 的 extra 是主机算出来的有效移动速度, 本地预测拿它当速度用
	# (见 NetSession.SNAP_STRIDE 的注释)。其余类型是 0, 没人读。
	node.set_meta("net_speed", extra)
	# 第一条快照直接落位: 生成时节点在 (0,0), 让它从原点滑过去会拉出一条
	# 横穿全屏的假移动。
	if not node.get_meta("net_primed", false):
		node.set_meta("net_primed", true)
		if node is Node2D:
			(node as Node2D).position = pos
			(node as Node2D).rotation = rot


## 每个物理帧调用一次 (从各自脚本的 net_puppet 早退分支里, 或者由
## net_manager 代跑没有分支的类型)。
##
## 做两件事: 用快照里带的速度把目标点往前推 (dead reckoning), 再把节点
## 平滑地收敛到那个目标。只有插值没有推算的话, 傀儡会永远落后半个快照
## 间隔 (30Hz 下约 17ms) 外加平滑的时间常数, 高速子弹会明显拖后。
static func update(node: Node, delta: float) -> void:
	if node == null or not is_instance_valid(node) or not (node is Node2D):
		return
	var n2 := node as Node2D
	var tpos := _advance_target(n2, delta)

	var kind: int = n2.get_meta("net_kind", NetSession.Kind.IGNORED)
	var k: float = CONVERGE_BULLET if kind == NetSession.Kind.BULLET else CONVERGE_DEFAULT
	var t: float = 1.0 - exp(-k * delta)
	n2.position = n2.position.lerp(tpos, t)
	n2.rotation = lerp_angle(n2.rotation, float(n2.get_meta("net_trot", n2.rotation)), t)
