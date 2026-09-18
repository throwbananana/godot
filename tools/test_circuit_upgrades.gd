extends SceneTree

## 电路系统三项低成本扩展的回归测试:
##   1. 双色 AND 受控物 (瓦片 61/62/63) —— 红蓝都接通才生效。
##   2. 第三条独立电路 (绿, 瓦片 56-60) —— 跟红/蓝互不影响。
##   3. 保持型压力板 + 它控制的可逆闸门 (瓦片 64-69) —— 踩着才通电,
##      离开就断电, 可以反复开合, 联机走独立的 broadcast_hold_gate 通道。
##
## 按项目惯例: 不用 assert (随机前提下的 assert 是潜在的 TIMEOUT 而不是 FAIL,
## 这里虽然不随机, 但同一个坑 CLAUDE.md 已经踩过两次), 用 print("[FAIL] …")
## 记全局标志, 只在最后 quit 一次 —— quit() 不中断调用栈, 中途 quit(1) 会被
## 末尾的 quit(0) 覆盖回 0。

const NetSession = preload("res://scripts/net_session.gd")
const GameState = preload("res://scripts/game_state.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")

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


## 一张放全部三个新机制的 13x13 图。避开老鹰/砖圈 (11-12 行) 和三个敌人
## 出生点 (0 行的 0/6/12 列), 免得 _spawn_base_and_walls() 或出生点开路
## 逻辑把这些格子覆盖掉。
func _make_layout() -> Array:
	var g: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		g.append(row)
	g[2][2] = 46   # 压力板 红
	g[2][4] = 47   # 压力板 蓝
	g[2][6] = 56   # 压力板 绿
	g[4][2] = 61   # AND 受控电墙 (红+蓝)
	g[4][4] = 58   # 受控电墙 绿
	g[6][2] = 64   # 保持压力板 红 (A)
	g[6][6] = 64   # 保持压力板 红 (B) —— 同色第二块, 用来测 OR 语义
	g[8][2] = 67   # 电路闸门 红
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


func _find_by_group(m: Node, group: String) -> Array:
	var out: Array = []
	for ch in m.actors_container.get_children():
		if ch.is_in_group(group):
			out.append(ch)
	for ch in m.map_container.get_children():
		if ch.is_in_group(group):
			out.append(ch)
	return out


func _run() -> void:
	print("==================================================")
	print(">>> CIRCUIT SYSTEM UPGRADES TEST <<<")
	print("==================================================")

	_test_validate_bound()
	await _test_and_gate()
	await _test_green_channel_independent()
	await _test_hold_gate_or_and_reverse()
	await _test_hold_gate_authority_and_net()

	NetSession.reset()
	print("==================================================")
	if _failed:
		print("[FAIL] 电路系统扩展测试未通过")
		quit(1)
	else:
		print(">>> ALL CIRCUIT UPGRADE CHECKS PASSED! <<<")
		quit(0)


## validate_layout 的上界要跟着新地块挪, 不然编辑器能画出来的图自己校验不过。
func _test_validate_bound() -> void:
	print("\n[0] validate_layout() 上界跟着新地块挪到 69")
	var g: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		g.append(row)
	g[2][2] = 69
	check(MapTemplates.validate_layout(g).is_empty(), "69 号地块 (闸门绿) 通过校验")
	g[2][2] = 70
	var errs := MapTemplates.validate_layout(g)
	check(not errs.is_empty(), "70 号地块越界被拦下 (%s)" % str(errs))


## 红蓝都要接通, AND 受控电墙才会断电——单独一色不生效, 只记进度。
func _test_and_gate() -> void:
	print("\n[1] 双色 AND 受控电墙 (瓦片 61)")
	var m := _boot(NetSession.Role.OFFLINE)
	if m == null:
		return

	check(m.circuit_and_pending.size() == 1, "AND 受控物确实登记了一份待触发记录 (实际 %d)" % m.circuit_and_pending.size())
	var building: Node = null
	for b in m.circuit_and_pending:
		building = b
	if building == null:
		fail("找不到 AND 受控电墙实例, 后续断言跳过")
		m.free()
		return
	check(building.get("is_powered") == true, "触发前 AND 电墙仍带电")

	m._on_circuit_switch_pressed("red")
	check(bool(m.circuit_solved.get("red", false)), "红色电路标记为已接通")
	check(m.circuit_and_pending.has(building), "只接通红色时 AND 电墙仍在待触发列表里 (还差蓝色)")
	check(building.get("is_powered") == true, "只接通红色时 AND 电墙仍带电 (蓝色还没到)")

	m._on_circuit_switch_pressed("blue")
	check(bool(m.circuit_solved.get("blue", false)), "蓝色电路标记为已接通")
	check(not m.circuit_and_pending.has(building), "红蓝都接通后 AND 电墙从待触发列表移除")
	check(building.get("is_powered") == false, "红蓝都接通后 AND 电墙断电")
	m.free()


