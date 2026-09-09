class_name NetSession
extends RefCounted

## 联机功能的**纯数据层**：会话角色、输入打包、快照编解码、实体分类。
##
## 这里一行 socket 都不开、一个 RPC 都不发 —— 所有真正碰网络的东西都在
## `scripts/net_manager.gd`（自动加载单例 `Net`）里。这么切分有两个具体理由：
##
## 1. **能被 headless 测出来。** 项目里 75 个 `tools/test_*.gd` 全是不联网的
##    SceneTree 脚本；打包/解包/分类这些最容易出静默错误的逻辑放在这里,
##    `tools/test_netcode.gd` 就能不开任何端口地把它们全跑一遍。放进
##    net_manager 里就只能靠"开两个进程手动连一次"来验证, 那等于没有回归。
## 2. **调用点不依赖自动加载。** player.gd / main.gd 只 preload 这个脚本读
##    静态变量, 不去摸 `/root/Net`。于是那些直接 `--script` 跑的测试脚本
##    (没有主场景、自动加载不一定就位) 不会因为拿到 null 而炸。
##
## 状态用 `static var` 而不是实例, 跟 `game_state.gd` 是同一个理由: 静态量能
## 跨 `change_scene_to_file()` 存活, 而联机会话正好要跨"标题界面 -> 对局"。
## 注意它**不是** GameState 的一部分, 所以不进 `campaign_save.json` ——
## 会话是运行期的东西, 存档里出现"上次连的是谁"没有任何意义。

const PROTOCOL_VERSION := 1

## 默认端口。27015 是 Valve 系游戏的传统端口, 挑它只是因为路由器/防火墙
## 的规则模板里通常已经有这一段。DISCOVERY_PORT 是局域网广播用的另一个
## UDP 端口, 必须和游戏端口分开 —— ENet 独占它那个端口, 广播插不进去。
const DEFAULT_PORT := 27015
const DISCOVERY_PORT := 27016

## 主机广播心跳的间隔, 和客户端认为"这个房间已经没了"的超时。
## 超时取 3 倍间隔: 丢一两个 UDP 广播包在局域网里很常见, 一丢就把房间从
## 列表里抹掉会让房间闪烁得没法点。
const DISCOVERY_BEACON_INTERVAL := 1.0
const DISCOVERY_TIMEOUT := 3.5

## 快照发送频率。30Hz 是"够 LAN 用又不至于把 Godot 的 Variant 序列化压垮"
## 的折中: 一间房同屏实体约 40 个, 每个 32 字节, 30Hz 约 38KB/s。
const SNAPSHOT_HZ := 30.0
const SNAPSHOT_DT := 1.0 / SNAPSHOT_HZ

## 傀儡位置的收敛速度 (指数平滑的时间常数的倒数)。坦克的快照里带了速度,
## 所以两帧之间是靠推算走的, 这个平滑只用来消掉推算和权威位置之间的残差;
## 数值大 = 纠正得快但抖, 小 = 顺滑但拖影。25 在 30Hz 快照下残差半衰期
## 约 28ms, 肉眼看不出来又不会抖。
const PUPPET_CONVERGE := 25.0

## ---------------------------------------------------------------- 本地预测
##
## 客户端**自己那辆**坦克不等主机的快照, 直接按本地输入先走 —— 否则按下
## 方向键到坦克动起来之间要等一个来回 (局域网约 70ms: 快照间隔 33ms + 收敛;
## 走 Steam 打公网还要再加 RTT), 手感和"网络卡了"没有区别。
##
## 预测的只有**移动**。开火仍然完全权威 —— 预测子弹要处理"我以为打中了但
## 主机说没有"的回滚, 那是另一个数量级的复杂度, 而移动预测已经拿走了绝大
## 部分体感收益。
##
## 预测用的速度不是本地算的, 是主机在快照里给的 (见 SNAP_STRIDE 的注释),
## 所以升级、流沙、冰面、眩晕全都自动生效。

static var prediction_enabled: bool = true

## 本地预测位置和权威位置差多少就直接归位, 而不是慢慢拉回来。
##
## 会差这么多只有一种情况: 本地预测和主机的判定分了岔 (被主机眩晕了、
## 被推了、撞上了一个客户端这边判定不到的东西)。这种时候慢慢拉回来会是
## 一段长达一秒的诡异漂移, 不如直接认账。64px = 1.33 格。
const PREDICT_SNAP_DIST := 64.0

