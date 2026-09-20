extends SceneTree

## 自爆车 (SUICIDE) 的寻路回归测试。
##
## 同一段代码里的自爆无人机 (DRONE_MINI) 刻意不在覆盖范围内: 它走自由矢量,
## 而且"撞到任何东西都引爆"是它写死的定位, 所以它根本没有"卡住"这个状态。
##
## 起因: 自爆车的"拦截 AI"只做了贪心朝向 —— 每帧取 |dx|>|dy| 的那条主轴,
## 转成四方向之一直冲过去, 整条链路上没有任何避障判定; 而 _physics_process
## 末尾的碰撞分支里, 自爆车撞到*非目标*(砖墙/钢墙/边界/同伴)时既不引爆也不
## 换向 —— 那个 if 里只有"撞到玩家/鹰巢/建筑就引爆"一条, 撞墙时整个分支是空的。
## 两件事叠起来的后果是确定性的死循环: 主轴被墙挡住 → 贴着墙不动 → 下一帧
## 重新算出同一条主轴 → 继续贴着墙。玩家与自爆车之间只要隔着一堵墙, 它就会
## 在墙前停住直到被打死, 全程没有任何报错。
##
## 按 CLAUDE.md "Commands" 一节: 用 _failed 标志 + 末尾唯一一次 quit(),
## 不用 assert (headless 下 assert 是挂起而不是失败), 也不散落 quit(1)
## (同进程后面的 quit(0) 会把退出码覆盖回 0)。
var _failed := false

const EnemyScript = preload("res://scripts/enemy.gd")

func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING SUICIDE TANK PATHFINDING TESTS <<<")
	print("==================================================")

	await _test_detours_around_wall_gap_above()
	await _test_detours_when_upper_side_is_sealed()
	await _test_no_detour_on_open_ground()
	await _test_target_is_not_an_obstacle()
	await _test_wall_contact_does_not_waste_the_truck()
	await _test_friendly_structure_is_an_obstacle_not_a_target()

	if _failed:
		print("\n>>> SUICIDE PATHFINDING CHECKS FAILED <<<")
		quit(1)
	else:
		print("\n>>> ALL SUICIDE PATHFINDING CHECKS PASSED! <<<")
		quit(0)

## 造一面 48px 格砖墙。cells 是 (x, y) 中心坐标列表。
func _build_wall(parent: Node, cells: Array) -> Array:
	var made: Array = []
	for c in cells:
		var b := StaticBody2D.new()
		b.add_to_group("brick")
		var col := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(48, 48)
		col.shape = box
		b.add_child(col)
		parent.add_child(b)
		b.global_position = c
		made.append(b)
	return made

func _make_target(parent: Node, pos: Vector2) -> Node2D:
	var t := Node2D.new()
	t.add_to_group("player")
	parent.add_child(t)
	t.global_position = pos
	return t

func _make_truck(parent: Node, pos: Vector2, type: int) -> Node2D:
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.enemy_type = type
	parent.add_child(enemy)
	enemy._setup_tank_type()
	enemy.global_position = pos
	return enemy

## 跑到引爆或超时为止, 返回
## [是否够到目标, 全程最近距离, 用掉的帧数, 是否从墙体下方绕行]。
## 最后一项让调用方能区分"绕过去了"和"从预期的那一侧绕过去了"。
func _run_until_reached(truck: Node2D, target: Node2D, max_frames: int) -> Array:
	var best := INF
	var frames := 0
	var went_low := false
	while frames < max_frames:
		if not is_instance_valid(truck):
			# 引爆即自毁。这里必须交出"活着时量到的最近距离"而不是 0 —— 第一版
			# 图省事直接返回 0.0, 于是"炸在半路上"和"炸在目标脸上"在调用方看来
			# 一模一样, 上面那条 res[1] > 60 的检查完全落空: 实测把自家护盾塔的
			# 豁免拆掉 (车直接撞爆在塔上) 那一步照样报 PASS。
			return [true, best, frames, went_low]
		went_low = went_low or truck.global_position.y > 340.0
		var d: float = truck.global_position.distance_to(target.global_position)
		best = minf(best, d)
		if truck.is_suicide_detonated:
			return [true, best, frames, went_low]
		await process_frame
		frames += 1
	return [false, best, frames, went_low]

