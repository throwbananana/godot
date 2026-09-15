extends SceneTree

## 电路谜题 (瓦片 46-55) 与"地图家具"在联机下的同步回归测试。
##
## 为什么需要它: 电路系统 (05c376b) 比联机 (012fa0c) 早进来, 而联机的三层
## 测试一次都没覆盖到它 —— 电路房是 MapDirector 按 validate() 随机放的谜题房,
## run_net_e2e.ps1 那三趟根本没抽到过。实测出来的两个缺陷:
##
##   1. **地图家具被复制了两遍。** _build_map() 全程没有任何 authority 判定,
##      两端都把瓦片铺一遍; 而压力板/炸开关/充能站/油桶/宝箱这些进的是
##      actors_container, net_manager::_send_snapshot() 每帧扫这个容器并把
##      非 IGNORED 的一律登记下发。于是客户端手里是**双份**: 自己建的那份
##      (活的) 加主机推来的傀儡 (monitoring=false 的惰性壳)。实测客户端
##      本地建出 5 个 kind=SCENE_NODE 的实体。
##      两份完全重叠, 肉眼看不出来, 直到你朝它开一枪。
##
##   2. **"电路接通"这个状态变化根本没有上行/下行通道。**
##      _on_circuit_switch_pressed() 没有 authority 判定也没有 RPC, 而
##      electric_wall/shield_station 的 set_circuit_solved() 改的是
##      is_powered / collision_shape.disabled / modulate —— **改状态而不是删节点**,
##      所以连 map_container.child_exiting_tree 那条地形兜底都吃不到
##      (能量墙自毁恰好能蹭上, 其余三类不行)。
##      后果双向且都不报错: 客户端的预测坦克有真碰撞, 会压中自己本地那块
##      压力板, 于是只有它那边断电; 反过来主机打爆炸开关, 客户端的
##      switch_pressed 永远不触发, 它看到的是一堵仍然带电的墙。
##
## 修复采用的规则跟地形一致 —— **地图家具按种子同步, 不进复制层; 只复制它的
## 状态变化**。这正是 CLAUDE.md "地图靠种子同步而不是复制瓦片" 那条的推广。
##
## 按项目惯例: 不用 assert (随机前提下的 assert 是潜在的 TIMEOUT 而不是 FAIL),
## 用 print("[FAIL] …") 记全局标志, **只在最后 quit 一次** —— quit() 不中断
## 调用栈, 中途 quit(1) 会被末尾的 quit(0) 覆盖回 0。

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


## 一张只放电路件的 13x13 图。刻意避开老鹰/砖圈 (11-12 行) 和三个敌人
## 出生点 (0 行的 0/6/12 列), 免得 _spawn_base_and_walls() 或出生点开路
## 逻辑把这些格子覆盖掉 —— 那样测试会因为"东西根本没生成"而假绿。
func _make_layout() -> Array:
	var g: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		g.append(row)
	g[2][2] = 46   # 压力板 红
	g[2][4] = 52   # 炸开关 红
	g[4][2] = 48   # 受控电墙 红
	g[4][4] = 50   # 受控充能站 红
	g[6][2] = 54   # 能量墙 红
	g[6][4] = 26   # 油桶 —— 普通地图家具的对照组, 证明这不是电路专属问题
	return g


func _boot(role: int) -> Node:
	NetSession.reset()
	NetSession.role = role
	NetSession.local_player_id = 1 if role == NetSession.Role.HOST else 2
	NetSession.match_seed = 12345
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	GameState.playtest_layout = _make_layout()

	var packed := load("res://scenes/main.tscn")
	if packed == null:
		fail("main.tscn 加载失败")
		return null
	var m: Node = packed.instantiate()
	root.add_child(m)
	for i in range(5):
		m._process(0.016)
	return m


## actors_container 里"会被复制"的家具数量。玩家坦克不算 —— 它本来就该复制。
func _replicable_furniture(m: Node) -> Array:
	var out: Array = []
	for ch in m.actors_container.get_children():
		if ch.is_in_group("player") or ch.is_in_group("p1") or ch.is_in_group("p2"):
			continue
		if NetSession.classify(ch) == NetSession.Kind.IGNORED:
			continue
		var scr = ch.get_script()
		out.append(scr.resource_path.get_file() if scr else ch.get_class())
	return out


func _gated_count(m: Node) -> int:
	var n := 0
	for c in m.circuit_gated_buildings:
		n += m.circuit_gated_buildings[c].size()
	return n


func _run() -> void:
	print("==================================================")
	print(">>> CIRCUIT / MAP-FURNITURE NET SYNC TEST <<<")
	print("==================================================")

	await _test_furniture_not_replicated()
	await _test_client_cannot_solve_locally()
	await _test_client_applies_host_circuit()
	await _test_host_solves_and_broadcasts()
	await _test_furniture_is_deterministic()

	NetSession.reset()
	print("==================================================")
	if _failed:
		print("[FAIL] 电路/家具联机同步测试未通过")
		quit(1)
	else:
		print(">>> ALL CIRCUIT NETSYNC CHECKS PASSED! <<<")
		quit(0)


## 缺陷 1。两端都会本地建出这些家具 (地图是按种子确定性生成的), 所以它们
## **一个都不能进复制层** —— 否则客户端就是本地一份 + 傀儡一份。
func _test_furniture_not_replicated() -> void:
	print("\n[1] 地图家具不进复制层 (否则客户端拿到双份)")
	for role in [NetSession.Role.HOST, NetSession.Role.CLIENT]:
		var label := "主机" if role == NetSession.Role.HOST else "客户端"
		var m := _boot(role)
		if m == null:
			return
		var built: int = m.actors_container.get_children().size()
		check(built >= 5, "%s: 家具确实生成了 (actors_container %d 个子节点)" % [label, built])

		var repl := _replicable_furniture(m)
		check(repl.is_empty(),
			"%s: 没有任何家具会被复制 (实际 %d 个: %s)" % [label, repl.size(), str(repl)])

		# 客户端也必须真的把受控建筑登记进 circuit_gated_buildings ——
		# 它要靠这张表响应主机推来的"电路接通"事件。
		check(_gated_count(m) == 3,
			"%s: 三个受控建筑都登记了 (实际 %d)" % [label, _gated_count(m)])
		m.free()