## 小误差的回拉速率 (每秒的指数收敛系数)。太大就会和玩家的输入较劲,
## 表现为按住方向键时坦克一顿一顿; 太小则误差长期不收敛。
const PREDICT_PULL := 6.0

## 开火反馈的预测窗口。客户端本地播了枪口火焰之后, 主机迟早会把它自己那份
## 火焰回声过来 (VFXAnimator.create_anim 的回声是无差别的), 落在这个时间和
## 距离窗口内、又贴着本机坦克的那一份就跳过, 免得同一枪闪两次。
##
## 窗口取得很紧: 32px 不到一格, 0.25s 略大于一个来回加一个快照周期。
## 判错的代价也只是"少播一次枪口火焰", 看不出来。
const PREDICT_FIRE_ECHO_WINDOW := 0.25
const PREDICT_FIRE_ECHO_RADIUS := 32.0

## 客户端最近一次**本地预测**的开火时刻与枪口位置 (actors_container 局部坐标
## 由调用方换算)。只被 should_skip_muzzle_echo() 读。
static var predicted_fire_msec: int = -100000
static var predicted_fire_pos: Vector2 = Vector2.ZERO


## 主机回声过来的这一份枪口火焰, 是不是我刚才已经本地播过的那一发?
##
## 判据是"时间接近 + 位置接近本机刚才那个枪口"。这确实是启发式的, 但两边
## 都收得很紧, 而且**判错的代价是单向的**: 误判成重复 = 少播一次枪口火焰
## (看不出来); 判不出重复 = 同一枪闪两次 (看得出来但不影响任何判定)。
## 没有更精确的办法 —— VFX 回声走的是 create_anim 这个统一收口, 只带路径和
## 坐标, 不带"这是谁开的枪"。给回声加上来源等于给每一个特效都加, 那条收口
## 之所以有价值正是因为它对特效种类一无所知。
static func should_skip_muzzle_echo(paths: Array, world_pos: Vector2) -> bool:
	if not is_client():
		return false
	if paths.is_empty() or not String(paths[0]).contains("muzzle_flash"):
		return false
	var age := float(Time.get_ticks_msec() - predicted_fire_msec) / 1000.0
	if age > PREDICT_FIRE_ECHO_WINDOW:
		return false
	return world_pos.distance_to(predicted_fire_pos) <= PREDICT_FIRE_ECHO_RADIUS

enum Role { OFFLINE, HOST, CLIENT }

## 传输层。ENET 是现在唯一实现的一档; STEAM 预留给 GodotSteam 的
## SteamMultiplayerPeer —— 它同样实现 MultiplayerPeer 接口, 所以只需要换
## net_manager 里建 peer 的那两个函数和大厅 UI, 下面这一整套输入/快照/
## 傀儡逻辑一行都不用动。详见 net_manager.gd 顶部的"换传输层"注释。
enum Transport { ENET, STEAM }

static var transport: Transport = Transport.ENET

static var role: Role = Role.OFFLINE

## 本地这台机器控制的是几号玩家。主机永远是 1, 客户端永远是 2 ——
## 这直接对上了本来就存在的本地双人 (p1_instance / p2_instance), 所以
## 战斗逻辑那边完全不需要知道"这是第几个网络对端"。
static var local_player_id: int = 1

## 主机开局时掷出、随 `begin_match` 一起下发的随机种子。两端都用它
## `seed()` 之后再建图, 于是地形完全一致 —— 和每日挑战让所有人拿到同一张
## 图用的是同一条机制 (见 main.gd::start_game() 里 DAILY_CHALLENGE 那段)。
static var match_seed: int = 0

## 主机侧: 已连上的客户端 peer id (0 = 没人)。客户端侧: 固定为 1 (主机)。
static var remote_peer_id: int = 0

## 最近一次失败原因, 大厅 UI 直接显示。空串表示没有错误。
static var last_error: String = ""

## 客户端进联机对局之前, 它**自己那份** GameState 的快照。
##
## 加入联机之后这台机器的 GameState 会被主机那一局整个覆盖 (战役是
## campaign_from_dict, 街机至少也会被状态包改掉建造库存)。而 GameState 全是
## 静态变量, 打完回到标题也不会自己恢复 —— 不备份的话, "陪朋友打一局联机"
## 会把自己的金币、天赋、建材、图鉴改成别人的数字。
##
## 存在这里而不是 main.gd 里, 是因为备份要在**进对局之前**做 (大厅里, 还没
## 覆盖的时候), 还原要在会话结束时做 (net_manager.leave()), 两头跨了场景切换,
## 只有静态变量活得过去。
static var client_campaign_backup: Dictionary = {}
static var has_campaign_backup: bool = false