## 绿色是第三条独立通道, 触发它不能影响红/蓝的状态, 反之亦然。
func _test_green_channel_independent() -> void:
	print("\n[2] 绿色电路独立于红/蓝 (瓦片 56/58)")
	var m := _boot(NetSession.Role.OFFLINE)
	if m == null:
		return

	var green_buildings: Array = m.circuit_gated_buildings.get("green", [])
	check(green_buildings.size() == 1, "受控电墙(绿)确实登记进了 green 通道 (实际 %d)" % green_buildings.size())

	m._on_circuit_switch_pressed("green")
	check(bool(m.circuit_solved.get("green", false)), "绿色电路标记为已接通")
	check(not bool(m.circuit_solved.get("red", false)), "触发绿色不影响红色 (仍未接通)")
	check(not bool(m.circuit_solved.get("blue", false)), "触发绿色不影响蓝色 (仍未接通)")
	if not green_buildings.is_empty():
		check(green_buildings[0].get("is_powered") == false, "受控电墙(绿)在绿色接通后断电")
	m.free()


## 保持型压力板: 同色两块任意一块被占用就该开门 (OR), 全部离开就该关门,
## 而且这个过程要能反复翻转 (跟一次性锁存的电路完全不同)。
func _test_hold_gate_or_and_reverse() -> void:
	print("\n[3] 保持型压力板 OR 语义 + 可逆开合 (瓦片 64/67)")
	var m := _boot(NetSession.Role.OFFLINE)
	if m == null:
		return

	var switches := _find_by_group(m, "hold_switch")
	var doors := _find_by_group(m, "circuit_gate_door")
	check(switches.size() == 2, "两块红色保持压力板都生成了 (实际 %d)" % switches.size())
	check(doors.size() == 1, "红色闸门生成了 (实际 %d)" % doors.size())
	if switches.size() != 2 or doors.is_empty():
		fail("布局没按预期生成, 后续断言跳过")
		m.free()
		return

	var sw_a: Node = switches[0]
	var sw_b: Node = switches[1]
	var door: Node = doors[0]
	check(door.is_open == false, "初始状态闸门是关着的")

	var body_a := CharacterBody2D.new()
	var body_b := CharacterBody2D.new()

	sw_a._on_body_entered(body_a)
	check(sw_a.is_held == true, "压力板 A 被踩下后 is_held=true")
	check(door.is_open == true, "踩下压力板 A 后闸门打开")

	sw_b._on_body_entered(body_b)
	check(door.is_open == true, "压力板 B 也被踩下, 闸门仍然打开")

	sw_a._on_body_exited(body_a)
	check(sw_a.is_held == false, "压力板 A 离开后 is_held=false")
	check(door.is_open == true, "A 离开但 B 还站着, 闸门仍应保持打开 (OR 语义)")

	sw_b._on_body_exited(body_b)
	check(door.is_open == false, "A/B 都离开后闸门重新关闭——跟一次性锁存的电路不同, 这里可以反复翻转")

	# 再开一次, 证明真的是"可逆"而不是"一次性烧掉"。
	sw_a._on_body_entered(body_a)
	check(door.is_open == true, "重新踩下后闸门能再次打开 (验证可逆, 不是一次性)")

	body_a.free()
	body_b.free()
	m.free()


## 联机权限: 客户端不能自己决定闸门开合 (预测坦克会压中自己本地那块压力板),
## 必须等主机通过 net_apply_hold_gate() 下发——跟 test_circuit_netsync.gd
## 对一次性电路做的是同一件事, 只是这里的状态可以反复覆盖。
func _test_hold_gate_authority_and_net() -> void:
	print("\n[4] 客户端不能自己开合闸门, 只认主机下发")
	var m := _boot(NetSession.Role.CLIENT)
	if m == null:
		return

	var switches := _find_by_group(m, "hold_switch")
	var doors := _find_by_group(m, "circuit_gate_door")
	if switches.is_empty() or doors.is_empty():
		fail("客户端本地没建出压力板/闸门, 后续断言跳过")
		m.free()
		return
	var door: Node = doors[0]

	var body := CharacterBody2D.new()
	switches[0]._on_body_entered(body)
	check(door.is_open == false, "客户端本地踩压力板不会让闸门自己打开")

	if not m.has_method("net_apply_hold_gate"):
		fail("客户端缺少 net_apply_hold_gate() —— 主机的闸门事件无处可落")
	else:
		m.net_apply_hold_gate("red", true)
		check(door.is_open == true, "net_apply_hold_gate(true) 之后客户端闸门打开")
		m.net_apply_hold_gate("red", false)
		check(door.is_open == false, "net_apply_hold_gate(false) 之后客户端闸门重新关闭")

	body.free()
	m.free()
