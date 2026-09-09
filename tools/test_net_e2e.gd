extends SceneTree

## **真的开两个进程、真的连一次**的端到端测试。
##
## 前面两个测试 (test_netcode / test_net_runtime) 覆盖的是数据层和两条
## 单端代码路径, 它们都不碰 socket。可是联机最容易坏的地方恰恰在中间那一段:
## RPC 注解写错了权限、通道号冲突、傀儡生成在客户端拿不到场景、
## unreliable 包被静默丢弃 —— 这些在单端测试里全是绿的。
##
## 用法 (由 tools/run_net_e2e.ps1 驱动, 不要手动一个个开):
##   godot --headless --script tools/test_net_e2e.gd -- --host
##   godot --headless --script tools/test_net_e2e.gd -- --client
##
## 主机先起、等客户端连上才开局; 客户端连上后等主机的 begin_match。
## 两端各跑 RUN_SECONDS 秒真实对局, 然后各自打印结论并按 [FAIL] 决定退出码。

const NetSession = preload("res://scripts/net_session.gd")
const NetPuppet = preload("res://scripts/net_puppet.gd")
const GameState = preload("res://scripts/game_state.gd")
const BuilderControllerCls = preload("res://scripts/builder_controller.gd")
const ShopStandCls = preload("res://scripts/shop_stand.gd")

## 建造测试用的建筑。**特意挑导弹打击**: 它是唯一一个跳过落点合法性检查的
## (_try_place_current 里 `selection != MISSILE_STRIKE and not _is_placement_valid`),
## 所以这条断言不依赖坦克当时正朝着一格空地 —— 而坦克朝哪儿是上面预测测试
## 走完之后的残留状态, 不该由它决定建造测试红不红。
const BUILD_ID := "missile_strike"
const BUILD_STOCK := 3

const HOST_ADDRESS := "127.0.0.1"
## 故意不用 NetSession.DEFAULT_PORT: 测试跑的时候玩家自己那局游戏可能正开着,
## 撞端口会让测试以"无法监听"失败, 而那和代码没关系。
const E2E_PORT := 27115
## 街机趟和战役趟用**不同的端口**。
##
## 两趟是背靠背跑的, 上一趟的监听套接字在系统里还可能处在 TIME_WAIT,
## 下一趟去绑同一个端口就会失败 —— 表现是"客户端连上了但一个快照都收不到"
## (实测到过一次), 看着像复制层坏了, 其实是根本没连上同一个会话。
## 连续跑整套 e2e 时这个概率不低。战役趟用 E2E_PORT + 1, 见 _port()。
const CONNECT_TIMEOUT := 20.0
## 必须明显大于街机模式 3 秒的刷怪间隔, 否则"主机在刷怪 / 客户端看得到敌人"
## 这两条断言会随机变红。
## 主机的观测窗口。它同时是"客户端做完全部检查之前主机必须一直在线"的
## 时长下限 —— 客户端那边的本地预测验收要按住方向键探路、静置、再测响应,
## 加起来十几秒, 主机先退场的话客户端会在一个已经断掉的会话上做断言。
const RUN_SECONDS := 20.0
## 客户端做完断言之后多留一会儿再断开。
##
## 这不是"等一等更保险"的迷信, 是修一个具体的假失败: 两个进程的
## _enter_match() 耗时差了两秒多 (主机先启动, 磁盘缓存是冷的; 客户端加载
## 同一批资源快得多), 于是客户端的观测窗口整体比主机早结束, 它一走
## net.leave() 就让主机的 remote_input 被清空、快照停发 —— 主机那边报出来的
## 是"没收到输入包""快照才 69 帧", 看起来像联机坏了, 其实是测试自己拆的台。
## 下面的对齐 (双方都等第一个包到达再开始计时) 加上这段尾巴一起解决它。
const CLIENT_TAIL_SECONDS := 5.0
## 客户端的观测窗口**故意比主机短**。
##
## 两边的窗口即使对齐到同一帧开始, 客户端也会晚约一个快照周期结束 (它的
## 发令枪是"收到第一帧快照", 比主机的"收到 client_ready" 晚 33ms)。
## 主机一跑完就 leave(), 客户端立刻收到 server_disconnected 并跟着 reset,
## 于是客户端的断言全部落在一个已经清空的会话上 —— 现象是"一个傀儡都没有",
## 而 actors_container 里明明躺着 2 辆坦克 2 只敌人。留 2.5 秒余量。
const CLIENT_RUN_SECONDS := 4.0

var failures: int = 0
var campaign_mode: bool = false
var tag: String = "?"
var net: Node = null
var main_node: Node = null


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL][%s] %s" % [tag, msg])


func ok(msg: String) -> void:
	print("  [ok][%s] %s" % [tag, msg])


func check(cond: bool, msg: String) -> void:
	if cond:
		ok(msg)
	else:
		fail(msg)


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	net = root.get_node_or_null("Net")
	if net == null:
		print("[FAIL] 找不到 /root/Net 自动加载")
		quit(1)
		return
	campaign_mode = args.has("--campaign")
	if args.has("--lobby"):
		tag = "LOBBY-主机" if args.has("--host") else "LOBBY-客户端"
		await _run_lobby(args.has("--host"))
		if main_node and is_instance_valid(main_node):
			main_node.queue_free()
		net.leave()
		await process_frame
		print("==== %s DONE: %d failures ====" % [tag, failures])
		quit(1 if failures > 0 else 0)
		return
	# 三元表达式在这里不行: 两个分支都是 void 协程, GDScript 会先要求它们
	# 有返回值再谈 await。老老实实分支。
	if args.has("--host"):
		tag = "HOST-战役" if campaign_mode else "HOST"
		if campaign_mode:
			await _run_host_campaign()
		else:
			await _run_host()
	elif args.has("--client"):
		tag = "CLIENT-战役" if campaign_mode else "CLIENT"
		if campaign_mode:
			await _run_client_campaign()
		else:
			await _run_client()
	else:
		# tools/run_tests.ps1 是按 test_*.gd 通配的, 会把这个文件也捞进去。
		# 单独跑一端没有意义 (会挂在等对端上直到超时, 报成 TIMEOUT ——
		# 而 TIMEOUT 是这个项目里最难查的一种失败, 见 CLAUDE.md)。
		# 所以缺参数时干净地跳过, 而不是失败。
		print(">>> test_net_e2e 需要 --host / --client, 请用 tools/run_net_e2e.ps1 驱动。此次跳过。")
		quit(0)
		return

	if main_node and is_instance_valid(main_node):
		main_node.queue_free()
	net.leave()
	await process_frame

	print("==== %s DONE: %d failures ====" % [tag, failures])
	quit(1 if failures > 0 else 0)