## 主机建图完成后算出的地形校验和; 客户端建完自己那份也算一遍并比对。
## 不一致说明两端的地图生成漂了 (随机种子之外还有别的输入), 这会让
## 客户端看到的墙和主机的判定对不上 —— 属于必须被吼出来的错误, 不能静默。
static var map_checksum: int = 0

# ---------------------------------------------------------------- 输入位

const IN_UP := 1 << 0
const IN_DOWN := 1 << 1
const IN_LEFT := 1 << 2
const IN_RIGHT := 1 << 3
const IN_FIRE := 1 << 4
const IN_BUILD_PREV := 1 << 5
const IN_BUILD_NEXT := 1 << 6
const IN_BUILD_PLACE := 1 << 7
const IN_BUILD_CANCEL := 1 << 8

## player_id -> 该玩家当前这一帧的输入位。
##
## 主机侧: 1 号是本机键盘直接读的 (不走这张表), 2 号是客户端 RPC 上来的。
## 客户端侧: 这张表没人读 —— 客户端的坦克是傀儡, 由快照驱动。
static var remote_input: Dictionary = {}

## 客户端上一次发出去的输入位。相同就不重发 (省掉静止时每帧一个包),
## 但握手期/丢包时会靠 net_manager 里的定期重发兜底。
static var last_sent_input: int = 0

# ---------------------------------------------------------------- 实体分类

## 复制哪些东西。**只认 actors_container 里的节点** —— 地形是两端各自按
## 同一个种子建的, 不走复制 (见 map_checksum)。
## SCENE_NODE 是**兜底档**: 任何从场景实例化出来、又不属于上面几类的东西
## (玩家造的炮塔/围墙/地雷、火车车厢、导弹打击标记……)。它靠节点自己的
## `scene_file_path` 复制, 所以不需要维护一张会过期的类型表 —— 项目里光
## 建造物就有 16 种, 分布在 scripts/buildings/ 和 scripts/ 两处, 手写表是
## 一定会漏的。
##
## 代码里 new() 出来的节点 (全部 VFX) `scene_file_path` 是空的, 自然被排除。
enum Kind { PLAYER = 0, ENEMY = 1, BULLET = 2, POWERUP = 3, SPAWNSTAR = 4, ALLY = 5, SCENE_NODE = 6, IGNORED = 255 }

## 自己在 _physics_process 里有 net_puppet 早退分支的类型。其余类型的傀儡
## 由 net_manager 代跑插值, 并且整个关掉处理 —— 见 NetPuppet.make_puppet。
const SELF_DRIVEN_KINDS := [Kind.PLAYER, Kind.ENEMY, Kind.BULLET]

## 脚本路径 -> Kind。用脚本路径而不是 `node is PlayerTank` 是为了避免
## preload 环: player.gd 要 preload 这个文件读输入, 这个文件再 preload
## player.gd 就成了循环依赖。
const SCRIPT_KIND := {
	"res://scripts/player.gd": Kind.PLAYER,
	"res://scripts/enemy.gd": Kind.ENEMY,
	"res://scripts/bullet.gd": Kind.BULLET,
	"res://scripts/power_up.gd": Kind.POWERUP,
	"res://scripts/spawn_star.gd": Kind.SPAWNSTAR,
	"res://scripts/ally_tank.gd": Kind.ALLY,
}

## Kind -> 客户端用来造傀儡的场景。必须和主机那边实际实例化的场景一致,
## 否则傀儡的贴图/碰撞形状会和主机的判定对不上。
const KIND_SCENE := {
	Kind.PLAYER: "res://scenes/player.tscn",
	Kind.ENEMY: "res://scenes/enemy.tscn",
	Kind.BULLET: "res://scenes/bullet.tscn",
	Kind.POWERUP: "res://scenes/power_up.tscn",
	Kind.SPAWNSTAR: "res://scenes/spawn_star.tscn",
	Kind.ALLY: "res://scenes/ally_tank.tscn",
}

## 每个被复制实体在主机上分到的编号。0 保留作"没有编号"。
static var _next_net_id: int = 1

