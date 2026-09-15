extends SceneTree

## 双人合体挂载 (scripts/train_link.gd) 的门禁。
##
##     & $godot --headless --path . --script tools/test_train_link.gd
##
## 用鸭子类型的桩节点驱动状态机, 不启动 main.tscn —— 和 tools/test_train_teleport.gd
## 同一个路数。挂载规则只依赖"两个有 global_position / is_dying 的东西"和
## rpg_mgr 报的分支, 把这些桩起来比布一整局战斗快得多, 也更容易构造边界条件。
##
## 覆盖:
##   1. 必须有一方是列车分支; 两个都不是就挂不上
##   2. 列车分支的那一方当机车 (哪怕他是 P2)
##   3. 距离太远挂不上 (否则等于一个免费的瞬移脱困)
##   4. 需要两人**同时**按住; 一个人按住不算
##   5. 挂上之后有闸门, 同一次按压不会立刻又解开
##   6. 任一方单击即解除
##   7. 阵亡 / 机车不再是列车分支 -> 自动断开
##   8. 后车挂在**整列车最后一节**之后, 而不是直接贴着机车
##   9. 联机接线: IN_LINK 进了 pack_input, F_TOWED 会关掉客户端的移动预测
##
## 按 CLAUDE.md 的约定: _failed 标志 + 末尾唯一一次 quit(), 不用 assert
## (headless 下 assert 是挂起而不是失败), 中途也不 quit(1)。

const TrainLink = preload("res://scripts/train_link.gd")
const NetSession = preload("res://scripts/net_session.gd")
const GameState = preload("res://scripts/game_state.gd")

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true


func _ok(msg: String) -> void:
	print("  ok  " + msg)


# ---------------------------------------------------------------- 桩

## 一辆最小的"坦克": 状态机只读这三样。
class TankStub extends Node2D:
	var is_dying := false
	var player_id := 1
	var history_positions: Array[Vector2] = []
	var history_rotations: Array[float] = []


## 一节车厢桩 —— 只需要 leader_node + 历史, collect_followers 就认得它。
class CarriageStub extends Node2D:
	var leader_node: Node = null
	var history_positions: Array[Vector2] = []
	var history_rotations: Array[float] = []


## 分支直接当参数传给 TrainLink —— 它不去 scene tree 里摸 rpg_mgr, 所以这里
## 也不需要伪造一整个 current_scene。
var branch1 := "default"
var branch2 := "default"

var scene_stub: Node2D
var p1: TankStub
var p2: TankStub


func _build_world() -> void:
	scene_stub = Node2D.new()
	root.add_child(scene_stub)

	p1 = TankStub.new()
	p1.player_id = 1
	p2 = TankStub.new()
	p2.player_id = 2
	scene_stub.add_child(p1)
	scene_stub.add_child(p2)
	p1.global_position = Vector2(300, 300)
	p2.global_position = Vector2(330, 300)

	# 自检 —— 世界没搭起来的话, 下面每一条"挂不上"的用例都会因为错误的理由变绿。
	# 第一版就栽在这里: 桩节点在 _init() 阶段还没真正进树, 而当时的 evaluate()
	# 要靠 p1.get_tree().current_scene 拿分支, 拿不到就当成"两边都不是列车",
	# 于是第一条用例是**空转的绿**。规则模块后来改成由调用方传分支, 这条自检
	# 留着挡下一次。
	if not is_instance_valid(p1) or not is_instance_valid(p2):
		_fail("测试世界没搭起来 —— 后面所有'挂不上'的用例都会空转变绿")


## 直接塞输入位, 绕开真实按键 —— 状态机读的是 NetSession.input_for(),
## 而离线档下它走 pack_input() 读真实按键。这里把角色设成 HOST 并把两份
## 输入都放进 remote_input, 就能逐帧精确控制两个人按了什么。
func _set_bits(b1: int, b2: int) -> void:
	NetSession.role = NetSession.Role.HOST
	NetSession.local_player_id = 0      # 让 input_for() 两个 pid 都走 remote_input
	NetSession.remote_input[1] = b1
	NetSession.remote_input[2] = b2


const LINK := 1 << 9        # NetSession.IN_LINK


func _step(b1: int, b2: int, dt: float = 0.1) -> String:
	_set_bits(b1, b2)
	return TrainLink.host_step(dt, p1, p2, branch1, branch2)


# ---------------------------------------------------------------- 用例

func _test_requires_train_branch() -> void:
	TrainLink.reset()
	branch1 = "default"
	branch2 = "heavy"
	_step(LINK, LINK)
	if TrainLink.is_linked():
		_fail("两人都不是列车分支, 却挂载成功了 —— '必须其中一个是列车型'这条规则没生效")
	else:
		_ok("两人都不是列车分支 -> 挂不上")