## queue_free() 只是挂上删除标记, 物理服务器要到它真正处理那一帧才会把碰撞体
## 从 broadphase 里摘掉 —— 按固定帧数等是不够的 (CLAUDE.md 里 test_kinetic_push
## 那条同样的坑)。这里必须轮询到真没了为止: 下一个 STEP 会在几乎同样的坐标上
## 重新搭一套布局, 上一步残留的砖墙正好压在新布局的行进路线上, 表现出来就是
## "空地上的自爆车莫名其妙拐弯"。
## 等到车真的动起来为止, 再去看它的朝向。
##
## facing_direction 的初值是 DOWN, 要等第一个物理帧跑完拦截 AI 才会被改写 ——
## 直接在 add_child 之后就读朝向, 读到的是"还没开始想"的默认值, 而不是它决定
## 要走的方向。这条曾经让本文件的"空地直冲"检查在第 0 帧误报 DOWN: 前几次能过
## 纯粹是因为上一步的清理恰好多耗了几帧, 换成轮询式清理之后时序一变就露馅了。
func _await_first_move(truck: Node2D, from: Vector2) -> bool:
	var waited := 0
	while waited < 120:
		if not is_instance_valid(truck):
			return false
		if truck.global_position.distance_to(from) > 1.0:
			return true
		await process_frame
		waited += 1
	return false

func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	var waited := 0
	while waited < 60:
		var alive := false
		for n in nodes:
			if is_instance_valid(n):
				alive = true
				break
		if not alive:
			break
		await process_frame
		waited += 1
	await process_frame # 再给一帧: is_instance_valid()==false 不等于 broadphase 已经更新

## 目标在正右方, 中间一堵竖墙, 缺口在上方。
func _test_detours_around_wall_gap_above() -> void:
	print("\n[STEP 1] 竖墙挡住主轴、缺口在上方时自爆车必须绕过去...")

	var world := Node2D.new()
	root.add_child(world)

	var walls := _build_wall(world, [
		Vector2(250, 156), Vector2(250, 204), Vector2(250, 252),
		Vector2(250, 300), Vector2(250, 348), Vector2(250, 396),
		Vector2(250, 444),
	])
	var target := _make_target(world, Vector2(430, 300))
	var truck := _make_truck(world, Vector2(100, 300), EnemyScript.EnemyType.SUICIDE)

	await process_frame
	await process_frame

	var res = await _run_until_reached(truck, target, 1200)
	if not res[0]:
		_fail("自爆车被墙卡住了: %d 帧内始终没够到目标, 全程最近 %.1f px (贪心主轴撞墙后既不换向也不绕行)" % [res[2], res[1]])
	elif res[1] > 60.0:
		# "引爆了"本身不等于"打中了" —— 半路炸在别的东西上也会让 res[0] 为真。
		_fail("自爆车在离目标 %.1f px 的地方就炸了, 并没有真的够到目标" % res[1])
	else:
		print("  [PASS] %d 帧内绕过墙体并引爆。" % res[2])

	await _cleanup(walls + [target, truck, world])