## 客户端侧: net_id -> 傀儡节点。
static var puppets: Dictionary = {}

# ================================================================ 会话

static func is_active() -> bool:
	return role != Role.OFFLINE


static func is_host() -> bool:
	return role == Role.HOST


static func is_client() -> bool:
	return role == Role.CLIENT


## 本机是不是"跑模拟的那一端"。离线和主机都是 true, 客户端是 false。
##
## 这是整套联机改造里最重要的一个谓词: 所有原本无条件跑的战斗逻辑
## (敌人 AI、子弹碰撞、刷怪、掉落) 都用它包一层, 客户端上一律不跑。
static func is_authority() -> bool:
	return role != Role.CLIENT


static func reset() -> void:
	role = Role.OFFLINE
	local_player_id = 1
	match_seed = 0
	remote_peer_id = 0
	last_error = ""
	map_checksum = 0
	remote_input.clear()
	last_sent_input = 0
	puppets.clear()
	_next_net_id = 1
	predicted_fire_msec = -100000
	predicted_fire_pos = Vector2.ZERO
	# client_campaign_backup 故意**不清**: 还原它的人是 net_manager.leave(),
	# 而 leave() 正是调 reset() 的那一个 —— 顺序是先还原再 reset。清在这里
	# 等于把还原用的数据在还原之前就扔了。


## 把已经被释放的傀儡从表里摘掉。换房时 main.gd::_clear_all() 会把上一间房的
## 敌人和子弹整批 queue_free, 但这张表不知道 —— 不清的话它只增不减, 而且
## 主机随后发来的 despawn 全部落在失效引用上。
static func purge_dead_puppets() -> void:
	var dead: Array = []
	for id in puppets:
		if not is_instance_valid(puppets[id]):
			dead.append(id)
	for id in dead:
		puppets.erase(id)


static func alloc_net_id() -> int:
	_next_net_id += 1
	return _next_net_id - 1

# ================================================================ 输入

## 把一套 `<prefix>_move_*` / `<prefix>_fire` / `<prefix>_build_*` 输入动作
## 压成一个整数。prefix 是 "p1" 或 "p2"。
##
## **客户端始终用 "p1" 这套键位操作自己那辆 2 号坦克。** 联机的时候屏幕前
## 只有一个人, 让他去够方向键+小键盘 0 那套"右手边玩家"的布局毫无道理 ——
## 键位是本地概念, 玩家编号是网络概念, 这里是两者唯一需要解耦的地方。
static func pack_input(prefix: String) -> int:
	var bits := 0
	if Input.is_action_pressed(prefix + "_move_up"): bits |= IN_UP
	if Input.is_action_pressed(prefix + "_move_down"): bits |= IN_DOWN
	if Input.is_action_pressed(prefix + "_move_left"): bits |= IN_LEFT
	if Input.is_action_pressed(prefix + "_move_right"): bits |= IN_RIGHT
	if Input.is_action_pressed(prefix + "_fire"): bits |= IN_FIRE
	if Input.is_action_pressed(prefix + "_build_prev"): bits |= IN_BUILD_PREV
	if Input.is_action_pressed(prefix + "_build_next"): bits |= IN_BUILD_NEXT
	if Input.is_action_pressed(prefix + "_build_place"): bits |= IN_BUILD_PLACE
	if Input.is_action_pressed(prefix + "_build_cancel"): bits |= IN_BUILD_CANCEL
	return bits


## 位 -> 方向向量。
##
## **优先级必须和 player.gd 原来那串 if/elif 完全一致 (上 > 下 > 左 > 右)。**
## 同时按住上和左的时候, 本地玩家会往上走; 如果这里改成"后按的赢"或者
## 归一化成斜向, 联机下同一套按键就会走出不同的轨迹, 而这种差异只在
## 两个人同时打的时候才看得出来, 极难定位。
static func dir_from_bits(bits: int) -> Vector2:
	if bits & IN_UP: return Vector2.UP
	if bits & IN_DOWN: return Vector2.DOWN
	if bits & IN_LEFT: return Vector2.LEFT
	if bits & IN_RIGHT: return Vector2.RIGHT
	return Vector2.ZERO


static func has_bit(bits: int, bit: int) -> bool:
	return (bits & bit) != 0


