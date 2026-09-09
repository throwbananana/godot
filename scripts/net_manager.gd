extends Node

## 联机的**唯一 I/O 层**: 建立连接、局域网发现、收发 RPC、驱动快照。
## 作为自动加载单例挂在 `/root/Net`。
##
## 这是项目里第一个自动加载。之所以非用不可: RPC 需要收发两端存在**路径
## 相同**的节点, 而联机会话要跨 `title_screen -> main` 这次场景切换活下来 ——
## 挂在场景里的节点做不到这一点。纯数据部分仍然按项目惯例放在
## `net_session.gd` 的静态变量里 (见那个文件顶部的理由), 这里只放非得碰
## 引擎和网络的东西。
##
## **未激活时它完全是惰性的**: 不开端口、不注册 _process、不发包。所以
## `tools/test_*.gd` 那批 headless 脚本和单机游戏完全不受影响。
##
## ## 换传输层 (Steam / 其它)
##
## 真正和 ENet 绑定的只有 `_make_host_peer()` / `_make_client_peer()` 两个
## 函数, 以及局域网发现那一段 (Steam 有自己的大厅, 不需要 UDP 广播)。
## GodotSteam 的 SteamMultiplayerPeer 同样实现 MultiplayerPeer 接口, 所以
## 接 Steam 只需要:
##   1. 加一个 `NetSession.Transport.STEAM` 分支, 在这两个函数里建
##      SteamMultiplayerPeer 并用 Steam Lobby 的 lobby_id 代替 ip:port;
##   2. 大厅 UI 的"房间列表"从 UDP 发现换成 Steam 的 lobby 列表回调。
## 下面的输入 RPC、快照编解码、傀儡插值一行都不用改 —— 它们只认
## MultiplayerAPI, 不认底下跑的是什么。

const NetSession = preload("res://scripts/net_session.gd")
const NetPuppet = preload("res://scripts/net_puppet.gd")

## 大厅相关
signal lobby_list_changed()
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connection_failed(reason: String)
signal connected_to_host()
## 主机按下"开始"之后两端都会收到: 随机种子、模式、以及战役合作时主机那一局
## 的完整战役状态 (街机是空字典)。
signal match_begin(match_seed: int, mode: int, campaign: Dictionary)
## 主机侧: 客户端已经把地图建完、进到对局里了。
##
## 这不只是给测试用的。收到 begin_match 到真正把 main.tscn 建完之间有实测
## 两秒以上的空档 (要加载全部贴图和建 174 块地形), 这段时间里客户端已经在
## 发输入包了 —— 所以"收到过对方的包"完全不等于"对方能看见这局游戏"。
signal client_ready()
## 对局中主机把非实体状态 (分数/命数/血量) 推下来时触发。
signal state_synced(state: Dictionary)
signal match_ended(victory: bool, score: int)

## 当前对局的 MainGame 实例。main.gd 在 _ready() 里 attach, _exit_tree() 里 detach。
var game: Node = null

var _snapshot_accum: float = 0.0
var _state_accum: float = 0.0
## 状态包比快照稀疏得多 —— 分数和命数不需要 30Hz。
const STATE_HZ := 6.0

## 主机侧: net_id -> 节点。用来算"上一帧还在、这一帧没了"的差集。
var _tracked: Dictionary = {}

## 诊断计数器。联机出问题时第一个要问的永远是"包到底发出去没有" ——
## 有这三个数就能立刻分清"主机没发"和"客户端没收"。tools/test_net_e2e.gd
## 直接读它们。
var snapshots_sent: int = 0
var snapshots_recv: int = 0
var spawns_sent: int = 0
var inputs_sent: int = 0
var inputs_recv: int = 0
var states_recv: int = 0

## 房间重建 (换图/开局) 期间抑制地形销毁事件 —— 那一瞬间 map_container 的
## 每个子节点都在 exit_tree, 一个不落地发出去就是几百个无意义的包, 而且
## 客户端那边正好也在重建, 收到了也没有对应节点。
var _bulk_change: bool = false

# ---------------------------------------------------------------- 局域网发现

