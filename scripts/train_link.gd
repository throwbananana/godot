class_name TrainLink
extends RefCounted

## 双人合体挂载 —— 两名玩家同时按住 link 键, 其中一辆挂到另一辆后面当车厢。
##
##     挂载条件: 两人同时按住 p{1,2}_link, 双方存活, 彼此距离 <= LINK_RANGE,
##               且**至少一方是 train 分支** (那一方当机车)
##     解  除:   任一方单击 link 键; 或任一方阵亡 / 切房间 / 分支变更
##
## === 状态放在 static 上, 和 NetSession / GameState 同一个套路 ===
##
## 挂载状态既要被 main.gd 驱动 (主机每帧判定), 又要被 player.gd 读 (决定这一帧
## 是自己走还是被拖着走), 还要在切房间时清掉。做成节点会多一个需要同步的实体,
## 而它本质上只是两个整数。
##
## === 谁当机车: 列车分支的那一方 ===
##
## 这是"必须有一方是 train"这条规则的直接推论 —— 挂车厢是列车分支的能力,
## 所以列车方是机车, 另一方成为它的车厢。两个人都是 train 时按玩家编号定
## (1 号当机车), 而不是"谁先按谁当"—— 后者依赖两台机器上事件到达的先后,
## 联机时主客双方可能得出不同结论, 而这个结论没有任何东西会去校验。
##
## === 为什么要限距离 ===
##
## 跟随是靠采样机车的历史路径实现的 (TrainFollowHelper.sample_at_distance),
## 也就是说挂载的瞬间, 后车会被**直接放到**机车尾迹上的某一点。不限距离的话
## 隔着半张地图按一下就能瞬移过去, 等于一个无冷却的免费脱困技能。

const LINK_RANGE: float = 120.0

## 状态切换后的闸门。挂载要求"两人同时按住", 而按住的那一帧之后按键仍然是
## 按下状态 —— 没有这道闸, 同一次按压会在挂上的下一帧立刻被判成解除。
## 0.40 秒足够让人松开手, 又短到不影响"挂上了马上想解开"。
const TOGGLE_LOCKOUT: float = 0.40

## 后车挂在整列车的**最后一节**后面, 再退这么远。
## 和 TrainCarriage.follow_distance 取同一个值, 队形才是均匀的。
const TOW_GAP: float = 38.0

## 0 = 未挂载。挂载时分别是机车 / 后车的 player_id。
static var leader_id: int = 0
static var follower_id: int = 0

static var _lockout: float = 0.0
static var _prev_bits: Dictionary = {}


static func reset() -> void:
	leader_id = 0
	follower_id = 0
	_lockout = 0.0
	_prev_bits.clear()


static func is_linked() -> bool:
	return leader_id != 0


static func is_follower(pid: int) -> bool:
	return leader_id != 0 and follower_id == pid


static func is_leader(pid: int) -> bool:
	return leader_id != 0 and leader_id == pid


## 这一帧 pid 是不是刚按下 link 键 (上升沿)。
static func _just_pressed(pid: int, bits: int) -> bool:
	var prev: int = int(_prev_bits.get(pid, 0))
	return NetSession.has_bit(bits, NetSession.IN_LINK) \
		and not NetSession.has_bit(prev, NetSession.IN_LINK)


## 能不能挂载; 返回机车的 player_id, 0 表示不行。
##
## **分支由调用方传进来, 这里不去 scene tree 里摸 rpg_mgr。** 本模块是纯规则,
## 让它自己 `p1.get_tree().current_scene.rpg_mgr` 会带来两个问题: 一是多一条
## 只在"节点已进树"时才成立的隐式前提 (桩测试里节点在 _init() 阶段还没进树,
## 于是 evaluate 静默退化成"两边都不是列车"—— 一条**空转的绿**), 二是同一份
## 分支信息在 main.gd 手上本来就是现成的。
##
## `reason` 是给调用方发提示用的 —— 按了没反应而不知道为什么, 比不能按更糟。
static func evaluate(p1: Node, p2: Node, b1: String, b2: String,
		reason: Array = []) -> int:
	if GameState.player_count != 2:
		return 0
	if not is_instance_valid(p1) or not is_instance_valid(p2):
		return 0
	if ("is_dying" in p1 and p1.is_dying) or ("is_dying" in p2 and p2.is_dying):
		return 0

	if b1 != "train" and b2 != "train":
		reason.append("需要有一方是列车分支")
		return 0

	if p1.global_position.distance_to(p2.global_position) > LINK_RANGE:
		reason.append("距离太远, 靠近队友再合体")
		return 0

	# 两个都是 train 时按编号定, 见类注释。
	if b1 == "train":
		return 1
	return 2