## 同样一堵墙, 但拿一道横盖把上方那条路真的封死, 逼它掉头从下方绕。
##
## 这一步专门验证"绕行方向长期锁存"不会变成一头扎进死路: 车先选了 UP, 一路
## 撞到横盖才发现走不通, 这时候必须放弃 UP 重新选, 而不是顶着横盖磨到死。
## 注意墙一定要真的封顶 —— 第一版这里只是把竖墙往上接长, 车绕过墙顶照样能
## 到目标, 于是这一步名义上测"改走下方", 实际测的还是第 1 步的上方绕行。
func _test_detours_when_upper_side_is_sealed() -> void:
	print("\n[STEP 2] 上方封死时自爆车必须掉头从下方绕...")

	var world := Node2D.new()
	root.add_child(world)

	var cells := []
	for i in range(5):
		cells.append(Vector2(250, 300 - i * 48)) # 竖墙: y=300 向上到 y=108
	for i in range(4):
		cells.append(Vector2(202 - i * 48, 108))  # 横盖: 从竖墙顶端向左延伸
	var walls := _build_wall(world, cells)
	var target := _make_target(world, Vector2(430, 300))
	var truck := _make_truck(world, Vector2(100, 300), EnemyScript.EnemyType.SUICIDE)

	await process_frame
	await process_frame

	var res = await _run_until_reached(truck, target, 1200)
	if not res[0]:
		_fail("上方是死路时自爆车没能掉头走下方: %d 帧内最近 %.1f px" % [res[2], res[1]])
	elif res[1] > 60.0:
		_fail("自爆车在离目标 %.1f px 的地方就炸了, 并没有真的够到目标" % res[1])
	elif not res[3]:
		_fail("自爆车是从上方过去的, 但上方已被横盖封死 —— 测试布局没起作用")
	else:
		print("  [PASS] %d 帧内掉头从下方绕过并引爆。" % res[2])

	await _cleanup(walls + [target, truck, world])

## 空地上不能因为避障判定而无端拐弯 —— 自爆车的威胁性就建立在"直线冲脸"上。
func _test_no_detour_on_open_ground() -> void:
	print("\n[STEP 3] 空地上必须保持直冲, 不做多余绕行...")

	var world := Node2D.new()
	root.add_child(world)
	var target := _make_target(world, Vector2(430, 300))
	var truck := _make_truck(world, Vector2(100, 300), EnemyScript.EnemyType.SUICIDE)

	await process_frame
	await process_frame

	if not await _await_first_move(truck, Vector2(100, 300)):
		_fail("空地上自爆车 120 帧内没有起步")
		await _cleanup([target, truck, world])
		return

	var straight := true
	var frames := 0
	var turn_at := Vector2.ZERO
	while frames < 300 and is_instance_valid(truck) and not truck.is_suicide_detonated:
		if truck.facing_direction != Vector2.RIGHT:
			straight = false
			turn_at = truck.global_position
			break
		await process_frame
		frames += 1

	if not straight:
		_fail("空地上自爆车不应拐弯: 第 %d 帧在 %s 处转向了 %s" % [frames, str(turn_at.round()), str(truck.facing_direction)])
	elif frames >= 300:
		_fail("空地上 300 帧 (330px 直线距离) 还没引爆, 拦截 AI 没在推进")
	else:
		print("  [PASS] 全程保持 RIGHT 直冲, %d 帧后引爆。" % frames)

	await _cleanup([target, truck, world])