## 缺陷 2 的上半: 客户端不许自己结算电路。
## 它的预测坦克有真碰撞, 会压中自己本地那块压力板 —— 没有 authority 判定的话
## 只有它这边断电, 主机毫不知情。
func _test_client_cannot_solve_locally() -> void:
	print("\n[2] 客户端不能自己解开电路")
	var m := _boot(NetSession.Role.CLIENT)
	if m == null:
		return
	m._on_circuit_switch_pressed("red")
	check(not bool(m.circuit_solved.get("red", false)),
		"客户端本地触发开关后电路仍未接通 (实际 circuit_solved=%s)" % str(m.circuit_solved))

	var still_live := 0
	for b in m.circuit_gated_buildings.get("red", []):
		if is_instance_valid(b) and b.get("is_powered") == true:
			still_live += 1
	check(still_live > 0, "受控电墙在客户端仍然带电 (未被本地断电), 带电数 %d" % still_live)
	m.free()


## 缺陷 2 的下半: 主机说接通了, 客户端必须照做 —— 而且是作用在**它自己本地
## 建的**那批受控建筑上。
func _test_client_applies_host_circuit() -> void:
	print("\n[3] 客户端响应主机下发的电路事件")
	var m := _boot(NetSession.Role.CLIENT)
	if m == null:
		return
	if not m.has_method("net_apply_circuit"):
		fail("客户端缺少 net_apply_circuit() —— 主机的电路事件无处可落")
		m.free()
		return
	m.net_apply_circuit("red")
	check(bool(m.circuit_solved.get("red", false)), "net_apply_circuit 之后电路标记为已接通")

	var powered := 0
	for b in m.circuit_gated_buildings.get("red", []):
		if is_instance_valid(b) and b.get("is_powered") == true:
			powered += 1
	# 受控电墙断电 (is_powered=false), 受控充能站上电 (is_powered=true) ——
	# 两者方向相反, 所以这里只断言"电墙那一边确实变了"。
	check(powered <= 1, "受控电墙已在客户端断电 (仍带电的建筑数 %d, 允许充能站那 1 个)" % powered)
	m.free()


## 主机侧: 照旧本地结算 (单机路径一行不改), 并且要把事件广播出去。
func _test_host_solves_and_broadcasts() -> void:
	print("\n[4] 主机照旧本地结算, 并具备广播通道")
	var m := _boot(NetSession.Role.HOST)
	if m == null:
		return
	m._on_circuit_switch_pressed("red")
	check(bool(m.circuit_solved.get("red", false)), "主机本地结算电路 (单机行为不变)")

	var net_script = load("res://scripts/net_manager.gd")
	var has_broadcast: bool = false
	if net_script:
		for meth in net_script.get_script_method_list():
			if String(meth.get("name", "")) == "broadcast_circuit":
				has_broadcast = true
				break
	check(has_broadcast, "net_manager.gd 提供 broadcast_circuit() 下发通道")

	# 重复触发必须是无操作 (同色可能有多个开关, OR 逻辑)。
	var before: Dictionary = m.circuit_solved.duplicate()
	m._on_circuit_switch_pressed("red")
	check(before == m.circuit_solved, "同色重复触发是无操作 (OR 逻辑不重放)")
	m.free()


## "不复制家具" 这条规则**完全建立在一个前提上: 两端会各自建出一模一样的
## 家具**。前提不成立的话, 后果比原来的双份更糟 —— 客户端会看到一个主机
## 那边不存在的油桶, 而且没有任何东西会来纠正它。
##
## 这不是空担心。宝箱 (_setup_challenge_treasure) 是这批家具里唯一用了
## randf() 和 get_random_empty_tile_position() 的, 也就是说它依赖两端的 RNG
## 流在那一刻处于同一位置 —— 而 CLAUDE.md 里已经记过一次 RNG 流被屏幕抖动
## 的 randf_range() 岔开的事故。所以这里逐格比对, 不是只数个数。
func _test_furniture_is_deterministic() -> void:
	print("\n[5] 两端建出的家具逐格一致 (不复制家具的前提)")
	var host_set := _furniture_fingerprint(NetSession.Role.HOST)
	var client_set := _furniture_fingerprint(NetSession.Role.CLIENT)
	check(not host_set.is_empty(), "指纹非空 (否则这条断言是空转的)")
	check(host_set == client_set,
		"主机与客户端的家具集合一致\n      主机  : %s\n      客户端: %s" % [str(host_set), str(client_set)])


## 家具的 (名字前缀, 格号) 集合, 排序后当指纹。用格号而不是浮点坐标, 跟
## net_remove_tile 的定位口径保持一致。
func _furniture_fingerprint(role: int) -> Array:
	var m := _boot(role)
	if m == null:
		return []
	var out: Array = []
	for ch in m.actors_container.get_children():
		if not ch.has_meta(NetSession.FURNITURE_META):
			continue
		var p: Vector2 = (ch as Node2D).position
		out.append("%s@%d,%d" % [String(ch.name).left(6), int(floor(p.x / 48.0)), int(floor(p.y / 48.0))])
	out.sort()
	m.free()
	return out