## 主机每帧调一次。返回一个描述这一帧发生了什么的字符串 (空 = 无事),
## 调用方拿去发提示。
##
## **只有主机 (或单机) 能调。** 客户端的预测坦克有真实碰撞, 也真的会读到本地
## 按键, 让它自己判定的话两边会各挂各的 —— 而挂载状态没有任何东西在校验,
## 分歧只会表现为"我这边合体了, 你那边没有"。这和电路开关、房门那两处
## 早退保护是同一个理由。
static func host_step(delta: float, p1: Node, p2: Node,
		b1_branch: String, b2_branch: String) -> String:
	if _lockout > 0.0:
		_lockout -= delta

	var b1 := NetSession.input_for(1)
	var b2 := NetSession.input_for(2)
	var msg := ""

	if leader_id != 0:
		# 已挂载: 任一方单击即解除
		var valid := is_instance_valid(p1) and is_instance_valid(p2)
		# 机车必须一直是列车分支。分支可以在对局中变 (升级卡), 而挂载是靠
		# "有一方是 train"成立的 —— 前提没了就得断开, 否则一辆非列车坦克会
		# 一直拖着队友, 而这个状态没有任何入口能再产生它。
		var still_train := (b1_branch if leader_id == 1 else b2_branch) == "train"
		if not valid or ("is_dying" in p1 and p1.is_dying) or ("is_dying" in p2 and p2.is_dying) \
				or not still_train:
			leader_id = 0
			follower_id = 0
			msg = "🚂 连接断开"
		elif _lockout <= 0.0 and (_just_pressed(1, b1) or _just_pressed(2, b2)):
			leader_id = 0
			follower_id = 0
			_lockout = TOGGLE_LOCKOUT
			msg = "🚂 已解除挂载"
	else:
		# 未挂载: 需要两人同时按住
		if _lockout <= 0.0 \
				and NetSession.has_bit(b1, NetSession.IN_LINK) \
				and NetSession.has_bit(b2, NetSession.IN_LINK):
			var reason: Array = []
			var lead := evaluate(p1, p2, b1_branch, b2_branch, reason)
			if lead != 0:
				leader_id = lead
				follower_id = 2 if lead == 1 else 1
				_lockout = TOGGLE_LOCKOUT
				msg = "🚂 P%d 挂载到 P%d 后方" % [follower_id, leader_id]
			elif not reason.is_empty() and (_just_pressed(1, b1) or _just_pressed(2, b2)):
				# 只在按下的那一帧提示一次, 按住不放不会刷屏
				msg = "🚂 " + str(reason[0])

	_prev_bits[1] = b1
	_prev_bits[2] = b2
	return msg


## 后车这一帧该待在哪。返回 {} 表示还没有可用的尾迹 (机车刚生成)。
##
## 挂在**整列车的最后一节**后面, 而不是直接挂在机车后面: 列车分支的机车本来
## 就带着 1~2 节 AI 车厢, 直接按 TOW_GAP 挂到机车后面会和第一节车厢完全重叠。
static func follower_target(leader: Node) -> Dictionary:
	if not is_instance_valid(leader):
		return {}
	var tail: Node = leader
	var chain := TrainFollowHelper.collect_followers(leader)
	if not chain.is_empty():
		tail = chain[chain.size() - 1]
	if not ("history_positions" in tail and "history_rotations" in tail):
		return {}
	return TrainFollowHelper.sample_at_distance(
		tail.history_positions, tail.history_rotations, TOW_GAP)