## 战斗逻辑读输入的唯一入口。返回这一帧 pid 号玩家的输入位。
##
## - 离线: 直接读本地 `p{pid}_*`, 和联机改造之前的行为逐位相同。
## - 主机: 1 号读本地, 2 号读客户端发上来的。
## - 客户端: 返回 0 —— 客户端的坦克是傀儡, 不该有人问它输入。
static func input_for(pid: int) -> int:
	match role:
		Role.OFFLINE:
			return pack_input("p1" if pid == 1 else "p2")
		Role.HOST:
			if pid == local_player_id:
				return pack_input("p1")
			return int(remote_input.get(pid, 0))
		_:
			return 0

# ================================================================ 快照

## 一帧快照的线格式。拆成三个 Packed 数组而不是 Array[Dictionary], 是因为
## Godot 对 PackedInt32Array/PackedFloat32Array 有紧凑的二进制序列化, 而
## 一个 Array[Dictionary] 每个字段都要带 key 字符串, 同样内容大 5 倍以上。
##
## - ids[i]        第 i 个实体的 net_id
## - flags[i]      状态位 (见 F_*)
## - data[i*6+0/1] 位置 x / y (父节点局部坐标)
## - data[i*6+2]   旋转
## - data[i*6+3/4] 速度 x / y —— 傀儡靠它在两帧快照之间推算, 没有它坦克
##                 会以 30Hz 一跳一跳地走
## - data[i*6+5]   按类型解释的附加量。目前只有 PLAYER 用它: 主机算出来的
##                 **当前有效移动速度**。客户端的本地预测拿它当自己的速度,
##                 于是所有影响速度的东西 (升级倍率、流沙、冰面、两栖装甲、
##                 眩晕时的 0) 自动跟着走 —— 不需要把 RPGManager 那一整套
##                 状态复制到客户端, 也不会因为漏同步某个 buff 而越预测越偏。
const SNAP_STRIDE := 6

const F_INVULNERABLE := 1 << 0
const F_DYING := 1 << 1
const F_VISIBLE := 1 << 2
## 玩家坦克此刻能不能开火 (主机的 can_fire)。客户端的开火反馈预测靠它闸住 ——
## 见 player.gd::_net_predict_step 里那段。
const F_CAN_FIRE := 1 << 3


## 把一组实体编成快照。entities 是 [{id, pos, rot, vel, flags}] 形式的数组,
## 由 net_manager 从场景树上收集; 这里只管编码, 不碰节点。
static func encode_snapshot(entities: Array) -> Array:
	var n := entities.size()
	var ids := PackedInt32Array()
	var flags := PackedInt32Array()
	var data := PackedFloat32Array()
	ids.resize(n)
	flags.resize(n)
	data.resize(n * SNAP_STRIDE)
	for i in range(n):
		var e: Dictionary = entities[i]
		ids[i] = int(e.get("id", 0))
		flags[i] = int(e.get("flags", 0))
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var vel: Vector2 = e.get("vel", Vector2.ZERO)
		var base := i * SNAP_STRIDE
		data[base + 0] = pos.x
		data[base + 1] = pos.y
		data[base + 2] = float(e.get("rot", 0.0))
		data[base + 3] = vel.x
		data[base + 4] = vel.y
		data[base + 5] = float(e.get("extra", 0.0))
	return [ids, flags, data]


## encode_snapshot 的逆。故意做成"结构坏了就返回空数组"而不是崩 ——
## 快照走的是 unreliable 通道, 一个被截断的包不该把整局游戏带走。
static func decode_snapshot(payload: Array) -> Array:
	if payload.size() != 3:
		return []
	var ids: PackedInt32Array = payload[0]
	var flags: PackedInt32Array = payload[1]
	var data: PackedFloat32Array = payload[2]
	var n := ids.size()
	if flags.size() != n or data.size() != n * SNAP_STRIDE:
		return []
	var out: Array = []
	out.resize(n)
	for i in range(n):
		var base := i * SNAP_STRIDE
		out[i] = {
			"id": ids[i],
			"flags": flags[i],
			"pos": Vector2(data[base + 0], data[base + 1]),
			"rot": data[base + 2],
			"vel": Vector2(data[base + 3], data[base + 4]),
			"extra": data[base + 5],
		}
	return out

# ================================================================ 实体

