extends SceneTree

## 联机对局的运行期冒烟测试。**不开端口** —— 直接把 NetSession.role 掰成
## HOST / CLIENT, 再真的把 main.tscn 跑起来, 验证两条代码路径都不炸、
## 而且各自做了该做的事。
##
## 为什么值得单独有这么一个测试: 联机改造对 main.gd 的侵入是几条
## `if not NetSession.is_authority(): return` 和 `if NetSession.is_authority():`。
## 这类改动的失败模式不是报错, 而是**静默地少做一件事** —— 比如客户端把
## 玩家坦克也本地生成了一辆 (场上出现两辆 1 号车), 或者主机因为条件写反了
## 一辆都不生成。两者在单机测试里都看不见, 因为单机根本不走这些分支。
##
## 按项目惯例: print("[FAIL] …") + quit(1), 不用 assert。

const NetSession = preload("res://scripts/net_session.gd")
const GameState = preload("res://scripts/game_state.gd")

var failures: int = 0
var main_node: Node = null


func fail(msg: String) -> void:
	failures += 1
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
	print(">>> NET RUNTIME SMOKE TEST <<<")
	print("==================================================")
	await _run_as(NetSession.Role.HOST)
	await _run_as(NetSession.Role.CLIENT)
	NetSession.reset()
	await _test_lobby_ui()

	# 两次运行用的是同一个 match_seed。建出来的图必须一模一样 —— 这就是
	# 联机不复制地形、只同步种子的全部依据 (见 main.gd::_net_verify_map)。
	# 它要是不成立, 真正联机时地形校验和会报警, 但那时候已经晚了。
	print("\n[种子决定地图]")
	check(_checksums.size() == 2 and _checksums[0] == _checksums[1],
		"同一个种子跑两遍得到同一张图 (%s)" % str(_checksums))
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL NET RUNTIME CHECKS PASSED! <<<")
		quit(0)


func _run_as(role: int) -> void:
	var label := "主机" if role == NetSession.Role.HOST else "客户端"
	print("\n[%s]" % label)

	NetSession.reset()
	NetSession.role = role
	NetSession.local_player_id = 1 if role == NetSession.Role.HOST else 2
	# 固定种子: 两端用同一个种子建同一张图, 这里顺便验证同一个种子跑两次
	# 得到的校验和一致 —— 那正是联机地图同步赖以成立的前提。
	NetSession.match_seed = 12345

	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2

	var packed := load("res://scenes/main.tscn")
	if packed == null:
		fail("main.tscn 加载失败")
		return
	main_node = packed.instantiate()
	root.add_child(main_node)

	# 跑几帧, 让 _ready -> start_game -> _process 都真的走一遍。
	for i in range(5):
		main_node._process(0.016)

	var map_children: int = main_node.map_container.get_children().size()
	check(map_children > 0, "%s: 地图建出来了 (%d 个瓦片)" % [label, map_children])
	check(NetSession.map_checksum != 0, "%s: 地形校验和算出来了 (%d)" % [label, NetSession.map_checksum])
	_checksums.append(NetSession.map_checksum)

	var p1_ok: bool = main_node.p1_instance != null and is_instance_valid(main_node.p1_instance)
	var p2_ok: bool = main_node.p2_instance != null and is_instance_valid(main_node.p2_instance)

	if role == NetSession.Role.HOST:
		check(p1_ok and p2_ok, "主机: 本地生成了 P1 和 P2 两辆坦克")
		var players := 0
		for c in main_node.actors_container.get_children():
			if NetSession.classify(c) == NetSession.Kind.PLAYER:
				players += 1
		check(players == 2, "主机: actors_container 里正好 2 辆玩家坦克 (实际 %d)" % players)
	else:
		# 客户端一辆都不该本地生成 —— 两辆都会以傀儡形式从主机的 spawn
		# 包过来。这里如果也建一辆, 场上就会有两辆 1 号车。
		check(not p1_ok and not p2_ok, "客户端: 一辆坦克都没有本地生成 (等主机的 spawn 包)")
		var players := 0
		for c in main_node.actors_container.get_children():
			if NetSession.classify(c) == NetSession.Kind.PLAYER:
				players += 1
		check(players == 0, "客户端: actors_container 里没有玩家坦克 (实际 %d)" % players)
		check(main_node.enemies_spawned == 0, "客户端: 没有本地刷怪 (enemies_spawned=%d)" % main_node.enemies_spawned)

	# net_collect_state 是主机每 1/6 秒调一次的东西, 字段少一个客户端 HUD
	# 就永远显示初始值 —— 静默, 所以在这里点一遍名。
	if role == NetSession.Role.HOST:
		var state: Dictionary = main_node.net_collect_state()
		for key in ["score", "p1_lives", "p2_lives", "left", "p1_hp", "p1_max", "p2_hp", "p2_max", "over", "victory", "map"]:
			check(state.has(key), "主机状态包含字段 %s" % key)

	# 客户端侧: 收到状态包之后 HUD 不该炸, 而且剩余敌人数要用主机给的值。
	if role == NetSession.Role.CLIENT:
		main_node.net_apply_state({
			"score": 4200, "p1_lives": 2, "p2_lives": 1, "left": 7,
			"p1_hp": 3, "p1_max": 5, "p2_hp": 1, "p2_max": 5,
			"over": false, "victory": false, "map": NetSession.map_checksum,
		})
		check(main_node.score == 4200, "客户端: 分数取自主机状态包")
		check(main_node._net_enemies_left == 7, "客户端: 剩余敌人数取自主机状态包")
		check(main_node.hud_enemies.text == "ENEMIES: 7", "客户端 HUD 显示的是主机给的剩余数 (实际 %s)" % main_node.hud_enemies.text)

		# 地形销毁事件: 主机说某格没了, 客户端要真的把它删掉。
		var before: int = main_node.map_container.get_children().size()
		var victim: Node2D = null
		for c in main_node.map_container.get_children():
			if c is Node2D:
				victim = c
				break
		if victim == null:
			fail("客户端: 地图里没有可测试的瓦片")
		else:
			var gx: int = main_node._grid_col(victim.position.x)
			var gy: int = main_node._grid_col(victim.position.y)
			main_node.net_remove_tile(gx, gy, String(victim.name).left(6))
			# queue_free 是延迟的, 手动放行一帧
			await process_frame
			var after: int = main_node.map_container.get_children().size()
			check(after < before, "客户端: net_remove_tile 真的删掉了那一格 (%d -> %d)" % [before, after])

	main_node.queue_free()
	await process_frame
	main_node = null


