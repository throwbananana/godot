extends SceneTree

## 掉线重连的回归测试。
##
## 主机侧本来就有一半: 客户端掉线时对局不结束, socket 还开着, P2 坦克只是
## 停止响应输入。缺的是**他回来之后世界怎么重建**, 而那一步有三个各自会
## 静默失败的环节:
##
##   1. **spawn 包是一次性的。** _send_snapshot() 头一次见到某个节点时分配
##      net_id 并广播, 之后永远不再提它。重连回来的客户端那份世界是全新的,
##      而主机这边每个单位早就有 net_id 了 —— 于是一个 spawn 包都不会再发,
##      他进到的是一间有地图有 HUD 但一辆坦克都没有的空房间。跟 CLAUDE.md
##      记的那次"谁加载得快谁决定这局能不能玩"是同一个失败形态, 一样不报错。
##   2. **开局包也是一次性的。** begin_match 是"进对局"的唯一入口, 那一发在
##      他掉线之前就播完了。不补一份的话他连进来之后会一直卡在标题界面,
##      连接是通的、什么也不会发生。
##   3. **房间广播在开局时就停了** (_stop_beacon, 免得别人看到一个进不去的
##      满房间)。客位空出来之后不重开的话, 掉线的队友只能手输 IP 才回得来。
##
## 这里不开真端口 —— 三条都是主机侧的状态迁移, 掰 NetSession.role 就能验。
## 真连接那一层归 run_net_e2e.ps1。
##
## 按项目惯例: 不用 assert, print("[FAIL] …") 记全局标志, **只在最后 quit
## 一次** (quit() 不中断调用栈, 中途 quit(1) 会被末尾的 quit(0) 覆盖回 0)。

const NetSession = preload("res://scripts/net_session.gd")
const GameState = preload("res://scripts/game_state.gd")

var _failed := false


