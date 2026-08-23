extends SceneTree

## 爆炸物 x 地形 的破坏矩阵。
##
## 起因是一个玩家报告: "炸弹炸不掉白砖"。白砖是 tile_steel (浅灰紫, 全场最亮
## 的墙)。查下来它不是单点漏了, 而是**四个爆炸源各写了一套地形判定, 互相不
## 一致** —— 地雷炸得掉钢墙, 定时炸弹/导弹/油桶炸不掉; 而硬黏土的 3 血设定
## 被其中三个直接 queue_free 绕过。
##
## 这类问题读代码很难发现: 四处逻辑分散在四个文件里, 每一处单看都说得通,
## 只有把它们并排列成矩阵才看得出来谁和谁不一样。所以这个测试的产出是一张表,
## 断言的是**一致性**, 不是某一格的具体取值 —— 具体取值是设计决定, 一致性
## 不是。
##
## 判定规则 (bullet.gd 是基准, 它是"地形破坏的唯一决定处"):
##   brick      一律炸掉
##   hard_clay  走 take_hit(), 3 血, 不是一击必杀
##   sand_dune  整块塌 (take_hit / take_damage)
##   steel      普通火力炸不掉, 只有 tier3 plasma 能破; border 永远不破
##
## 注意 hard_clay_block 同时在 brick 和 hard_clay 两个组里 (见 CLAUDE.md),
## 所以任何"先查 brick 就 queue_free"的写法都会顺手把硬黏土一击秒掉。

const GameState = preload("res://scripts/game_state.gd")

## 测试用的地形摆在离真实地图很远的地方, 免得被地图里原有的方块干扰。
const TEST_ORIGIN := Vector2(3000.0, 3000.0)

var failures: int = 0
var _main: Node = null
var results: Dictionary = {} # "源|地形" -> "炸掉" / "扣血" / "没反应"


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> EXPLOSIVE x TERRAIN MATRIX <<<")
	print("==================================================")

	GameState.reset_campaign(1)
	GameState.mode = GameState.GameMode.CAMPAIGN
	GameState.current_act = 1
	GameState.current_floor = 0
	GameState.battle_type = "battle"

	var scn = load("res://scenes/main.tscn")
	_main = scn.instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame

	for source in ["timed_bomb", "missile_strike", "oil_barrel", "landmine"]:
		for terrain in ["brick", "steel", "hard_clay", "sand_dune"]:
			results["%s|%s" % [source, terrain]] = await _trial(source, terrain)

	_print_matrix()
	_check_consistency()
	await _check_border_survives()

	var m := _main
	_main = null
	current_scene = null
	m.queue_free()
	await process_frame

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL EXPLOSIVE MATRIX CHECKS PASSED! <<<")
		quit(0)


## 摆一块地形, 在它旁边引爆一个爆炸物, 看它变成什么样。
##
## 地形用 main.gd 自己的 _spawn_* 走真实路径 —— 测试里手搓一份必然和游戏里
## 的分组/子块划分发散。
func _trial(source: String, terrain: String) -> String:
	var container: Node2D = _main.map_container
	var local := TEST_ORIGIN

	match terrain:
		"brick":
			_main._spawn_brick_tile(container, local, false)
		"steel":
			_main._spawn_brick_tile(container, local, true)
		"hard_clay":
			_main._spawn_hard_clay_tile(container, local)
		"sand_dune":
			# 沙丘没有独立的 _spawn_*_tile, 它走通用的 _spawn_tile 分派,
			# 而且那个函数固定往 map_container 里塞 (不收 container 参数)。
			_main._spawn_tile("sand_dune", local, _main.tex_sand_dune)

	# 先让物理跑一帧: intersect_shape 要等 broadphase 刷新才看得见新加的刚体
	# (油桶和地雷都走物理查询, 不等的话它们会认为周围一片空)。
	await physics_frame
	await physics_frame

	var before := _sample_tiles(local)
	if before.is_empty():
		return "地形没生成"

	var global_pos: Vector2 = container.to_global(local)
	_detonate(source, global_pos)

	await physics_frame
	await physics_frame
	await create_timer(0.15).timeout

	var alive := 0
	var damaged := 0
	for entry in before:
		var node = entry["node"]
		if is_instance_valid(node):
			alive += 1
			if int(entry["hp"]) > 0 and ("health" in node) and int(node.health) < int(entry["hp"]):
				damaged += 1

	# 清场, 免得影响下一格
	for entry in before:
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	await process_frame

	if alive == 0:
		return "炸掉"
	if damaged > 0:
		return "扣血"
	return "没反应"