## 每一档跑完之后记下地形校验和, _run() 末尾比对。
var _checksums: Array[int] = []


## 大厅界面的冒烟测试。
##
## 整块 UI 是在代码里搭的 (net_lobby.gd), 没有 .tscn 可以被编辑器校验 ——
## 一个写错的节点路径或者用错的容器只有在玩家点开它的那一刻才会炸,
## 而那正好是"我想联机"这个动作的第一步。
##
## 只断言不依赖网络环境的部分: 打开/关闭、按钮可见性随阶段变化。
## start_listening() 会真的去 bind 一个 UDP 端口, 端口被占时它自己降级成
## 一条错误提示而不是抛异常, 所以这里不对它的成败下断言。
func _test_lobby_ui() -> void:
	print("\n[大厅界面]")
	var packed := load("res://scenes/title_screen.tscn")
	if packed == null:
		fail("title_screen.tscn 加载失败")
		return
	var title: Node = packed.instantiate()
	root.add_child(title)
	await process_frame

	var lobby = title.get("net_lobby")
	if lobby == null:
		fail("标题界面上没有建出大厅 (net_lobby 为空)")
		title.queue_free()
		await process_frame
		return
	ok("大厅面板已随标题界面建出")
	check(title.get("btn_lan_coop") != null, "联机入口按钮已建出")
	check(not lobby.visible, "默认不显示")

	lobby.open_dialog()
	await process_frame
	check(lobby.visible, "open_dialog 之后显示出来")
	check(lobby.phase == lobby.Phase.BROWSE, "初始阶段是 BROWSE (在找房间)")
	check(title._is_dialog_open(), "标题界面知道有对话框开着 (暗号输入/入场动画要靠它让路)")

	lobby._on_close()
	await process_frame
	check(not lobby.visible, "关闭之后隐藏")
	check(not NetSession.is_active(), "关闭时顺带断开了会话 (否则 socket 会一直挂着)")

	title.queue_free()
	await process_frame