## 等 predicate 变真, 或者超时。返回是否等到了。
func _await_until(predicate: Callable, timeout: float, what: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	fail("等待超时 (%.1fs): %s" % [timeout, what])
	return false


func _enter_match() -> void:
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	var packed := load("res://scenes/main.tscn")
	main_node = packed.instantiate()
	root.add_child(main_node)
	# --script 模式下没有"主场景", 而项目里不少脚本靠 get_tree().current_scene
	# 拿 MainGame (player.gd 取 rpg_mgr 就是这么拿的)。补上它, 否则这个测试
	# 跑的路径会和真游戏不一样。
	current_scene = main_node


## 把一次"按下并松开"真的送进输入系统, 于是 _unhandled_input 会像玩家按键
## 那样被调用。Input.action_press() 只改按键状态 (轮询读得到), 不产生事件,
## 所以事件驱动的建造热键测不到 —— 必须走 parse_input_event。
func _press_action(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


## **按真实时间跑, 不按帧数。**
##
## 第一版写的是 `t += 1.0/60.0` 每帧 —— headless 下没有垂直同步, 实测跑到
## 约 190fps, 于是"5 秒"实际只过了 1.6 秒真实时间, 比街机模式 3 秒的刷怪
## 间隔还短。测试于是报"主机根本不刷怪", 而主机其实完全正常。
## 联机的一切 (快照间隔、输入重发、刷怪) 都以真实时间计, 测试也必须。
func _run_frames(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


## 这一趟用哪个端口。街机趟和战役趟必须分开 —— 见 E2E_PORT 旁边的注释。
func _port() -> int:
	return E2E_PORT + (1 if campaign_mode else 0)

# ================================================================ 主机

func _run_host() -> void:
	print("==== HOST START ====")
	if not net.host_game("E2E-HOST", _port()):
		fail("开房失败: " + NetSession.last_error)
		return
	ok("已监听 %d" % _port())

	if not await _await_until(func(): return NetSession.remote_peer_id != 0, CONNECT_TIMEOUT, "客户端连入"):
		return
	ok("客户端已连入 (peer %d)" % NetSession.remote_peer_id)

	# 主机是建造库存的权威, 客户端的那份由状态包覆盖。开局前先给主机备点货,
	# 下面才测得到"客户端请求 -> 主机扣库存并建造"这条上行链路。
	GameState.structure_inventory = {}
	GameState.add_structure_stock(BUILD_ID, BUILD_STOCK)

	net.start_match(int(GameState.GameMode.ARCADE), {})
	_enter_match()

	# 观测窗口从"第一个客户端的包到达"开始计时, 不从进场景开始 ——
	# 两个进程加载 main.tscn 的耗时差得很远 (见 CLIENT_TAIL_SECONDS 的注释)。
	# 等的是 client_ready 而**不是**"收到过输入包": 客户端从连上那一刻就在发
	# 输入了, 但它还要两秒多才建完自己的世界。拿输入包当发令枪的话, 主机的
	# 观测窗口会整整早两秒开始, 于是主机先跑完先断开, 客户端的断言全部
	# 在一个已经被 reset 掉的会话上执行 —— 报出来是"一个傀儡都没有"。
	if not await _await_until(func(): return net.client_in_match, CONNECT_TIMEOUT, "客户端建完世界"):
		return
	net.inputs_recv = 0
	net.snapshots_sent = 0
	net.spawns_sent = 0
	ok("两端都已进场, 开始计时")

	await _run_frames(RUN_SECONDS)

	check(net.spawns_sent > 0, "发出了实体生成包 (%d 个)" % net.spawns_sent)
	check(net.snapshots_sent > 20, "持续发出了快照 (%d 帧)" % net.snapshots_sent)
	# 客户端的输入必须真的到了主机。它是整条链路里唯一一条"上行", 也是
	# 唯一一条 any_peer 的 RPC —— 权限注解写错的话只有这里会不动。
	# 断言用计数器而不是 remote_input.has(2): 后者会在对端断开时被清空,
	# 于是"测试跑完了"和"链路坏了"长得一模一样。
	check(net.inputs_recv > 0, "收到了客户端的输入包 (%d 个)" % net.inputs_recv)
	check(main_node.enemies_spawned > 0, "主机侧真的在刷怪 (%d 只)" % main_node.enemies_spawned)

	# 客户端的建造请求必须在**主机**这边真的扣掉库存 —— 库存是权威状态,
	# 客户端已经完全不碰自己那份了 (它只显示主机同步下来的数字)。
	# 少一个正好说明: 请求到了、主机执行了、而且只执行了一次。
	var left := GameState.get_structure_stock(BUILD_ID)
	check(left == BUILD_STOCK - 1, "客户端的建造请求在主机侧扣了 1 个库存 (%d -> %d)" % [BUILD_STOCK, left])

# ================================================================ 客户端

func _run_client() -> void:
	print("==== CLIENT START ====")
	if not net.join_game(HOST_ADDRESS, _port()):
		fail("连接失败: " + NetSession.last_error)
		return

	# `multiplayer` 是 Node 的属性, SceneTree 上没有 —— 从 root 取。
	var mp := root.multiplayer
	if not await _await_until(func(): return mp.has_multiplayer_peer() and mp.get_unique_id() > 1, CONNECT_TIMEOUT, "握手完成"):
		return
	ok("已连上主机 (本机 peer id = %d)" % mp.get_unique_id())

	if not await _await_until(func(): return NetSession.match_seed != 0, CONNECT_TIMEOUT, "主机开局"):
		return
	ok("收到开局种子 %d" % NetSession.match_seed)

	# **故意让客户端慢三秒再进场。**
	#
	# 这一段不是等待, 是一条回归断言。生成包是 reliable 的一次性事件, 谁也
	# 不会重发; 客户端 `game` 还是 null 的时候收到的会被直接丢掉。所以
	# "主机先加载完" 这个顺序会让客户端永远看不到那两辆坦克 —— 一片有地图、
	# 有 HUD、却没有任何单位的空房间, 不报任何错。
	#
	# 而默认情况下这个顺序**测不到**: 主机进程先启动两秒, 磁盘缓存是冷的,
	# 每次都恰好是客户端先就绪, 于是 bug 一直躲在运气后面。这里把顺序钉成
	# 最坏的那一种, 下面"两辆玩家坦克都出现了"那条断言才真的有意义。
	await _run_frames(3.0)
	_enter_match()

	# 和主机对齐: 从第一帧快照到达开始计时。
	net.snapshots_recv = 0
	if not await _await_until(func(): return net.snapshots_recv > 0, CONNECT_TIMEOUT, "主机开始推快照"):
		return
	ok("收到第一帧快照, 开始计时")

	await _run_frames(CLIENT_RUN_SECONDS)

	check(net.snapshots_recv > 20, "持续收到了快照 (%d 帧)" % net.snapshots_recv)
	check(NetSession.is_client(), "断言时会话仍然活着 (role=%d) —— 这条挂了说明主机先跑完并断开了, 下面的结论全部不作数" % NetSession.role)
	check(net.inputs_sent > 0, "本机发出了输入包 (%d 个)" % net.inputs_sent)

	var actor_kinds := {}
	for c in main_node.actors_container.get_children():
		var k := NetSession.classify(c)
		actor_kinds[k] = int(actor_kinds.get(k, 0)) + 1
	print("  [dbg][CLIENT] puppets=%d actors=%d kinds=%s role=%d" % [
		NetSession.puppets.size(), main_node.actors_container.get_children().size(),
		str(actor_kinds), NetSession.role])

	var players := 0
	var enemies := 0
	for id in NetSession.puppets:
		var n = NetSession.puppets[id]
		if not is_instance_valid(n):
			continue
		match int(n.get_meta("net_kind", -1)):
			NetSession.Kind.PLAYER: players += 1
			NetSession.Kind.ENEMY: enemies += 1
	check(players == 2, "两辆玩家坦克都以傀儡形式出现了 (实际 %d)" % players)
	check(enemies > 0, "敌人傀儡出现了 (%d 只)" % enemies)
	# is_instance_valid 而不是 != null: 会话被 reset 之后这两个引用会指向
	# 已经释放的对象, 而那时 `!= null` 仍然为真 —— 上一版就是这么绿着的,
	# 同时旁边的傀儡计数报 0。
	check(is_instance_valid(main_node.p1_instance) and is_instance_valid(main_node.p2_instance),
		"p1_instance / p2_instance 被接到了傀儡上 (摄像机跟随和 HUD 靠它们)")

	# 傀儡必须**在动**。只检查"存在"是不够的 —— 快照解码错了、
	# set_target 没生效、插值系数写成 0, 这三种情况下傀儡都会好端端地
	# 停在原地, 而"存在"检查一样是绿的。
	var sample: Node2D = null
	for id in NetSession.puppets:
		var n = NetSession.puppets[id]
		if is_instance_valid(n) and int(n.get_meta("net_kind", -1)) == NetSession.Kind.ENEMY:
			sample = n
			break
	if sample == null:
		fail("没有可用来验证移动的敌人傀儡")
	else:
		var p0: Vector2 = sample.position
		await _run_frames(1.5)
		if not is_instance_valid(sample):
			ok("采样的敌人傀儡在观察期内被主机销毁了 —— 说明 despawn 也通了")
		else:
			check(sample.position.distance_to(p0) > 1.0,
				"敌人傀儡在动 (位移 %.1f px)" % sample.position.distance_to(p0))

	check(main_node.score >= 0 and main_node._net_enemies_left >= 0, "状态包已应用到 HUD")
	check(not main_node.hud_enemies.text.is_empty(), "HUD 剩余敌人有内容: %s" % main_node.hud_enemies.text)

	await _check_prediction()


## 本地预测的验收。
##
## 这一段的断言方式是刻意选的: **按下方向键之后只放行两个物理帧, 就要求
## 坦克已经动了。** 没有预测的话这在物理上不可能 —— 输入要先发给主机、
## 主机跑一帧、结果编进下一个快照 (最长 33ms) 再传回来, 怎么也不止两帧。
## 所以这条断言真正测的是"预测在生效", 而不是"坦克能动"。
##
## 光测响应还不够: 一个只往前冲、永远不对账的预测同样能通过上面那条。
## 所以第二条测持续移动一秒之后本地位置和权威位置的偏差 —— 它同时否掉
## "预测跑飞了"和"回拉把预测压死了"两种坏法。
func _check_prediction() -> void:
	print("  ---- 本地预测 ----")
	var own: Node2D = null
	for id in NetSession.puppets:
		var n = NetSession.puppets[id]
		if not is_instance_valid(n):
			continue
		if int(n.get_meta("net_kind", -1)) == NetSession.Kind.PLAYER \
			and int(n.player_id) == NetSession.local_player_id:
			own = n
			break
	if own == null:
		fail("找不到本机操作的那辆坦克 (player_id=%d)" % NetSession.local_player_id)
		return

	check(NetPuppet.is_predicted(own), "自己那辆坦克被标成了本地预测")
	var spd := float(own.get_meta("net_speed", 0.0))
	check(spd > 0.0, "主机在快照里下发了有效速度 (%.1f px/s)" % spd)

	# --- 第一步: 找一个走得通的方向。出生点四周未必哪面都空 (基地钢墙、砖块)。
	#
	# 每个方向按满 0.6 秒: 要的是"这个方向确实能走", 用的是**权威**的结果,
	# 所以必须给输入留够一个来回。
	var chosen := ""
	for act in ["p1_move_up", "p1_move_left", "p1_move_right", "p1_move_down"]:
		var p0: Vector2 = own.position
		Input.action_press(act)
		await _run_frames(0.5)
		var d := own.position.distance_to(p0)
		Input.action_release(act)
		await _run_frames(0.5)
		if d > 8.0:
			chosen = act
			break
	if chosen == "":
		fail("四个方向各按 0.6 秒都没走动 —— 出生点被完全堵死, 或者输入根本没到主机")
		return
	ok("选定测试方向 %s" % chosen)

	# --- 第二步: 确认坦克真的停住了。
	#
	# 这一步是上一版缺的, 而缺了它整个测试就是假的。第一版直接在探测循环里
	# 数"按下两帧后动了多少", 结果**关掉预测照样通过** —— 因为探测时按过的
	# 那几下正在路上, 主机隔了一个来回才响应, 于是插值中的傀儡本来就在动,
	# 测出来的位移根本不是这一次按键造成的。
	# 先静止, 才能把"这两帧的位移"归因给"刚按下的这一次"。
	await _run_frames(0.8)
	var rest0: Vector2 = own.position
	await physics_frame
	await physics_frame
	var residual := own.position.distance_to(rest0)
	if residual > 0.2:
		fail("坦克没有真正静止 (两帧仍移动 %.2f px), 下面的响应测量不可信" % residual)
		return
	ok("坦克已静止 (两帧残余位移 %.3f px)" % residual)

	# --- 第三步: 决定性的一测。
	#
	# 从静止开始按下方向键, 只放行两个物理帧 (33ms)。没有预测的话这在物理上
	# 不可能有位移: 输入要发给主机、主机跑一帧、结果编进下一个快照 (最长
	# 33ms) 再传回来。所以这条断言测的就是"预测在生效"本身。
	var p_before: Vector2 = own.position
	Input.action_press(chosen)
	await physics_frame
	await physics_frame
	var immediate := own.position.distance_to(p_before)
	check(immediate > 0.5, "从静止按下 %s 后两个物理帧内就动了 (%.2f px) —— 关掉预测这里是 0" % [chosen, immediate])

	# --- 第四步: 持续移动时不能跑飞, 也不能被回拉压死。
	var start: Vector2 = own.position
	await _run_frames(1.0)
	var travelled := own.position.distance_to(start)
	var authoritative: Vector2 = own.get_meta("net_tpos", own.position)
	var drift := own.position.distance_to(authoritative)
	Input.action_release(chosen)

	check(travelled > 20.0, "持续按住一秒真的走了一段 (%.1f px)" % travelled)
	# 偏差小**同时**又走了一段, 才说明主机那边的坦克也在跟着走: 权威位置就是
	# 主机的 P2 位置, 它不动的话偏差会一路涨到触发硬归位。
	check(drift < NetSession.PREDICT_SNAP_DIST / 2.0,
		"预测位置和权威位置仍然贴合 (偏差 %.1f px < %.0f)" % [drift, NetSession.PREDICT_SNAP_DIST / 2.0])

	await _check_fire_feedback(own)
	await _check_build_request()


## 开火反馈的预测。
##
## 和位移预测同一种测法: 从静止 (没按过开火键) 开始按下, 只放行两个物理帧,
## 要求枪口火焰已经出现在场上。没有预测的话这不可能 —— 输入要发到主机、
## 主机开火、特效回声再传回来, 一个来回加一个快照周期都不止。
##
## 顺带钉住那道闸: 主机说不能开火 (F_CAN_FIRE 没置位) 时不许有本地反馈,
## 否则冷却期间按住不放会一路闪光而主机一枪没出。
func _check_fire_feedback(own: Node2D) -> void:
	print("  ---- 开火反馈预测 ----")
	var flags := int(own.get_meta("net_flags", 0))
	check((flags & NetSession.F_CAN_FIRE) != 0, "主机下发了'可以开火'位")

	# 只数**自己枪口附近**的火焰。
	#
	# 数全场是不行的: 敌人开火也走 spawn_muzzle_flash, 而那些火焰会随主机的
	# 回声不断生灭。实测撞见过一次 (2 -> 2) —— 本机确实预测出了一团火焰,
	# 同一瞬间一团敌人的火焰播完消失了, 总数纹丝不动, 报出来是"预测没生效"。
	# 噪声源和被测量的东西混在同一个计数里, 断言就不成立。
	var muzzle: Vector2 = own.global_position + own.facing_direction * 28.0
	var before := _muzzle_flash_count_near(muzzle)
	Input.action_press("p1_fire")
	await physics_frame
	await physics_frame
	var after := _muzzle_flash_count_near(muzzle)
	Input.action_release("p1_fire")
	check(after > before, "按下开火键两个物理帧内自己枪口就闪了 (%d -> %d)" % [before, after])

	# 闩住了: 同一个冷却周期内再按不会又闪一次。
	var latched := _muzzle_flash_count_near(muzzle)
	Input.action_press("p1_fire")
	await physics_frame
	Input.action_release("p1_fire")
	check(_muzzle_flash_count_near(muzzle) <= latched,
		"同一个冷却周期内没有连闪 (%d -> %d)" % [latched, _muzzle_flash_count_near(muzzle)])
	await _run_frames(1.0)


## 指定位置附近的枪口火焰数量。VFXAnimator 建出来的节点没有脚本路径可认,
## 用它第一帧贴图的路径来认最直接。
func _muzzle_flash_count_near(pos: Vector2, radius: float = 48.0) -> int:
	var n := 0
	if main_node == null or not is_instance_valid(main_node):
		return 0
	for c in main_node.actors_container.get_children():
		if c.has_meta("net_id") or not (c is Node2D):
			continue
		if (c as Node2D).global_position.distance_to(pos) > radius:
			continue
		var frames = c.get("frame_textures")
		if frames is Array and frames.size() > 0 and frames[0] != null:
			if str(frames[0].resource_path).contains("muzzle_flash"):
				n += 1
	return n


## 客户端建造的验收 (客户端这一半; 主机那半在 _run_host 里查库存)。
##
## 客户端**完全不碰自己那份库存**了 —— 它显示的、判断"能不能选"用的, 都是
## 主机随状态包同步下来的数字。所以"请求之后本地库存少了 1"这件事本身就
## 证明了整条链路: 请求上行到主机、主机执行并扣账、新数字再同步回来。
## 客户端自己减一是做不到这个的。
func _check_build_request() -> void:
	print("  ---- 建造请求 ----")
	var builder = main_node.builder_ctrl
	if builder == null or not is_instance_valid(builder):
		fail("客户端没有 BuilderController")
		return

	var before := GameState.get_structure_stock(BUILD_ID)
	check(before == BUILD_STOCK, "建造库存已从主机同步下来 (%s x%d)" % [BUILD_ID, before])
	if before <= 0:
		return

	# 走**真实的按键路径**, 不直接调 select_structure/_try_place_current。
	#
	# 这一段专门盯着键位槽和玩家号的错配: 客户端屏幕前的人按的是 p1_* 键位,
	# 开的却是 2 号车。直接按槽位当玩家号的话 (最自然的写法, 也是原来的写法),
	# 他的选择会记在本机 1 号车名下, request_select 同步不出去, 按放置键
	# 什么都不会发生 —— 而直接调函数的测试完全看不到这个 bug。
	_press_action("p1_build_next")
	await _run_frames(0.3)
	var sel := int(builder.selection_by_pid.get(NetSession.local_player_id, -1))
	check(sel == int(BuilderControllerCls.StructureType.MISSILE_STRIKE),
		"p1_* 键位选中的是本机操作的那号车 (pid=%d, 选择=%d)" % [NetSession.local_player_id, sel])

	_press_action("p1_build_place")
	# 等一个状态包周期以上 (6Hz), 让主机执行完并把新库存同步回来。
	await _run_frames(1.2)

	var after := GameState.get_structure_stock(BUILD_ID)
	check(after == before - 1, "主机执行了建造并把扣完的库存同步回来 (%d -> %d)" % [before, after])

	# 别比主机先断开 —— 见 CLIENT_TAIL_SECONDS 的注释。
	await _run_frames(CLIENT_TAIL_SECONDS)


# ================================================================ 战役合作

## 客户端存档里的哨兵金币数。用一个不可能自然出现的值, 这样"存档没被改"
## 这条断言不会被巧合蒙混过去。
const SENTINEL_GOLD := 987654


func _enter_campaign_match() -> void:
	var packed := load("res://scenes/main.tscn")
	main_node = packed.instantiate()
	root.add_child(main_node)
	current_scene = main_node


func _run_host_campaign() -> void:
	print("==== HOST 战役 START ====")
	if not net.host_game("E2E-HOST", _port()):
		fail("开房失败: " + NetSession.last_error)
		return
	if not await _await_until(func(): return NetSession.remote_peer_id != 0, CONNECT_TIMEOUT, "客户端连入"):
		return
	ok("客户端已连入")

	# 走大厅那条真实路径: 开新的一局双人战役, 先把楼层图生成好再随开局包下发。
	GameState.reset_campaign(2)
	GameState.ensure_floor_ready()
	check(GameState.has_floor(), "主机侧楼层图已生成 (%d 间房)" % GameState.floor_rooms.size())
	var start_room := GameState.current_room
	net.start_match(int(GameState.GameMode.CAMPAIGN), GameState.campaign_to_dict())
	_enter_campaign_match()

	if not await _await_until(func(): return net.client_in_match, CONNECT_TIMEOUT, "客户端建完世界"):
		return
	ok("两端都已进场 (起始房 %s)" % start_room)
	await _run_frames(2.0)

	# 起始房是非战斗房, 一进来就算清空, 门是开着的 —— 所以可以直接走。
	var room := GameState.current_room_data()
	var dir := -1
	for d in range(4):
		if bool(room["doors"][d]) and GameState.can_exit(GameState.current_room, d):
			dir = d
			break
	if dir < 0:
		fail("起始房一扇能走的门都没有 —— 楼层图生成有问题")
		return

	# 走真实路径 _on_door_entered(), 而不是直接调 _transition_to_room:
	# 前者才会经过"客户端不许自己换房"那道闸 (见 main.gd 里的注释)。
	main_node._on_door_entered(dir)
	await _run_frames(3.0)

	check(GameState.current_room != start_room,
		"主机换到了新房间 (%s -> %s)" % [start_room, GameState.current_room])
	check(main_node.map_container.get_children().size() > 0, "新房间的地形建出来了")

	# 远端玩家的升级选卡。直接把队列摆成"只等 2 号", 免得先弹出主机自己那张
	# 本地卡面把测试卡住 —— 这里要验的是**远端**那条路。
	var queue: Array[int] = [2]
	main_node.pending_upgrade_players = queue
	main_node._show_next_upgrade()
	check(paused, "主机在等对方选卡期间暂停了战场 (不暂停的话对方选卡时会被打死)")
	if not await _await_until(func(): return not paused, 30.0, "对方选完卡并回报"):
		return
	check(main_node.pending_upgrade_players.is_empty(), "选卡队列已清空")
	var branch := str(main_node.rpg_mgr.get_branch(2))
	check(branch != "default", "对方选的流派在主机侧真的生效了 (%s)" % branch)

	await _shop_purchase_host_side()
	await _event_host_side()
	await _run_frames(RUN_SECONDS)


## 事件房: 客户端答题, 主机结算。
##
## 重点在**去重**: 事件是共享决策, 两个人都能点, 而奖励落在整局的 GameState
## 上。结算两遍就是金币加两次、天赋给两层, 而且不报错。客户端会连点两次,
## 这里断言只结算了一次。
func _event_host_side() -> void:
	print("  ---- 事件房: 客户端答题 ----")
	# **把某间房强制改成事件房, 而不是碰运气找一间。**
	#
	# 商店有保底 (FloorMap._assign_types 里那条 fallback), 事件房没有 —— 相当
	# 比例的楼层一间都没有。第一版就是"找不到就跳过", 结果这一整段覆盖是
	# 随机生效的: 跑十次可能有六次什么都没测, 而它绿得和真跑过一模一样。
	# 房间类型只是字典里一个字段, 改它比赌布局可靠得多。
	var ev_key := ""
	for k in GameState.floor_rooms.keys():
		var kk := str(k)
		if kk != GameState.current_room and kk != GameState.floor_start_room and kk != GameState.floor_boss_room:
			ev_key = kk
			break
	if ev_key == "":
		fail("找不到一间可以改成事件房的房间")
		return
	GameState.floor_rooms[ev_key]["type"] = "event"
	GameState.floor_rooms[ev_key]["cleared"] = false
	ok("已把 %s 强制改成事件房" % ev_key)

	# 基线必须在换房**之前**取。客户端就在旁边并发跑, 完全可能在主机走完
	# 2.5 秒观察窗之前就答完了题 —— 上一版在换房之后才取基线, 于是奖励
	# 早已到账, 四个增量全是 0, 报出来是"事件没发奖励"。
	var before := _reward_signature()

	_transition_to_shop(ev_key)  # 同一条换房路径, 只是目标是事件房

	# 同理: **不**断言"框现在还开着"。客户端可能已经答完并让主机收了框,
	# 那是链路正常工作的表现, 不是失败。用计数器判定结果, 不用时序。
	if not await _await_until(func(): return main_node._net_remote_events_resolved >= 1, 30.0, "客户端答题并由主机结算"):
		return
	check(not main_node.event_dialog.visible, "结算后主机侧事件框收起")
	check(not main_node._net_event_open, "'未结算事件'标志已清掉")

	# 客户端故意连点了两次。再等一会儿, 确认第二次确实被丢掉了 ——
	# 共享奖励结算两遍不会报任何错, 只会让这一局凭空多一份收益。
	await _run_frames(2.0)
	check(main_node._net_remote_events_resolved == 1,
		"重复的事件选择被丢弃了 (结算次数 = %d, 期望 1)" % main_node._net_remote_events_resolved)

	var after := _reward_signature()
	check(after != before, "事件确实发放了奖励 (%s -> %s)" % [str(before), str(after)])


## 事件可能发放的**全部**收益。
##
## 第一版只盯了金币/血上限/攻击/命四项, 于是随机抽到发天赋的那几个选项时
## (singularity 的 Warp Drive、glacier_cache 的 Frost Cleats、bounty 的两项)
## 四项全是 0, 报出来是"事件没发奖励" —— 而事件其实工作得好好的。
## 随机化的前置条件又一次把不完整的断言变成了间歇性假失败。
## 这里按 _on_choice 里实际会动的字段逐个列全, 天赋按总层数计。
func _reward_signature() -> Array:
	var perk_stacks := 0
	for d in [GameState.unlocked_perks, GameState.p2_unlocked_perks]:
		for k in d:
			perk_stacks += int(d[k])
	return [
		GameState.gold, GameState.max_hp_lvl, GameState.atk_bonus,
		GameState.player_lives, GameState.speed_lvl, GameState.fire_rate_lvl,
		GameState.player_tier, GameState.branch_tier, perk_stacks,
	]


## 主机把两人挪进商店房, 备好金币, 然后等客户端下单。
##
## 直接 _transition_to_room 到商店房而不是一路走过去: 楼层图是随机的, 商店
## 可能在三道门之外, 而这段要测的是"客户端能不能买", 不是寻路。
func _shop_purchase_host_side() -> void:
	print("  ---- 商店: 客户端下单 ----")
	var shop_key := ""
	for k in GameState.floor_rooms.keys():
		if str(GameState.floor_rooms[k].get("type", "")) == "shop":
			shop_key = str(k)
			break
	if shop_key == "":
		fail("这一层没有商店房 —— FloorMap 保证过每层必有 (见 CLAUDE.md 商店保底)")
		return

	GameState.gold = 9999
	_transition_to_shop(shop_key)
	await _run_frames(2.5)

	var stands := _shop_stands()
	check(stands.size() > 0, "商店房摆出了 %d 个货位" % stands.size())
	if stands.is_empty():
		return
	# 这里**不**断言"0 号货位一开始没卖出": 客户端可能已经先一步下单了
	# (两端是并发的), 那条断言纯粹是在赌时序。真正说明问题的是下面两条 ——
	# 钱扣了、房间字典标记了。

	# 客户端会在它那边开上 0 号货位并发请求。等主机这边真的成交。
	if not await _await_until(func(): return _stand_sold(0), 30.0, "客户端的成交请求到达并执行"):
		return
	check(GameState.gold < 9999, "主机扣了金币 (剩 %d)" % GameState.gold)
	check(bool(GameState.current_room_data()["shop_stock"][0]["sold"]), "房间字典里 0 号货位已标记售出")


func _transition_to_shop(shop_key: String) -> void:
	# 借用换房那条路径, 但绕开"必须相邻"的限制 —— 测试要的是到达商店房。
	main_node._transition_to_room(shop_key, 0)


func _shop_stands() -> Array:
	var out: Array = []
	for c in main_node.map_container.get_children():
		if c is ShopStandCls:
			out.append(c)
	out.sort_custom(func(a, b): return int(a.slot_index) < int(b.slot_index))
	return out


func _stand_sold(slot: int) -> bool:
	for c in main_node.map_container.get_children():
		if c is ShopStandCls and int(c.slot_index) == slot:
			return bool(c.sold)
	return false


func _run_client_campaign() -> void:
	print("==== CLIENT 战役 START ====")

	# 先在这台机器上留一份**自己的**战役存档。整个测试的重点之一就是它
	# 一个字节都不能被联机改动 —— 联机战役里客户端的 GameState 装的是主机
	# 那一局, 而 save_campaign() 每过一道门就会被 visit_room() 调一次。
	GameState.reset_campaign(1)
	GameState.gold = SENTINEL_GOLD
	GameState.save_campaign()
	var my_backup := GameState.campaign_to_dict()
	ok("已写入本机存档哨兵 (gold=%d)" % SENTINEL_GOLD)

	if not net.join_game(HOST_ADDRESS, _port()):
		fail("连接失败: " + NetSession.last_error)
		return
	var mp := root.multiplayer
	if not await _await_until(func(): return mp.has_multiplayer_peer() and mp.get_unique_id() > 1, CONNECT_TIMEOUT, "握手完成"):
		return

	# 轮询 last_begin_campaign 而不是接 match_begin 信号。
	#
	# 开局包是 reliable 的一次性事件, 而这个测试是在握手完成**之后**才有机会
	# 接信号的 —— 主机那边一看到 peer_connected 就立刻开局, 包可能比这行代码
	# 先到, 信号就白接了 (实测就是这样超时的)。真正的大厅不受影响, 它在
	# open_dialog() 里、连接之前就接好了。net_manager 把最后一个开局包存下来,
	# 正是为了让后接的人也读得到。
	if not await _await_until(func(): return not net.last_begin_campaign.is_empty(), CONNECT_TIMEOUT, "主机开局并下发战役状态"):
		return
	if not NetSession.has_campaign_backup:
		NetSession.client_campaign_backup = my_backup
		NetSession.has_campaign_backup = true
	GameState.campaign_from_dict(net.last_begin_campaign)
	GameState.player_count = 2
	check(int(GameState.mode) == int(GameState.GameMode.CAMPAIGN), "客户端进入了战役模式")
	check(GameState.has_floor(), "客户端接管了主机的楼层图 (%d 间房)" % GameState.floor_rooms.size())
	check(GameState.gold != SENTINEL_GOLD, "客户端的内存状态已被主机那一局覆盖 (gold=%d)" % GameState.gold)

	var start_room := GameState.current_room
	_enter_campaign_match()
	if not await _await_until(func(): return net.states_recv > 0, CONNECT_TIMEOUT, "收到主机的状态包"):
		return
	ok("已进场并开始收状态包")

	# 主机会在几秒内走过一道门。
	if not await _await_until(func(): return GameState.current_room != start_room, 20.0, "跟着主机换房"):
		return
	ok("跟着主机换到了新房间 (%s -> %s)" % [start_room, GameState.current_room])
	await _run_frames(2.0)

	check(main_node.map_container.get_children().size() > 0, "新房间的地形在客户端也建出来了")
	check(NetSession.map_checksum != 0, "新房间算出了地形校验和 (%d)" % NetSession.map_checksum)
	# 这一条是两端地图一致的实证: 主机把自己的校验和放进状态包, 对不上时
	# main.gd::net_apply_state 会置 _net_map_warned 并报错。
	check(net.states_recv > 0, "确实收到过状态包 (%d 个), 校验和比对真的执行了" % net.states_recv)
	check(not main_node._net_map_warned, "换房之后两端的地形校验和一致 (没有触发不一致告警)")

	# 远端选卡: 主机把该我选的卡面发过来, 我在**自己**的屏幕上选。
	var dlg = main_node.upgrade_dialog
	if dlg == null or not is_instance_valid(dlg):
		fail("客户端没有升级对话框")
		return
	if not await _await_until(func(): return dlg.visible, 30.0, "收到主机发来的升级卡面"):
		return
	check(dlg.cards_data.size() > 0, "卡面有 %d 张" % dlg.cards_data.size())
	check(int(dlg.current_player_id) == 2, "卡面是发给本机这号车的 (pid=%d)" % int(dlg.current_player_id))
	check(paused, "选卡期间本地也暂停了")

	dlg._on_remote_card_picked(0, 2)
	await _run_frames(1.5)
	check(not dlg.visible, "选完之后对话框关闭")
	check(not paused, "选完之后本地恢复运行")

	await _shop_purchase_client_side()
	await _event_client_side()

	# **"客户端不写盘"这条断言不在这里。**
	#
	# 两个测试进程是同一个 Godot 项目, 因此共用同一个 user:// 目录, 也就是
	# 同一份 campaign_save.json —— 而主机在联机战役里**本来就该**存盘。
	# 于是"文件里是主机的数据"既可能是客户端违规写入, 也可能是主机正常存档,
	# 这个测试位置根本分辨不了 (第一版就是这么误报的: 盘上 gold=150,
	# 那是主机 reset_campaign 的默认值, 客户端一个字节都没写)。
	# 真正的断言放在 tools/test_netcode.gd 的单进程测试里, 那里没有第二个
	# 进程来搅局。

	# 会话结束时, 内存里那份 GameState 也要还原回自己的。
	net.leave()
	await process_frame
	check(GameState.gold == SENTINEL_GOLD,
		"退出联机之后内存里的 GameState 还原成了自己的 (gold=%d)" % GameState.gold)


## 客户端这一半的商店测试。
##
## **不能靠"把坦克瞬移到货位上"来触发 body_entered。** 第一版是那么写的,
## 结果 30 秒超时: 客户端那辆是**预测**坦克, 每个物理帧末尾 NetPuppet.reconcile
## 都会把它拉回权威位置, 而瞬移过去的距离远超 PREDICT_SNAP_DIST, 于是直接
## 硬归位 —— 物理引擎还没来得及检测重叠, 车已经回去了。
##
## 也不能让主机把 P2 挪到货位上: 那样主机自己那个货位会先触发本地成交,
## 这条断言就会**因为错误的原因**变绿 (测的是主机买, 不是客户端买)。
##
## 所以这里直接调客户端货位的 _on_body_entered, 覆盖"联机分支是否正确地
## 只发请求、不本地成交"这段判断, 再靠主机侧的断言 (扣钱 + 房间字典标记)
## 证明请求真的到了并被执行。至于"预测坦克身上有没有碰撞"这个前提, 由上面
## 那段本地预测的测试负责 (它撞墙停住了)。
func _shop_purchase_client_side() -> void:
	print("  ---- 商店: 本机下单 ----")
	# 等的是"**0 号货位存在且有效**", 不是"货位数量 > 0"。
	#
	# 两者的差别是一次真实的间歇失败: 商店货位会被 _rebuild_shop_stands()
	# 整批 queue_free 再重建 (主机每推一次战役状态就来一遍), 只采样一次
	# "有没有货位"再去找 0 号, 就可能落在那个批次之间 —— 报出来是
	# "客户端找不到 0 号货位", 看着像复制坏了, 其实只是采样时机不巧。
	# 把条件合成一个再轮询, 这个窗口就不存在了。
	# 条件里必须带上"而且还没卖出"。只等"0 号货位存在"的话, 采样可能落在
	# 一个已经售出的货位上 (货架会被 _rebuild_shop_stands 反复整批重建),
	# 于是下面 _on_body_entered 因为 sold 提前 return, 什么请求都没发,
	# 断言却报"客户端本地成交了" —— 诊断和真相完全不沾边。
	# 前置条件要么等到, 要么就该超时喊出来, 而不是默认它成立。
	if not await _await_until(
			func():
				var s = _client_stand(0)
				return s != null and not bool(s.sold),
			30.0, "跟着主机进入商店房并看到未售出的 0 号货位"):
		print("  [dbg][CLIENT] room=%s type=%s 收到换房=%d is_transitioning=%s paused=%s map_children=%d stands=%d" % [
			GameState.current_room,
			str(GameState.current_room_data().get("type", "?")),
			main_node._net_rooms_entered,
			str(main_node.is_transitioning), str(paused),
			main_node.map_container.get_children().size(),
			_client_shop_stands().size()])
		# 货架为空是这条超时最常见的原因, 而它和"没进对房间"是两回事。
		var st = GameState.current_room_data().get("shop_stock", null)
		print("  [dbg][CLIENT] shop_stock=%s" % ("无" if st == null else str(st)))
		return
	ok("商店房在客户端也摆出了 %d 个货位" % _client_shop_stands().size())
	check(GameState.gold > 0, "金币数已从主机同步下来 (%d)" % GameState.gold)

	var target = _client_stand(0)
	check(target.monitoring, "客户端的货位仍然可交互 (monitoring 开着), 才谈得上开上去成交")

	# 直接把自己那辆坦克摆到货位上。走位过去更真实, 但商店房的布局是随机的,
	# 让测试去寻路只会引入另一种随机失败。
	var own: Node2D = null
	for id in NetSession.puppets:
		var n = NetSession.puppets[id]
		if is_instance_valid(n) and int(n.get_meta("net_kind", -1)) == NetSession.Kind.PLAYER \
			and int(n.player_id) == NetSession.local_player_id:
			own = n
			break
	if own == null:
		fail("找不到本机那辆坦克")
		return

	# 关键的一条: 客户端**没有**本地成交。它要是自己扣了钱、自己把货位置成
	# 售出, 两台机器的账当场就分家了 —— 而且不会有任何报错。
	#
	# 断言必须**同步**紧跟调用, 中间不能 await: 本机回环下"发请求->主机成交
	# ->推战役状态->客户端重建货位"可以在一帧之内跑完, 隔一个 physics_frame
	# 再看, target 已经被重建换掉了, 读到的是新货位的 sold=true —— 于是这条
	# 断言会因为链路**正常工作**而变红 (上一版就是这样)。
	target._on_body_entered(own)
	check(not bool(target.sold), "客户端没有本地成交 (只发了请求)")

	if not await _await_until(func(): return _client_stand_sold(0), 25.0, "主机执行成交并把结果同步回来"):
		return
	ok("0 号货位在客户端也显示为已售出 —— 整条上行链路通了")


## 事件房客户端这一半: 主机把事件框推过来, 我来答, 而且**故意连点两次**。
##
## 连点是这段测试的核心。事件收益落在整局共享的 GameState 上, 结算两遍就是
## 金币加两次、天赋给两层, 没有任何报错。主机侧的 _net_event_open 是唯一的
## 一道闸, 不连点就测不到它。
func _event_client_side() -> void:
	print("  ---- 事件房: 本机答题 ----")
	var dlg = main_node.event_dialog
	if dlg == null or not is_instance_valid(dlg):
		fail("客户端没有事件框")
		return
	if not await _await_until(func(): return is_instance_valid(dlg) and dlg.visible, 30.0, "收到主机推来的事件框"):
		return

	check(str(dlg.dialog_type) != "", "事件框带着类型 (%s)" % str(dlg.dialog_type))
	if str(dlg.dialog_type) == "event":
		check(str(dlg.current_event_id) != "", "事件种类由主机指定并同步过来了 (%s)" % str(dlg.current_event_id))

	# 第一次点: 正常提交。
	dlg._pick(1)
	check(not dlg.visible, "点完之后本地立刻收起框 (不等主机)")
	# 第二次点: 必须被主机丢掉。这里直接再发一次请求, 模拟"两个人同时点"。
	await _run_frames(0.2)
	dlg._pick(1)
	ok("已连发两次事件选择, 主机应当只结算一次")


## 只返回**还活着**的货位。queue_free 过的节点在本帧剩下的时间里仍然是
## map_container 的子节点, 混进来会让"找 0 号货位"随机落到一个待删对象上。
func _client_shop_stands() -> Array:
	var out: Array = []
	if main_node == null or not is_instance_valid(main_node):
		return out
	for c in main_node.map_container.get_children():
		if c is ShopStandCls and is_instance_valid(c) and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _client_stand(slot: int):
	for c in _client_shop_stands():
		if int(c.slot_index) == slot:
			return c
	return null


func _client_stand_sold(slot: int) -> bool:
	var s = _client_stand(slot)
	return s != null and bool(s.sold)


func _read_save_file() -> Dictionary:
	var path := "user://campaign_save.json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


# ================================================================ 大厅联通性
#
# **这一趟走的是玩家真正会走的那条路。**
#
# 上面两趟为了聚焦复制层, 直接调 net.host_game() / net.join_game() —— 于是
# 大厅本身 (创建房间按钮、UDP 广播、房间列表、点进去、开始对战) 从来没被
# 测过。"联机能不能用"对玩家而言恰恰就是这一段: 复制层再正确, 房间列表出
# 不来也等于没有联机。
#
# 这里两端都真的实例化 title_screen.tscn, 调真正的按钮处理函数, 端口用真正的
# NetSession.DEFAULT_PORT。

func _lobby_of(title: Node):
	return title.get("net_lobby")


func _open_title_lobby() -> Node:
	var packed := load("res://scenes/title_screen.tscn")
	if packed == null:
		fail("title_screen.tscn 加载不出来")
		return null
	main_node = packed.instantiate()
	root.add_child(main_node)
	current_scene = main_node
	await process_frame

	var lobby = _lobby_of(main_node)
	if lobby == null:
		fail("标题界面上没有大厅 (net_lobby 为空) —— 联机入口根本没建出来")
		return null
	lobby.open_dialog()
	await process_frame
	return lobby


func _run_lobby(is_host: bool) -> void:
	print("==== %s START ====" % tag)
	var lobby = await _open_title_lobby()
	if lobby == null:
		return
	check(lobby.visible, "大厅打开了")

	if is_host:
		await _lobby_host(lobby)
	else:
		await _lobby_client(lobby)


func _lobby_host(lobby) -> void:
	# 走真正的"创建房间"按钮处理函数, 端口是玩家实际会用的 DEFAULT_PORT。
	lobby._on_host()
	await process_frame
	if NetSession.last_error != "":
		fail("开房失败: %s" % NetSession.last_error)
		return
	check(lobby.phase == lobby.Phase.HOSTING, "进入 HOSTING 阶段")
	check(NetSession.is_host(), "会话角色是主机")
	check(lobby._btn_start.disabled, "没人进来之前'开始'是灰的")

	if not await _await_until(func(): return NetSession.remote_peer_id != 0, CONNECT_TIMEOUT, "客户端通过大厅连入"):
		return
	ok("客户端已通过大厅连入")
	await process_frame
	check(not lobby._btn_start.disabled, "有人进来之后'开始'可以点了")

	# 真正的"开始街机"按钮。
	lobby._on_start_arcade()
	if not await _await_until(func(): return current_scene != null and current_scene.has_method("start_game"),
			CONNECT_TIMEOUT, "主机切进对局场景"):
		return
	ok("主机切进了 main.tscn")
	check(int(GameState.mode) == int(GameState.GameMode.ARCADE) and GameState.player_count == 2,
		"开局参数正确 (双人街机)")
	# 留一会儿, 让客户端也走完它那半段。
	await _run_frames(6.0)


func _lobby_client(lobby) -> void:
	check(lobby.phase == lobby.Phase.BROWSE, "初始在浏览房间阶段")

	# **这一条是局域网发现的实测。** 主机每秒往 255.255.255.255 广播一个心跳,
	# 客户端绑在发现端口上收。之前从来没有测试碰过这条路径 —— 它坏掉的话
	# 玩家看到的是"房间列表永远空着", 而复制层的测试全是绿的。
	if not await _await_until(func(): return _net_lobbies().size() > 0, CONNECT_TIMEOUT, "通过 UDP 广播发现主机房间"):
		print("  [dbg][%s] 局域网发现失败。同机广播被拦时属于环境限制, 手输 IP 仍然可用。" % tag)
		return
	var rooms := _net_lobbies()
	ok("发现了 %d 个局域网房间: %s" % [rooms.size(), str(rooms[0].get("name", "?"))])
	check(bool(rooms[0].get("compatible", false)), "协议版本匹配")
	check(int(rooms[0].get("port", 0)) == NetSession.DEFAULT_PORT, "广播里带着正确的游戏端口")

	# 走真正的"点房间加入"处理函数。
	lobby._on_join_lobby(rooms[0])
	if not await _await_until(func(): return lobby.phase == lobby.Phase.JOINED, CONNECT_TIMEOUT, "握手完成并进入 JOINED"):
		return
	ok("已通过房间列表加入")

	# 等主机按开始, 两端一起切场景。
	if not await _await_until(func(): return current_scene != null and current_scene.has_method("start_game"),
			CONNECT_TIMEOUT, "跟着主机切进对局场景"):
		return
	ok("客户端切进了 main.tscn")
	check(int(GameState.mode) == int(GameState.GameMode.ARCADE) and GameState.player_count == 2,
		"开局参数正确 (双人街机)")

	# 世界真的建起来了才算联机成立。
	await _run_frames(3.0)
	check(current_scene.map_container.get_children().size() > 0, "对局地图已建出")
	check(net.snapshots_recv > 0, "已经开始收到主机的快照 (%d 帧)" % net.snapshots_recv)


func _net_lobbies() -> Array:
	return net.get_lobbies() if net else []