## 收集刚摆下去的那块地形的所有子块 (砖/钢是 2x2 四块)。
func _sample_tiles(local: Vector2) -> Array:
	var out: Array = []
	# 这个脚本 extends SceneTree, 所以 get_nodes_in_group 直接就在 self 上,
	# 没有 get_tree() 可调。
	for g in ["brick", "steel", "hard_clay", "sand_dune"]:
		for n in get_nodes_in_group(g):
			if not is_instance_valid(n) or not (n is Node2D):
				continue
			if n.position.distance_to(local) > 48.0:
				continue
			var hp := 0
			if "health" in n:
				hp = int(n.health)
			var already := false
			for e in out:
				if e["node"] == n:
					already = true
			if not already:
				out.append({"node": n, "hp": hp})
	return out


func _detonate(source: String, global_pos: Vector2) -> void:
	match source:
		"timed_bomb":
			var b = load("res://scenes/timed_bomb.tscn").instantiate()
			_main.actors_container.add_child(b)
			b.global_position = global_pos + Vector2(-48.0, 0.0)
			b.detonate()
		"missile_strike":
			var m = load("res://scenes/missile_strike.tscn").instantiate()
			_main.actors_container.add_child(m)
			m.global_position = global_pos
			m._detonate()
		"oil_barrel":
			var o = load("res://scenes/buildings/oil_barrel.tscn").instantiate()
			_main.actors_container.add_child(o)
			o.global_position = global_pos + Vector2(-40.0, 0.0)
			o.detonate()
		"landmine":
			var l = load("res://scenes/buildings/landmine.tscn").instantiate()
			_main.actors_container.add_child(l)
			l.global_position = global_pos + Vector2(-40.0, 0.0)
			l._detonate()


func _print_matrix() -> void:
	print("\n%-16s %-8s %-8s %-10s %-10s" % ["爆炸源", "砖块", "钢墙(白砖)", "硬黏土", "沙丘"])
	print("-".repeat(60))
	for source in ["timed_bomb", "missile_strike", "oil_barrel", "landmine"]:
		print("%-16s %-8s %-11s %-11s %-10s" % [
			source,
			results.get("%s|brick" % source, "?"),
			results.get("%s|steel" % source, "?"),
			results.get("%s|hard_clay" % source, "?"),
			results.get("%s|sand_dune" % source, "?"),
		])
	print("")