func _test_train_side_leads() -> void:
	# P2 是列车方 -> P2 当机车, P1 变后车
	TrainLink.reset()
	branch1 = "default"
	branch2 = "train"
	_step(LINK, LINK)
	if TrainLink.leader_id != 2 or TrainLink.follower_id != 1:
		_fail("P2 是列车分支时应当由 P2 当机车, 实际 leader=%d follower=%d —— 挂车厢是列车分支的能力, 列车方必须是机车"
			% [TrainLink.leader_id, TrainLink.follower_id])
	else:
		_ok("列车方 (P2) 当机车, P1 成为后车")

	# 两个都是列车 -> 按编号定, P1 当机车 (不能依赖按键先后, 联机两端会分歧)
	TrainLink.reset()
	branch1 = "train"
	branch2 = "train"
	_step(LINK, LINK)
	if TrainLink.leader_id != 1:
		_fail("两人都是列车分支时应当由 P1 当机车 (确定性规则), 实际 leader=%d" % TrainLink.leader_id)
	else:
		_ok("双列车 -> P1 当机车 (确定性)")


func _test_range_gate() -> void:
	TrainLink.reset()
	branch1 = "train"
	branch2 = "default"
	p2.global_position = p1.global_position + Vector2(TrainLink.LINK_RANGE + 40.0, 0)
	_step(LINK, LINK)
	if TrainLink.is_linked():
		_fail("隔着 %.0f px 也能挂载 —— 后车会被直接放到机车尾迹上, 等于一个无冷却的免费瞬移脱困技"
			% p1.global_position.distance_to(p2.global_position))
	else:
		_ok("超出 LINK_RANGE -> 挂不上")
	p2.global_position = p1.global_position + Vector2(30, 0)


func _test_needs_both() -> void:
	TrainLink.reset()
	branch1 = "train"
	branch2 = "default"
	_step(LINK, 0)
	if TrainLink.is_linked():
		_fail("只有一个人按住就挂上了 —— 合体应当需要两人共识")
	else:
		_ok("只有一方按住 -> 挂不上")


func _test_lockout_then_unlink() -> void:
	TrainLink.reset()
	branch1 = "train"
	branch2 = "default"
	_step(LINK, LINK)
	if not TrainLink.is_linked():
		_fail("两人同时按住却没挂上")
		return

	# 同一次按压继续按住: 闸门期内不许被判成解除
	var msg := _step(LINK, LINK, 0.1)
	if not TrainLink.is_linked():
		_fail("按住不放的同一次按压把刚挂上的连接又解开了 (msg=%s) —— TOGGLE_LOCKOUT 没起作用" % msg)
	else:
		_ok("闸门期内按住不放, 连接保持")

	# 松手, 等过闸门, 再由 P2 单击 -> 解除
	_step(0, 0, TrainLink.TOGGLE_LOCKOUT + 0.1)
	_step(0, LINK)
	if TrainLink.is_linked():
		_fail("任一方单击应当解除挂载, 但仍然连着")
	else:
		_ok("任一方单击 -> 解除")


## 闸门真正防的那件事 —— 解除之后两人手还按着, 下一帧不能立刻又挂上。
##
## 上面那条"按住不放不会立刻解除"其实测不出闸门: 边沿检测 (_just_pressed)
## 本身就挡住了同一次按压, 把 TOGGLE_LOCKOUT 改成 0 那条用例照样是绿的 ——
## 一条**空转的绿**, 是把闸门时长改成 0 做反向对照时才发现的。
##
## 真正需要闸门的是这里: 解除走的是"任一方按下"的边沿, 而挂载走的是"两人同时
## 按住"的电平。两人一起按下的那一帧会解除, 而**下一帧两人仍然按着**, 电平条件
## 立刻又成立 —— 没有闸门就会每隔一帧反复挂上/解除, 玩家表现为"根本解不开"。
func _test_lockout_blocks_instant_relink() -> void:
	TrainLink.reset()
	branch1 = "train"
	branch2 = "default"
	_step(LINK, LINK)                                   # 挂上
	_step(0, 0, TrainLink.TOGGLE_LOCKOUT + 0.1)         # 松手, 过闸门
	_step(LINK, LINK)                                   # 两人同时按下 -> 解除
	if TrainLink.is_linked():
		_fail("两人同时按下时应当先解除, 但仍然连着")
		return
	_step(LINK, LINK)                                   # 手还按着的下一帧
	if TrainLink.is_linked():
		_fail("解除之后两人手还按着, 下一帧立刻又挂上了 —— TOGGLE_LOCKOUT 没起作用。玩家的表现是这个连接根本解不开")
	else:
		_ok("解除后按着不放, 不会立刻重挂")