## 这个节点属于哪一类。认不出来的 (VFX、建筑、火车车厢……) 返回 IGNORED,
## 不复制。
static func classify(node: Node) -> int:
	if node == null:
		return Kind.IGNORED
	var scr: Script = node.get_script() as Script
	if scr != null and SCRIPT_KIND.has(scr.resource_path):
		return SCRIPT_KIND[scr.resource_path]
	# 兜底: 从场景实例化出来的东西一律复制 (见 Kind.SCENE_NODE 的注释)。
	if node is Node2D and String(node.scene_file_path) != "":
		return Kind.SCENE_NODE
	return Kind.IGNORED


## 造一个傀儡需要的最小参数集。**只包含"看起来对"所必需的字段** ——
## 伤害、感知半径、AI 状态这些客户端一律不需要, 因为客户端不跑逻辑。
static func spawn_payload(node: Node, kind: int) -> Dictionary:
	match kind:
		Kind.PLAYER:
			return {
				"pid": int(node.player_id),
				"tier": int(node.upgrade_tier),
			}
		Kind.ENEMY:
			return {
				"type": int(node.enemy_type),
				"bonus": bool(node.is_bonus),
			}
		Kind.BULLET:
			# 子弹是唯一靠客户端自己推算移动的实体 (匀速直线), 所以
			# 方向和速度必须进 payload, 否则傀儡子弹只能被快照拖着走,
			# 720px/s 的针弹会拖出一条肉眼可见的残影。
			return {
				"dx": node.direction.x,
				"dy": node.direction.y,
				"spd": node.speed,
				"steel": bool(node.can_destroy_steel),
				"homing": bool(node.is_homing),
				"aoe": bool(node.is_aoe),
				"kin": bool(node.is_kinetic_push),
				"bnc": int(node.bounces_remaining),
				"tex": String(node.custom_texture_path),
			}
		Kind.POWERUP:
			return {"type": int(node.power_up_type)}
		Kind.SCENE_NODE:
			# 场景路径由节点自己带着。客户端拿它 load() 出同一个场景, 所以
			# 加一种建造物不需要动这里任何一行。
			return {"scene": String(node.scene_file_path)}
		_:
			return {}


## 把 spawn_payload 的内容写回一个新实例化的傀儡节点。必须在 add_child()
## **之前**调用 —— 这几个字段都是 _ready() 里拿来挑贴图的。
static func apply_spawn_payload(node: Node, kind: int, payload: Dictionary) -> void:
	match kind:
		Kind.PLAYER:
			node.player_id = int(payload.get("pid", 2))
			node.upgrade_tier = int(payload.get("tier", 0))
		Kind.ENEMY:
			node.enemy_type = int(payload.get("type", 0))
			node.is_bonus = bool(payload.get("bonus", false))
		Kind.BULLET:
			node.direction = Vector2(payload.get("dx", 0.0), payload.get("dy", -1.0))
			node.speed = float(payload.get("spd", 480.0))
			node.can_destroy_steel = bool(payload.get("steel", false))
			node.is_homing = bool(payload.get("homing", false))
			node.is_aoe = bool(payload.get("aoe", false))
			node.is_kinetic_push = bool(payload.get("kin", false))
			node.bounces_remaining = int(payload.get("bnc", 0))
			node.custom_texture_path = String(payload.get("tex", ""))
		Kind.POWERUP:
			node.power_up_type = int(payload.get("type", 0))


## 地形校验和。按格子把"这里是什么"折进一个 32 位整数。
##
## 用 map_container 的子节点数量是不够的 —— 数量对得上但类型错位的图会
## 静默通过。这里把每个节点的位置量化到格子再和它的类型名一起混进去,
## 于是"同一格从砖变成钢"也会被抓到。
static func terrain_checksum(container: Node, tile_size: float) -> int:
	if container == null:
		return 0
	var acc := 0
	for child in container.get_children():
		if not (child is Node2D):
			continue
		var p: Vector2 = (child as Node2D).position
		# floor 而不是 round: 瓦片摆在格心 (col + 0.5) * TILE_SIZE, round 会把
		# 24px 和 48px 都算成第 1 格, 两个不同位置撞进同一个格号。
		var gx := int(floor(p.x / tile_size))
		var gy := int(floor(p.y / tile_size))
		var tag := String(child.name).left(6)
		var h := hash([gx, gy, tag])
		# 交换律的加法保证遍历顺序不影响结果 —— 两端的建图顺序理论上一致,
		# 但不该把校验和的正确性押在这上面。
		acc = (acc + h) & 0x7FFFFFFF
	return acc