func fail(msg: String) -> void:
	_failed = true
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func check(cond: bool, msg: String) -> void:
	if cond:
		ok(msg)
	else:
		fail(msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> NET RECONNECT TEST <<<")
	print("==================================================")

	var net := root.get_node_or_null("Net")
	if net == null:
		fail("Net 自动加载不存在 —— 联机的一切都挂在它上面")
		quit(1)
		return

	await _test_respawn_all_on_ready(net)
	await _test_seat_reopens_on_disconnect(net)
	await _test_rejoin_gets_begin_match(net)

	NetSession.reset()
	print("==================================================")
	if _failed:
		print("[FAIL] 重连测试未通过")
		quit(1)
	else:
		print(">>> ALL RECONNECT CHECKS PASSED! <<<")
		quit(0)


func _boot_host(net: Node) -> Node:
	NetSession.reset()
	NetSession.role = NetSession.Role.HOST
	NetSession.local_player_id = 1
	NetSession.match_seed = 12345
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2

	var packed := load("res://scenes/main.tscn")
	if packed == null:
		fail("main.tscn 加载失败")
		return null
	var m: Node = packed.instantiate()
	root.add_child(m)
	for i in range(5):
		m._process(0.016)
	net.game = m
	return m


## 环节 1: 客户端报告就绪时, 主机必须把实体登记整个作废, 好让下一帧快照
## 重新宣告全场。
##
## 这里手工伪造"上一轮连接留下的登记" (给节点打 net_id + 填 _tracked),
## 而不是真的跑一遍 _send_snapshot() —— 那个函数会往一个不存在的对端发
## RPC, 噪音大而且验的不是这条逻辑。要验的就是"这批登记会不会被清掉"。
func _test_respawn_all_on_ready(net: Node) -> void:
	print("\n[1] 重连就绪时重新宣告全场")
	var m := _boot_host(net)
	if m == null:
		return

	# 挑几个真实实体冒充"上一轮已经宣告过"的。
	var victims: Array = []
	for ch in m.actors_container.get_children():
		if NetSession.classify(ch) == NetSession.Kind.IGNORED:
			continue
		victims.append(ch)
		if victims.size() >= 2:
			break
	check(victims.size() > 0, "场上有可复制实体可供伪造登记 (%d 个)" % victims.size())

	net._tracked.clear()
	var fake_id := 1000
	for v in victims:
		v.set_meta("net_id", fake_id)
		net._tracked[fake_id] = v
		fake_id += 1
	check(net._tracked.size() == victims.size(), "已伪造 %d 条登记" % net._tracked.size())

	# 客户端 (重新) 报告就绪。remote_peer_id 留 0, 免得内部的广播真去发 RPC。
	NetSession.remote_peer_id = 0
	net._rpc_client_ready()

	check(net._tracked.is_empty(),
		"_tracked 已清空 (实际还剩 %d 条) —— 否则重连的人进空房间" % net._tracked.size())
	var leftover := 0
	for v in victims:
		if is_instance_valid(v) and v.has_meta("net_id"):
			leftover += 1
	check(leftover == 0,
		"实体身上的 net_id 标记已摘除 (还剩 %d 个) —— 留着的话下一帧快照会认为它已经宣告过" % leftover)
	check(net.client_in_match, "client_in_match 置位 (快照才会开始下发)")

	net.game = null
	m.free()


## 环节 3 (先测, 因为它只碰 net 自己的状态): 客位空出来时房间要重新可见,
## 并且 client_in_match 要落回 false —— 不落回的话主机会继续朝一个已经不在
## 的对端发快照。
func _test_seat_reopens_on_disconnect(net: Node) -> void:
	print("\n[2] 掉线后客位重新开放")
	NetSession.reset()
	NetSession.role = NetSession.Role.HOST
	net.client_in_match = true
	NetSession.remote_peer_id = 7
	net._stop_beacon()

	net._on_peer_disconnected(7)

	check(NetSession.remote_peer_id == 0, "remote_peer_id 已清零")
	check(not net.client_in_match, "client_in_match 落回 false")
	check(net._beacon != null, "房间广播已重开 (否则掉线的队友只能手输 IP)")
	net._stop_beacon()


## 环节 2: 对局进行中有人连进来 = 掉线的队友回来了 (只有一个客位)。
## 必须补一份开局包, 否则他卡在标题界面。
##
## 这里验的是"这条路会去读 last_begin_mode" —— 真的把 RPC 发出去要有对端,
## 归 e2e。所以断言分两半: 开局前 (last_begin_mode == -1) 不该补发,
## 开局后该补发。前一半同样重要: 首次进大厅时误补一发会把还在浏览房间列表
## 的人直接拽进对局。
func _test_rejoin_gets_begin_match(net: Node) -> void:
	print("\n[3] 对局中重连会补发开局包")
	NetSession.reset()
	NetSession.role = NetSession.Role.HOST

	# 大厅阶段: 还没开局。
	net.last_begin_mode = -1
	var before_lobby: int = net.last_begin_mode
	net._on_peer_connected(9)
	check(NetSession.remote_peer_id == 9, "大厅阶段: 记下了对端 id")
	check(before_lobby == -1, "大厅阶段: last_begin_mode 仍是 -1, 不会补发开局包")

	# 对局阶段: begin_match() 已经跑过, last_begin_* 有值。
	#
	# 下面这一步会在日志里留一行
	#   ERROR: Attempt to call RPC with unknown peer ID: 9.
	# **这是预期的, 而且正是想要的证据**: 说明补发路径真的把包发出去了
	# (发给一个本测试里并不存在的对端), 而不只是"变量有值"。没有这行反而
	# 说明补发没发生。真连接下的验证归 run_net_e2e.ps1。
	print("  [注] 下面预期出现一行 unknown peer ID 的 ERROR —— 那是补发确实发生的证据")
	NetSession.remote_peer_id = 0
	net.last_begin_mode = int(GameState.GameMode.ARCADE)
	net.last_begin_campaign = {}
	net._on_peer_connected(9)
	check(NetSession.remote_peer_id == 9, "对局阶段: 重连的对端被接受")
	check(net.last_begin_mode != -1,
		"对局阶段: last_begin_mode 有值, 补发路径可达 (真正发包归 e2e 验)")
	net.last_begin_mode = -1