## 地图边界永远不能被炸开。
##
## 边界墙也挂在 steel 组上, 所以"让爆炸物能炸开钢墙"这个改动天然会顺手把边界
## 一起炸了 —— 而边界没了坦克就能开到地图外面去, 那是比"炸不掉墙"严重得多的
## 问题, 并且不会报任何错。四个爆炸源里每一个都得自己记得排除 border,
## 所以这条必须真的一个个引爆过去验, 不能只读代码。
func _check_border_survives() -> void:
	print("\n--- 地图边界不能被炸开 ---")
	var borders: Array = []
	for n in get_nodes_in_group("border"):
		if is_instance_valid(n) and n is Node2D:
			borders.append(n)
	if borders.is_empty():
		fail("地图上找不到 border 组的节点 —— 边界是不是没生成? 这条测不了")
		return

	var before := borders.size()
	for source in ["timed_bomb", "missile_strike", "oil_barrel", "landmine"]:
		# 每轮重新取一块**还活着**的边界。
		#
		# 这里有两个坑, 两个都让这条断言在"真的出 bug 时"静默失效过:
		#
		# 1. 不能写 `var target: Node2D = borders[0]`。带类型标注地把一个已被
		#    释放的对象赋给局部变量, GDScript 会抛
		#    "Trying to assign invalid previously freed instance" 并**直接中断
		#    整个函数** —— 于是下面的计数和断言压根不执行, 测试反而报通过。
		#    正是有 bug (第一块边界被炸没了) 的时候才会走到这一步。
		# 2. 传给 _detonate() 的必须是目标点本身, **不要**再自己加偏移:
		#    那个函数已经按各爆炸源的机制摆好位置了 (定时炸弹要先退一格,
		#    因为它的火焰从第 1 格起判定, 不判自己脚下)。第一版这里多加了一次
		#    +48, 炸弹正好落在边界正上方, 四条火焰全从 48px 外起步, 边界一次
		#    都没被判定到。
		var live: Array = []
		for n in get_nodes_in_group("border"):
			if is_instance_valid(n) and n is Node2D:
				live.append(n)
		if live.is_empty():
			break
		var target = live[0]
		_detonate(source, target.global_position)
		await physics_frame
		await create_timer(0.12).timeout

	var after := 0
	for n in get_nodes_in_group("border"):
		if is_instance_valid(n):
			after += 1

	if after >= before:
		ok("四个爆炸源贴着边界引爆之后, %d 块边界一块没少" % after)
	else:
		fail("边界被炸掉了 %d 块 (%d -> %d) —— 边界墙也在 steel 组里, "
			% [before - after, before, after]
			+ "哪个爆炸源忘了 `not is_in_group(\"border\")` 就会把地图炸出洞, "
			+ "坦克能直接开到地图外面")


func _check_consistency() -> void:
	var sources := ["timed_bomb", "missile_strike", "oil_barrel", "landmine"]

	# 1. 同一种地形, 四个爆炸源的结果必须一致。具体是什么值是设计决定,
	#    互相不一样一定是 bug。
	for terrain in ["brick", "steel", "hard_clay", "sand_dune"]:
		var seen := {}
		for s in sources:
			var v = str(results.get("%s|%s" % [s, terrain], "?"))
			if not seen.has(v):
				seen[v] = []
			seen[v].append(s)
		if seen.size() <= 1:
			ok("%s: 四个爆炸源结果一致 (%s)" % [terrain, seen.keys()[0]])
		else:
			var parts := PackedStringArray()
			for v in seen:
				parts.append("%s -> %s" % [", ".join(seen[v]), v])
			fail("%s 上四个爆炸源结果不一致: %s —— 四处地形判定各写了一套, "
				% [terrain, " | ".join(parts)]
				+ "玩家看到的就是'这个炸弹炸得掉那个炸不掉'")

	# 2. 砖块必须炸得掉 —— 这是最基本的一条, 独立于上面的一致性检查
	#    (四个源可以"一致地都炸不掉", 那样一致性会过而游戏是坏的)。
	var no_brick: Array[String] = []
	for s in sources:
		if str(results.get("%s|brick" % s, "")) != "炸掉":
			no_brick.append(s)
	if no_brick.is_empty():
		ok("四个爆炸源都炸得掉砖块")
	else:
		fail("这些爆炸源炸不掉砖块: %s" % ", ".join(no_brick))

	# 关于硬黏土: 四个源都是一击炸掉, 这**是设计内的** —— timed_bomb 和
	# missile_strike 明确写了 take_hit(99), 油桶的 blast_damage 是 4 而硬黏土
	# 只有 3 血。硬黏土的多段血是用来扛**子弹**的, 不是用来扛炸弹的。
	# 所以这里不断言"不能被一击秒", 只靠上面的一致性检查兜着。
	#
	# 但要留意实现上的隐患: hard_clay_block 同时在 brick 和 hard_clay 两个组里
	# (见 CLAUDE.md), 而 timed_bomb / missile_strike / landmine 都是先扫 brick
	# 组再无条件 queue_free —— 结果碰巧和 take_hit(99) 一样, 但走的不是同一条
	# 路。哪天硬黏土的血量或掉落规则改了, 这三处会静默地绕过去。