## 避障探测必须把"目标本身"当成可通行 —— 玩家/鹰巢/建筑正是它要撞的东西。
## 把玩家当障碍的话, 自爆车会在贴脸前最后一瞬间拐开, 表现为"怎么都撞不上"。
func _test_target_is_not_an_obstacle() -> void:
	print("\n[STEP 4] 贴脸距离上目标不能被当成障碍物...")

	var world := Node2D.new()
	root.add_child(world)

	# 用真玩家场景: 它带碰撞体, 探测射线会真的打到它。
	var player = load("res://scenes/player.tscn").instantiate()
	world.add_child(player)
	player.global_position = Vector2(400, 300)
	# 起步距离 120px: 车身半宽 19 + 探测 18 + 玩家半宽 20 = 57px 起探测就会打到
	# 玩家, 而引爆在 42px —— 这段 15px 的窗口就是"目标算不算障碍"唯一能被观察到
	# 的地方, 起手就贴到 52px 的话只跑几帧就炸了, 根本进不了探测范围。
	var truck := _make_truck(world, Vector2(280, 300), EnemyScript.EnemyType.SUICIDE)

	await process_frame
	await process_frame

	if not await _await_first_move(truck, Vector2(280, 300)):
		_fail("自爆车 120 帧内没有起步")
		await _cleanup([player, truck, world])
		return

	var turned_away := false
	var frames := 0
	while frames < 180 and is_instance_valid(truck) and not truck.is_suicide_detonated:
		if truck.facing_direction != Vector2.RIGHT:
			turned_away = true
			break
		await process_frame
		frames += 1

	if turned_away:
		_fail("自爆车在贴脸距离上拐开了 (朝向 %s) —— 避障探测把玩家当成了障碍" % str(truck.facing_direction))
	elif frames >= 180:
		_fail("正对玩家 120px 的情况下 180 帧内没有引爆")
	else:
		print("  [PASS] 直接撞上玩家并引爆 (%d 帧)。" % frames)

	await _cleanup([player, truck, world])

## 撞墙不能引爆 —— 自爆车是冲着玩家去的一次性威胁, 炸在砖墙上等于白送。
## (这条在修复前就是对的, 留作回归: 新加的绕行逻辑不能顺手把它改坏。)
func _test_wall_contact_does_not_waste_the_truck() -> void:
	print("\n[STEP 5] 贴到砖墙上不能自爆...")

	var world := Node2D.new()
	root.add_child(world)
	var walls := _build_wall(world, [Vector2(250, 300)])
	var target := _make_target(world, Vector2(430, 300))
	var truck := _make_truck(world, Vector2(180, 300), EnemyScript.EnemyType.SUICIDE)

	await process_frame
	await process_frame

	var detonated_on_wall := false
	for i in range(40):
		if not is_instance_valid(truck):
			detonated_on_wall = true
			break
		if truck.is_suicide_detonated and truck.global_position.distance_to(target.global_position) > 84.0:
			detonated_on_wall = true
			break
		await process_frame

	if detonated_on_wall:
		_fail("自爆车在砖墙上自爆了 —— 它只应该对玩家/鹰巢/建筑引爆")
	else:
		print("  [PASS] 砖墙接触不触发引爆。")

	await _cleanup(walls + [target, truck, world])

## 敌方护盾塔同时在 buildings 和 enemy_building 两个组里。buildings 是伞形组,
## 一路上把"玩家建的炮塔"和"给敌人加盾的塔"混在一起 —— 照着 buildings 判定的话,
## 自爆车会一头撞死在给自己队友加盾的塔上: 塔毫发无伤 (引爆的 AoE 只打玩家/
## 鹰巢/砖块), 车白送一辆。它应该绕开。
func _test_friendly_structure_is_an_obstacle_not_a_target() -> void:
	print("\n[STEP 6] 自家阵营的护盾塔应该被绕开而不是撞爆...")

	var world := Node2D.new()
	root.add_child(world)

	var tower = load("res://scenes/buildings/enemy_shield_tower.tscn").instantiate()
	world.add_child(tower)
	tower.global_position = Vector2(250, 300)
	var target := _make_target(world, Vector2(430, 300))
	var truck := _make_truck(world, Vector2(100, 300), EnemyScript.EnemyType.SUICIDE)

	await process_frame
	await process_frame

	var res = await _run_until_reached(truck, target, 1200)
	if not res[0]:
		_fail("自爆车没能绕过自家护盾塔: %d 帧内最近 %.1f px" % [res[2], res[1]])
	elif res[1] > 60.0:
		_fail("自爆车在离目标 %.1f px 的地方就炸了 —— 大概率是撞在自家护盾塔上白送了" % res[1])
	else:
		print("  [PASS] %d 帧内绕过自家护盾塔并击中目标。" % res[2])

	await _cleanup([tower, target, truck, world])