func _test_auto_break() -> void:
	# 阵亡
	TrainLink.reset()
	branch1 = "train"
	branch2 = "default"
	_step(LINK, LINK)
	p2.is_dying = true
	_step(0, 0)
	if TrainLink.is_linked():
		_fail("后车阵亡后连接没有自动断开")
	else:
		_ok("任一方阵亡 -> 自动断开")
	p2.is_dying = false

	# 机车不再是列车分支 (对局中改了分支)
	TrainLink.reset()
	branch1 = "train"
	branch2 = "default"
	_step(LINK, LINK)
	if not TrainLink.is_linked():
		_fail("挂载前置条件没满足, 后面这条用例无效")
		return
	branch1 = "heavy"
	branch2 = "default"
	_step(0, 0)
	if TrainLink.is_linked():
		_fail("机车改成非列车分支后连接没有断开 —— 挂载是靠'有一方是 train'成立的, 前提没了就该断")
	else:
		_ok("机车不再是列车分支 -> 自动断开")


## 后车必须排在机车**整列车**的最后, 而不是直接贴着机车 —— 列车分支的机车
## 本来就带 1~2 节 AI 车厢, 直接按 TOW_GAP 挂会和第一节完全重叠。
func _test_tail_of_chain() -> void:
	TrainLink.reset()
	# 给机车铺一条笔直的历史尾迹, 再挂一节车厢在它后面
	for i in range(60):
		p1.history_positions.append(Vector2(300 - i * 4.0, 300))
		p1.history_rotations.append(0.0)
	p1.history_positions.reverse()
	p1.history_rotations.reverse()

	var car := CarriageStub.new()
	car.leader_node = p1
	scene_stub.add_child(car)
	for i in range(60):
		car.history_positions.append(Vector2(300 - 38.0 - i * 4.0, 300))
		car.history_rotations.append(0.0)
	car.history_positions.reverse()
	car.history_rotations.reverse()

	var with_chain: Dictionary = TrainLink.follower_target(p1)
	car.leader_node = null      # 断开链, 让 collect_followers 认不到它
	var without: Dictionary = TrainLink.follower_target(p1)

	if with_chain.is_empty() or without.is_empty():
		_fail("follower_target() 拿不到尾迹, 用例无效")
		return
	var d: float = with_chain["position"].distance_to(without["position"])
	if d < 20.0:
		_fail("机车后面挂了一节车厢时, 后车位置只差 %.1f px —— 说明它挂在了机车正后方而不是队尾, 会和第一节车厢重叠" % d)
	else:
		_ok("后车排在整列车队尾 (与直接贴机车相差 %.1f px)" % d)
	car.queue_free()


## 联机接线。渲好规则但没接进网络层, 单机能玩、联机静默失效, 而且不会报错。
func _test_net_wiring() -> void:
	var f := FileAccess.open("res://scripts/net_session.gd", FileAccess.READ)
	if f == null:
		_fail("读不到 net_session.gd")
		return
	var src := _code_only(f.get_as_text())
	f.close()
	if not src.contains("_link\") : bits |= IN_LINK") and not src.contains("_link\"): bits |= IN_LINK"):
		_fail("pack_input() 没有把 p{1,2}_link 打进 IN_LINK —— 联机时客户端的挂载意图根本上不来, 而单机双人完全正常, 不会有任何报错")
	else:
		_ok("IN_LINK 已进 pack_input()")

	var pf := FileAccess.open("res://scripts/player.gd", FileAccess.READ)
	if pf == null:
		_fail("读不到 player.gd")
		return
	var psrc := _code_only(pf.get_as_text())
	pf.close()
	if not psrc.contains("F_TOWED"):
		_fail("player.gd 的本地预测没有读 F_TOWED —— 客户端当后车时会一边按方向键预测移动、一边被主机按尾迹拉回, 每帧一次硬纠偏, 表现为原地高频抖动")
	else:
		_ok("客户端预测已被 F_TOWED 闸住")

	var mf := FileAccess.open("res://scripts/net_manager.gd", FileAccess.READ)
	if mf == null:
		_fail("读不到 net_manager.gd")
		return
	var msrc := _code_only(mf.get_as_text())
	mf.close()
	if not msrc.contains("F_TOWED"):
		_fail("net_manager.gd 的 _flags_of() 没有下发 F_TOWED, 上面那道闸永远不会合上")
	else:
		_ok("F_TOWED 已随快照下发")


func _code_only(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var i := line.find("#")
		out += (line if i < 0 else line.substr(0, i)) + "\n"
	return out


func _run() -> void:
	print("=== 双人合体挂载 ===")
	GameState.player_count = 2
	_build_world()

	_test_requires_train_branch()
	_test_train_side_leads()
	_test_range_gate()
	_test_needs_both()
	_test_lockout_then_unlink()
	_test_lockout_blocks_instant_relink()
	_test_auto_break()
	_test_tail_of_chain()
	_test_net_wiring()

	TrainLink.reset()
	NetSession.reset()

	print("")
	if _failed:
		print("[FAIL] 双人合体挂载检查未通过")
		quit(1)
	else:
		print("[OK] 双人合体挂载检查全部通过")
		quit(0)


func _init() -> void:
	_run()