var _beacon: PacketPeerUDP = null      # 主机: 往外广播
var _listener: PacketPeerUDP = null    # 客户端: 收广播
var _beacon_accum: float = 0.0
## "ip:port" -> {ip, port, name, players, last_seen}
var _lobbies: Dictionary = {}
var _host_display_name: String = "TANK HOST"


func _ready() -> void:
	# 暂停时也要继续跑。玩家按下暂停只暂停**他自己那台机器**的场景树,
	# 对端的世界还在动 —— 如果连网络层也一起停了, 暂停期间攒下的输入和
	# 快照会在恢复的瞬间一次性涌进来, 表现为对方坦克瞬移一大段。
	# 主机暂停时模拟本来就冻住了, 快照会重复同一批位置, 语义是自洽的。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 惰性: 没有会话就不要每帧被叫醒。host()/join() 里会打开。
	set_process(false)
	set_physics_process(false)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ================================================================ 连接

func _make_host_peer(port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	# 只留一个客位: 这一版是"主机 P1 + 客户端 P2"的双人合作, 战斗代码里的
	# p1_instance/p2_instance 就是两个位置。多于 2 人需要先把那两个变量
	# 改成数组, 不是网络层能糊过去的事。
	var err := peer.create_server(port, 1)
	if err != OK:
		NetSession.last_error = "无法监听端口 %d (错误码 %d)" % [port, err]
		return null
	return peer


func _make_client_peer(address: String, port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		NetSession.last_error = "无法连接 %s:%d (错误码 %d)" % [address, port, err]
		return null
	return peer


func host_game(display_name: String = "", port: int = NetSession.DEFAULT_PORT) -> bool:
	leave()
	var peer := _make_host_peer(port)
	if peer == null:
		connection_failed.emit(NetSession.last_error)
		return false
	multiplayer.multiplayer_peer = peer
	NetSession.role = NetSession.Role.HOST
	NetSession.local_player_id = 1
	NetSession.last_error = ""
	_host_display_name = display_name if display_name != "" else "TANK HOST"
	_start_beacon(port)
	set_process(true)
	set_physics_process(true)
	return true


func join_game(address: String, port: int = NetSession.DEFAULT_PORT) -> bool:
	leave()
	var peer := _make_client_peer(address, port)
	if peer == null:
		connection_failed.emit(NetSession.last_error)
		return false
	multiplayer.multiplayer_peer = peer
	NetSession.role = NetSession.Role.CLIENT
	NetSession.local_player_id = 2
	NetSession.remote_peer_id = 1
	NetSession.last_error = ""
	set_process(true)
	set_physics_process(true)
	return true


const GameStateCls = preload("res://scripts/game_state.gd")


func leave() -> void:
	# 先还原客户端自己那份 GameState, 再 reset() —— 顺序不能反, reset()
	# 之后 NetSession 里那份备份的语义就没人负责了。见 client_campaign_backup。
	if NetSession.has_campaign_backup:
		GameStateCls.campaign_from_dict(NetSession.client_campaign_backup)
		NetSession.client_campaign_backup = {}
		NetSession.has_campaign_backup = false

	_stop_beacon()
	_stop_listening()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_tracked.clear()
	_snapshot_accum = 0.0
	_state_accum = 0.0
	client_in_match = false
	last_begin_mode = -1
	last_begin_campaign = {}
	NetSession.reset()
	set_process(false)
	set_physics_process(false)


func attach_game(g: Node) -> void:
	game = g


func detach_game(g: Node) -> void:
	if game == g:
		game = null
		_tracked.clear()

# ================================================================ 连接回调

func _on_peer_connected(id: int) -> void:
	if NetSession.is_host():
		NetSession.remote_peer_id = id
		peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if NetSession.is_host() and NetSession.remote_peer_id == id:
		NetSession.remote_peer_id = 0
		NetSession.remote_input.clear()
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	connected_to_host.emit()


func _on_connection_failed() -> void:
	NetSession.last_error = "连接被拒绝或超时"
	connection_failed.emit(NetSession.last_error)
	leave()


func _on_server_disconnected() -> void:
	NetSession.last_error = "与主机断开连接"
	peer_left.emit(1)
	leave()

# ================================================================ 局域网发现
#
# 主机每秒往 255.255.255.255:DISCOVERY_PORT 丢一个 JSON 心跳, 客户端绑在
# 那个端口上收。**发现端口必须和游戏端口分开** —— ENet 独占它自己的端口,
# 想在同一个端口上再收广播会直接绑定失败。
#
# 主机侧只发不绑, 所以同一台机器上开主机+客户端做测试是可行的 (客户端
# 独占 DISCOVERY_PORT, 主机不和它抢)。

func _start_beacon(game_port: int) -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", NetSession.DISCOVERY_PORT)
	_beacon_accum = NetSession.DISCOVERY_BEACON_INTERVAL # 立刻发第一个
	_beacon_game_port = game_port


var _beacon_game_port: int = NetSession.DEFAULT_PORT


func _stop_beacon() -> void:
	if _beacon:
		_beacon.close()
		_beacon = null


## 客户端开始监听局域网房间。大厅界面打开时调用, 关闭时 stop。
func start_listening() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(NetSession.DISCOVERY_PORT)
	if err != OK:
		NetSession.last_error = "无法监听发现端口 %d —— 可能已有另一个游戏实例占着" % NetSession.DISCOVERY_PORT
		_listener = null
		return
	_lobbies.clear()
	set_process(true)


func stop_listening() -> void:
	_stop_listening()
	if not NetSession.is_active():
		set_process(false)


func _stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null
	_lobbies.clear()


## 当前看到的房间列表, 按房间名排序 (稳定顺序, 免得列表每秒重排)。
func get_lobbies() -> Array:
	var out: Array = _lobbies.values().duplicate()
	out.sort_custom(func(a, b): return String(a.get("name", "")) < String(b.get("name", "")))
	return out


func _pump_beacon(delta: float) -> void:
	if _beacon == null:
		return
	_beacon_accum += delta
	if _beacon_accum < NetSession.DISCOVERY_BEACON_INTERVAL:
		return
	_beacon_accum = 0.0
	var payload := {
		"v": NetSession.PROTOCOL_VERSION,
		"name": _host_display_name,
		"port": _beacon_game_port,
		"players": 2 if NetSession.remote_peer_id != 0 else 1,
	}
	_beacon.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _pump_listener(delta: float) -> void:
	if _listener == null:
		return
	while _listener.get_available_packet_count() > 0:
		var raw := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		# 协议版本不一致的房间照样列出来但标记掉 —— 直接隐藏的话, 一个
		# 版本不匹配的对局表现为"我明明开了房他却看不见", 那是最难查的
		# 一类问题。列出来并写明原因, 至少症状是自解释的。
		var key := "%s:%d" % [ip, int(parsed.get("port", NetSession.DEFAULT_PORT))]
		_lobbies[key] = {
			"ip": ip,
			"port": int(parsed.get("port", NetSession.DEFAULT_PORT)),
			"name": String(parsed.get("name", "TANK HOST")),
			"players": int(parsed.get("players", 1)),
			"version": int(parsed.get("v", 0)),
			"compatible": int(parsed.get("v", 0)) == NetSession.PROTOCOL_VERSION,
			"last_seen": Time.get_ticks_msec(),
		}
		lobby_list_changed.emit()

	var now := Time.get_ticks_msec()
	var stale: Array = []
	for key in _lobbies:
		if now - int(_lobbies[key]["last_seen"]) > int(NetSession.DISCOVERY_TIMEOUT * 1000.0):
			stale.append(key)
	if not stale.is_empty():
		for key in stale:
			_lobbies.erase(key)
		lobby_list_changed.emit()

# ================================================================ 开局

## 主机点"开始"。掷种子、通知客户端、自己也进对局。
##
## campaign 是战役合作用的完整战役状态 (GameState.campaign_to_dict), 街机传
## 空字典。整份传而不是让客户端自己生成: 楼层图、幕数、金币、天赋都在里面,
## 客户端**接管主机这一局**, 而不是各自开一局长得像的。
func start_match(mode: int, campaign: Dictionary = {}) -> void:
	if not NetSession.is_host():
		return
	randomize()
	var s := randi()
	NetSession.match_seed = s
	# 开局之后房间就满了, 停掉广播免得别人还看得到一个进不去的房间。
	_stop_beacon()
	last_begin_mode = mode
	last_begin_campaign = campaign
	_rpc_begin_match.rpc(s, mode, campaign)
	match_begin.emit(s, mode, campaign)


## 最近一次开局包的内容。信号是"发生的那一刻"才有用的东西, 而开局包是
## reliable 的一次性事件 —— 谁要是晚一帧才连上 match_begin 就永远收不到了。
## 存下来让后连的人也读得到。
var last_begin_mode: int = -1
var last_begin_campaign: Dictionary = {}


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_match(s: int, mode: int, campaign: Dictionary) -> void:
	NetSession.match_seed = s
	last_begin_mode = mode
	last_begin_campaign = campaign
	match_begin.emit(s, mode, campaign)


## 主机侧: 客户端是否已经进到对局里了 (见 client_ready 信号)。
var client_in_match: bool = false


## 客户端建完自己那份世界之后调用。main.gd::start_game() 末尾。
func notify_ready() -> void:
	if NetSession.is_client():
		_rpc_client_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready() -> void:
	if not NetSession.is_host():
		return
	client_in_match = true
	client_ready.emit()

# ================================================================ 输入
#
# 客户端每个物理帧把自己的输入位打包发给主机。unreliable_ordered: 丢一帧
# 输入无所谓 (下一帧就补上了), 但**乱序会要命** —— 一个迟到的"松开"包
# 盖掉后到的"按下"会让坦克无缘无故停一下。

func _physics_process(delta: float) -> void:
	if NetSession.is_client():
		var bits := NetSession.pack_input("p1")
		# 状态没变就不发。静止时这能把上行包从 60/秒压到 0, 而握手/丢包
		# 的兜底是下面这个: 每 0.5 秒无条件重发一次当前状态。
		_input_resend_accum += delta
		if bits != NetSession.last_sent_input or _input_resend_accum >= 0.5:
			NetSession.last_sent_input = bits
			_input_resend_accum = 0.0
			inputs_sent += 1
			_rpc_input.rpc_id(1, bits)


var _input_resend_accum: float = 0.0


# ---------------------------------------------------------------- 建造 (上行)
#
# 建造是权威行为: 扣库存、占一格地、生成一个能挡子弹的实体。客户端只发
# 意图, 主机执行。两条都走 reliable —— 丢一个"我要放炮塔"和丢一帧输入完全
# 不是一回事, 后者下一帧就补上了, 前者丢了就是玩家按了没反应。

## 客户端: 我把选择切到了这个建筑。
func request_select(structure_type: int) -> void:
	if NetSession.is_client():
		_rpc_select.rpc_id(1, structure_type)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_select(structure_type: int) -> void:
	if not NetSession.is_host() or game == null or not is_instance_valid(game):
		return
	var builder = game.get("builder_ctrl")
	if builder == null or not is_instance_valid(builder):
		return
	# 直接写 selection_by_pid 而不是调 select_structure(): 后者会弹提示、
	# 改热键栏, 那些是**客户端那块屏幕**上该发生的事, 在主机这边重放一遍
	# 只会让主机玩家看到一堆自己没操作过的提示。
	builder.selection_by_pid[2] = structure_type


## 客户端: 我要在当前朝向放下当前选中的建筑。
func request_build() -> void:
	if NetSession.is_client():
		_rpc_build.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_build() -> void:
	if not NetSession.is_host() or game == null or not is_instance_valid(game):
		return
	var builder = game.get("builder_ctrl")
	if builder == null or not is_instance_valid(builder):
		return
	# 走的就是本地双人时 P2 按下放置键那条路径 —— 库存校验、落点校验、
	# 提示、扣库存全部复用, 没有一条"联机专用"的放置逻辑可以走偏。
	builder._try_place_current(2)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(bits: int) -> void:
	if not NetSession.is_host():
		return
	inputs_recv += 1
	# 客户端固定是 2 号玩家。不按 sender id 去查表是故意的: 这一版只有
	# 一个客位, 多加一层映射只会多一处能对错的地方。
	NetSession.remote_input[2] = bits

# ================================================================ 快照 (主机 -> 客户端)

func _process(delta: float) -> void:
	_pump_beacon(delta)
	_pump_listener(delta)

	if not NetSession.is_host() or game == null or not is_instance_valid(game):
		if NetSession.is_client():
			_update_managed_puppets(delta)
		return
	# **在客户端把世界建好之前一个包都不发。**
	#
	# 生成包是 reliable 的一次性事件 —— `_send_snapshot()` 给每个实体分配
	# net_id 时只广播一次, 之后再也不会重发。而客户端从收到开局种子到
	# main.tscn 建完有两秒以上 (加载贴图 + 建 174 块地形), 这期间 `game`
	# 还是 null, `_rpc_spawn` 会直接丢弃。
	#
	# 结果就是: **谁先加载完谁决定这局能不能玩。** 主机先加载完的话, 两辆
	# 玩家坦克的生成包在客户端还没准备好时就发完了, 客户端此后永远看不到
	# 它们 —— 一片有地图、有 HUD、但没有任何单位的空房间, 而且不报任何错。
	# 端到端测试没抓到它纯属运气: 那里主机先启动两秒, 磁盘缓存是冷的,
	# 每次都恰好是客户端先就绪。
	#
	# client_in_match 由客户端建完世界后的 notify_ready() 置位。等它之后,
	# 第一帧快照会把当时场上所有实体一次性登记并广播出去。
	if NetSession.remote_peer_id == 0 or not client_in_match:
		return

	_snapshot_accum += delta
	if _snapshot_accum >= NetSession.SNAPSHOT_DT:
		_snapshot_accum = 0.0
		_send_snapshot()

	_state_accum += delta
	if _state_accum >= 1.0 / STATE_HZ:
		_state_accum = 0.0
		_send_state()


## 没有 net_puppet 早退分支的傀儡 (友军坦克、玩家造的建筑、道具……) 由这里
## 代跑插值。有分支的那三类自己在 _physics_process 里跑, 不能在这里重复跑
## 一次 —— 一帧跑两次插值等于把收敛系数悄悄翻倍。
func _update_managed_puppets(delta: float) -> void:
	if not NetSession.is_client():
		return
	for id in NetSession.puppets:
		var n = NetSession.puppets[id]
		if not is_instance_valid(n):
			continue
		if not (int(n.get_meta("net_kind", NetSession.Kind.IGNORED)) in NetSession.SELF_DRIVEN_KINDS):
			NetPuppet.update(n, delta)


func _actors() -> Node:
	if game == null or not is_instance_valid(game):
		return null
	return game.get("actors_container")


## 主机侧: 扫一遍 actors_container, 把新出现的实体登记并下发 spawn,
## 把消失的下发 despawn, 剩下的编成一帧快照。
##
## 用"每帧比对"而不是挂 child_entered_tree 信号, 是因为这个项目里节点的
## 生成路径太多了 (main.gd 有 40 多个 _spawn_*, 子弹由 player/enemy 自己
## add_child, VFX 也往同一个容器里塞)。比对是唯一不会漏的做法, 代价是
## 生成最多晚一个快照周期 (33ms) 被看到 —— 对合作打坦克来说无所谓。
func _send_snapshot() -> void:
	var container := _actors()
	if container == null:
		return

	var seen := {}
	var entities: Array = []
	for child in container.get_children():
		var kind := NetSession.classify(child)
		if kind == NetSession.Kind.IGNORED:
			continue
		var nid: int = int(child.get_meta("net_id", 0))
		if nid == 0:
			nid = NetSession.alloc_net_id()
			child.set_meta("net_id", nid)
			_tracked[nid] = child
			spawns_sent += 1
			_rpc_spawn.rpc(nid, kind, NetSession.spawn_payload(child, kind))
		seen[nid] = true
		entities.append({
			"id": nid,
			"flags": _flags_of(child),
			"pos": (child as Node2D).position,
			"rot": (child as Node2D).rotation,
			"vel": _velocity_of(child, kind),
			"extra": _extra_of(child, kind),
		})

	var gone: Array = []
	for nid in _tracked:
		if not seen.has(nid):
			gone.append(nid)
	for nid in gone:
		_tracked.erase(nid)
		_rpc_despawn.rpc(nid)

	if not entities.is_empty():
		snapshots_sent += 1
		_rpc_snapshot.rpc(NetSession.encode_snapshot(entities))


func _flags_of(node: Node) -> int:
	var f := 0
	if node.get("is_invulnerable") == true:
		f |= NetSession.F_INVULNERABLE
	if node.get("is_dying") == true:
		f |= NetSession.F_DYING
	if node is CanvasItem and (node as CanvasItem).visible:
		f |= NetSession.F_VISIBLE
	# 只有玩家坦克有 can_fire。客户端拿它闸住开火反馈的预测 —— 没有这一位的话,
	# 冷却期间狂按开火键会一直播枪口火焰, 而主机一枪都没打出去。
	if node.get("can_fire") == true:
		f |= NetSession.F_CAN_FIRE
	return f


## 傀儡靠速度在两帧快照之间推算。坦克是 CharacterBody2D, 直接有 velocity;
## 子弹是 Area2D 手动移动的, 速度得从 direction*speed 现算。
func _velocity_of(node: Node, kind: int) -> Vector2:
	if kind == NetSession.Kind.BULLET:
		return node.direction * node.speed
	if node is CharacterBody2D:
		return (node as CharacterBody2D).velocity
	return Vector2.ZERO


## 快照里按类型解释的那个附加浮点数。
##
## 目前只有玩家坦克用: 主机这一帧算出来的有效移动速度, 客户端的本地预测
## 拿它当速度 (见 player.gd::_net_predict_step 里为什么不在客户端重算)。
func _extra_of(node: Node, kind: int) -> float:
	if kind == NetSession.Kind.PLAYER:
		return float(node.net_effective_speed)
	return 0.0


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn(nid: int, kind: int, payload: Dictionary) -> void:
	if not NetSession.is_client() or game == null or not is_instance_valid(game):
		return
	if NetSession.puppets.has(nid):
		return
	# SCENE_NODE 的场景路径在 payload 里 (节点自己的 scene_file_path),
	# 其余类型走固定表。
	var scene_path: String = String(payload.get("scene", "")) if kind == NetSession.Kind.SCENE_NODE \
		else String(NetSession.KIND_SCENE.get(kind, ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	var node = packed.instantiate()
	NetSession.apply_spawn_payload(node, kind, payload)
	NetPuppet.make_puppet(node, kind)
	# 自己那辆坦克走本地预测: 按本地输入立刻动, 再往权威位置回拉。
	# 其余所有实体 (包括队友那辆) 都是纯插值。
	if kind == NetSession.Kind.PLAYER and int(payload.get("pid", 0)) == NetSession.local_player_id:
		NetPuppet.make_predicted(node)
	node.set_meta("net_id", nid)
	NetSession.puppets[nid] = node
	var container := _actors()
	if container == null:
		node.queue_free()
		return
	container.add_child(node)
	# 客户端也要认得自己那辆坦克 —— HUD、摄像机跟随、树冠淡出都要用。
	if kind == NetSession.Kind.PLAYER and game.has_method("net_register_player_puppet"):
		game.net_register_player_puppet(node)


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn(nid: int) -> void:
	if not NetSession.is_client():
		return
	var node = NetSession.puppets.get(nid)
	NetSession.puppets.erase(nid)
	if is_instance_valid(node):
		node.queue_free()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(payload: Array) -> void:
	if not NetSession.is_client():
		return
	snapshots_recv += 1
	var records := NetSession.decode_snapshot(payload)
	for rec in records:
		var node = NetSession.puppets.get(int(rec["id"]))
		if not is_instance_valid(node):
			# spawn 走 reliable、快照走 unreliable, 两条通道不保证先后 ——
			# 认不出的 id 只是"生成包还在路上", 跳过就行, 下一帧就有了。
			continue
		NetPuppet.set_target(node, rec["pos"], rec["rot"], rec["vel"], rec["extra"], int(rec["flags"]))

# ================================================================ 非实体状态

func _send_state() -> void:
	if game == null or not is_instance_valid(game) or not game.has_method("net_collect_state"):
		return
	_rpc_state.rpc(game.net_collect_state())


@rpc("authority", "call_remote", "reliable")
func _rpc_state(state: Dictionary) -> void:
	if not NetSession.is_client():
		return
	states_recv += 1
	state_synced.emit(state)
	if game and is_instance_valid(game) and game.has_method("net_apply_state"):
		game.net_apply_state(state)

# ================================================================ 战役 (下行)
#
# 战役合作比街机多了一整层跨房间的状态: 幕数、金币、天赋、楼层图、当前房间、
# 商店货架。这一层**整份同步**, 不做增量 —— 而且用的就是存档那份字典
# (GameState.campaign_to_dict), 于是 tools/test_persistence_roundtrip.gd 那条
# "漏字段就变红"的保障顺带覆盖了联机同步。详见该函数顶部的注释。

## 主机: 战役状态变了 (清房、成交、事件结算……)。
func broadcast_campaign(d: Dictionary) -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_campaign.rpc(d)


@rpc("authority", "call_remote", "reliable")
func _rpc_campaign(d: Dictionary) -> void:
	if not NetSession.is_client() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_apply_campaign"):
		game.net_apply_campaign(d)


## 主机: 我要换房了, 你也换。
##
## room_seed 让两端用同一个种子建新房间的地形 —— 和开局那次用 match_seed
## 是同一条机制。d 是**换房之前**的战役状态: 客户端收下之后跑自己那份
## enter_room, 里面的 visit_room() 会做和主机完全相同的那次改动。
func broadcast_enter_room(d: Dictionary, room_seed: int, room_key: String, travel_dir: int) -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_enter_room.rpc(d, room_seed, room_key, travel_dir)


@rpc("authority", "call_remote", "reliable")
func _rpc_enter_room(d: Dictionary, room_seed: int, room_key: String, travel_dir: int) -> void:
	if not NetSession.is_client() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_enter_room"):
		game.net_enter_room(d, room_seed, room_key, travel_dir)

# ---------------------------------------------------------------- 商店 (上行)
#
# 成交和换货都是权威行为 (扣金币、发效果、改房间字典)。客户端开上货位时
# 只发意图, 主机跑的是它本地那条一模一样的 try_purchase() / try_reroll()。
#
# 请求带的是**槽位号**而不是坐标或物品 id: 两端的货架来自同一份
# room["shop_stock"], 顺序一致; 而坐标跨机器不可信 (GameArea 偏移随分辨率变),
# 物品 id 则会让客户端有机会"点名要买哪件", 绕开货架本身。

func request_buy(slot: int) -> void:
	if NetSession.is_client():
		_rpc_buy.rpc_id(1, slot)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_buy(slot: int) -> void:
	if not NetSession.is_host() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_apply_buy"):
		game.net_apply_buy(slot)


func request_reroll() -> void:
	if NetSession.is_client():
		_rpc_reroll.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_reroll() -> void:
	if not NetSession.is_host() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_apply_reroll"):
		game.net_apply_reroll()

# ---------------------------------------------------------------- 事件房
#
# 事件是**共享决策**: 收益落在整局的 GameState 上 (金币/天赋/命数/永久等级),
# 不属于某一个玩家。所以两边都看得到同一个事件框, 谁先点谁算, 主机去重。
#
# 和升级选卡的区别正在这里 —— 那个是"这张卡加在谁头上"的个人决策, 必须由
# 本人选; 事件是"这一局要走哪条路", 谁点都一样。

func broadcast_event(dialog_type: String, event_id: String) -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_event_show.rpc(dialog_type, event_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_event_show(dialog_type: String, event_id: String) -> void:
	if not NetSession.is_client() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_show_event"):
		game.net_show_event(dialog_type, event_id)


func broadcast_event_closed() -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_event_closed.rpc()


@rpc("authority", "call_remote", "reliable")
func _rpc_event_closed() -> void:
	if not NetSession.is_client() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_close_event"):
		game.net_close_event()


func request_event_choice(idx: int) -> void:
	if NetSession.is_client():
		_rpc_event_choice.rpc_id(1, idx)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_event_choice(idx: int) -> void:
	if not NetSession.is_host() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_apply_event_choice"):
		game.net_apply_event_choice(idx)

# ---------------------------------------------------------------- 升级选卡
#
# 联机战役里每个人在自己的屏幕上选自己的强化卡。卡面由主机生成 (RPGManager
# 只在主机这边跑), 发给远端玩家显示; 他回报的是**索引**而不是卡片内容 ——
# 客户端能决定的只有"选第几张", 决定不了那张卡是什么。

func send_upgrade_options(options: Array, pid: int) -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_upgrade_options.rpc(options, pid)


@rpc("authority", "call_remote", "reliable")
func _rpc_upgrade_options(options: Array, pid: int) -> void:
	if not NetSession.is_client() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_show_upgrade_options"):
		game.net_show_upgrade_options(options, pid)


func send_upgrade_pick(index: int, pid: int) -> void:
	if not NetSession.is_client():
		return
	_rpc_upgrade_pick.rpc_id(1, index, pid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_upgrade_pick(index: int, pid: int) -> void:
	if not NetSession.is_host() or game == null or not is_instance_valid(game):
		return
	if game.has_method("net_apply_remote_upgrade"):
		game.net_apply_remote_upgrade(index, pid)

# ================================================================ 地形销毁

## 主机侧: 一块可破坏地形没了。main.gd 在 map_container 的 child_exiting_tree
## 上调这里。格子坐标而不是节点路径 —— 两端的节点名不保证一致, 格子坐标
## 一定一致。
func notify_tile_gone(gx: int, gy: int, tag: String = "") -> void:
	if not NetSession.is_host() or _bulk_change or NetSession.remote_peer_id == 0:
		return
	_rpc_tile_gone.rpc(gx, gy, tag)


@rpc("authority", "call_remote", "reliable")
func _rpc_tile_gone(gx: int, gy: int, tag: String) -> void:
	if not NetSession.is_client():
		return
	if game and is_instance_valid(game) and game.has_method("net_remove_tile"):
		game.net_remove_tile(gx, gy, tag)


## 房间重建期间关掉地形事件, 见 _bulk_change 的声明。
func begin_bulk_change() -> void:
	_bulk_change = true


func end_bulk_change() -> void:
	_bulk_change = false

# ================================================================ 表现回声
#
# 客户端不跑逻辑, 所以它自己不会产生任何特效和音效。主机在生成它们的那个
# 收口函数里回声一份过来 —— VFXAnimator.create_anim() 和 SoundManager 的
# 两个合成器入口, 一共三个点, 覆盖了游戏里几乎全部的表现层。
#
# 走 unreliable: 掉一个爆炸特效不影响任何判定, 而为了它重传会挤占快照。

func echo_vfx(paths: Array, pos: Vector2, scale_factor: float, fps_val: float, rot: float) -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_vfx.rpc(paths, pos, scale_factor, fps_val, rot)


@rpc("authority", "call_remote", "unreliable", 2)
func _rpc_vfx(paths: Array, pos: Vector2, scale_factor: float, fps_val: float, rot: float) -> void:
	if not NetSession.is_client() or game == null or not is_instance_valid(game):
		return
	var container := _actors()
	if container == null:
		return
	var typed: Array[String] = []
	for p in paths:
		typed.append(String(p))
	var VFX = load("res://scripts/vfx_animator.gd")
	# 主机发的是 actors_container 的局部坐标 (见 VFXAnimator._net_echo 的
	# 理由), create_anim 要的是全局坐标, 这里转回去。
	var world_pos: Vector2 = pos
	if container is Node2D:
		world_pos = (container as Node2D).to_global(pos)
	# 这一份枪口火焰可能是本机刚才已经预测播过的那一发。见
	# NetSession.should_skip_muzzle_echo() —— 不去重的话同一枪会闪两次。
	if NetSession.should_skip_muzzle_echo(typed, world_pos):
		return
	VFX.create_anim(container, world_pos, typed, scale_factor, fps_val, rot)


func echo_sound(kind: String, args: Array) -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_sound.rpc(kind, args)


@rpc("authority", "call_remote", "unreliable", 2)
func _rpc_sound(kind: String, args: Array) -> void:
	if not NetSession.is_client():
		return
	var SM = load("res://scripts/sound_manager.gd")
	SM.net_replay(kind, args, get_tree())

# ================================================================ 结束

func end_match(victory: bool, score: int) -> void:
	if not NetSession.is_host() or NetSession.remote_peer_id == 0:
		return
	_rpc_end_match.rpc(victory, score)


@rpc("authority", "call_remote", "reliable")
func _rpc_end_match(victory: bool, score: int) -> void:
	match_ended.emit(victory, score)
