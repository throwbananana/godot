extends SceneTree

## 地图模板的结构与连通性校验, 外加鹰巢的零缝对齐。
##
## 模板列表是*枚举出来*的, 不是手写的。老版本手抄了 36 个名字并且注释写着
## "Validating all 36 Map Templates" —— 而文件里当时已经有 50 个了, 后加的
## JAMMER_OUTPOST / FACTORY_ESCORT / NAVAL_SALVAGE_ROUTE 等等一直没被检查过。
## 手抄的清单一定会过期, 所以改成从脚本常量表里捞所有 TEMPLATE_* 数组。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_map_templates_and_base_fit.gd

const MapTemplates = preload("res://scripts/map_templates.gd")
const GameState = preload("res://scripts/game_state.gd")

# 坦克永远过不去的地形。砖(1)/硬黏土(8)/沙丘(7) 都能打掉, 所以连通性上算通路 ——
# 被砖封住只是要多开几枪, 被钢或水封住才是真的过不去。
const HARD_BLOCK := [2, 3]

# 摆渡/越障装置。地图里只要有这些, 水面就不再是绝对屏障 —— 设计上本来就是
# "靠平台渡过去"。VOID_FERRY / VOID_CANAL 就是这么设计的: 第 3、9 行是整幅
# 水墙, 全靠 1、11 两列的竖向平台(11)摆渡。静态泛洪没法模拟平台的往返路线,
# 所以这里改成: 图里备了渡河手段, 就不再把水判成死路。
const CROSSING_TILES := [10, 11, 12, 22, 23]

# floor 0 那一档允许的地形: 基础地形 + {硬黏土, 地雷, 沙地} 里至多一种。
const BASIC_TILES := [0, 1, 2, 3, 4]
const TIER0_OPTIONAL := [5, 6, 8]

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> MAP TEMPLATE / BASE ALIGNMENT TEST <<<")
	print("==================================================")
	call_deferred("_run")


func _all_templates() -> Dictionary:
	# 必须走 load() 拿到 Script *对象*: 直接写 MapTemplates.get_script_constant_map()
	# 会被解析成"在类上调用非静态方法"而编译失败 —— map_templates.gd 有
	# class_name, 那个标识符指的是类本身, 不是脚本资源。
	var script: Script = load("res://scripts/map_templates.gd")
	var consts: Dictionary = script.get_script_constant_map()
	var out := {}
	for name in consts:
		if not name.begins_with("TEMPLATE_"):
			continue
		var v = consts[name]
		if v is Array and v.size() == 13 and v[0] is Array:
			out[name] = v
	return out


## 从鹰巢那一格泛洪, 返回可达格集合。
func _reachable_from_base(g: Array) -> Dictionary:
	var blockers: Array = HARD_BLOCK.duplicate()
	var has_crossing := false
	for r in range(13):
		for c in range(13):
			if int(g[r][c]) in CROSSING_TILES:
				has_crossing = true
	if has_crossing:
		blockers.erase(3)      # 有摆渡手段, 水不再算死路

	var seen := {}
	var stack: Array = [Vector2i(6, 12)]
	seen[Vector2i(6, 12)] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = cur + d
			if nx.x < 0 or nx.x > 12 or nx.y < 0 or nx.y > 12:
				continue
			if seen.has(nx):
				continue
			if int(g[nx.y][nx.x]) in blockers:
				continue
			seen[nx] = true
			stack.append(nx)
	return seen


func _run() -> void:
	var templates := _all_templates()
	print("\n--- 结构 (%d 张模板) ---" % templates.size())

	var bad := 0
	for name in templates:
		var g: Array = templates[name]
		var errs: Array[String] = []
		if g.size() != 13:
			errs.append("行数 %d != 13" % g.size())
		for r in range(g.size()):
			if g[r].size() != 13:
				errs.append("第 %d 行有 %d 列 != 13" % [r, g[r].size()])
		if errs.is_empty():
			for r in range(13):
				for c in range(13):
					var v = int(g[r][c])
					if v < 0 or v > 29:
						errs.append("(%d,%d) 地形号 %d 越界 (合法 0-29)" % [r, c, v])
			# 鹰巢与围墙由 main.gd::_spawn_base_and_walls() 自己生成在
			# row11 col5-7 / row12 col5,7, 模板必须把这几格留空, 否则会和
			# 自动生成的围墙叠在一起
			for c in [5, 6, 7]:
				if int(g[12][c]) != 0:
					errs.append("鹰巢格 (12,%d) 必须为空" % c)
				if int(g[11][c]) != 0:
					errs.append("鹰巢围墙格 (11,%d) 必须为空" % c)
			if int(g[12][4]) != 0:
				errs.append("P1 出生点 (12,4) 必须为空")
			if int(g[12][8]) != 0:
				errs.append("P2 出生点 (12,8) 必须为空")
			for c in [0, 6, 12]:
				if int(g[0][c]) != 0:
					errs.append("敌人出生点 (0,%d) 必须为空" % c)
		if not errs.is_empty():
			bad += 1
			fail("%s: %s" % [name, "; ".join(errs)])
	if bad == 0:
		ok("%d 张模板全部 13x13, 出生点/鹰巢格留空, 地形号合法" % templates.size())

	# --- 连通性 ---
	print("\n--- 连通性 (钢/水视为永久障碍, 砖与黏土算通路) ---")
	var unreachable := 0
	for name in templates:
		var g: Array = templates[name]
		if g.size() != 13:
			continue
		var seen := _reachable_from_base(g)
		var miss: Array[String] = []
		for c in [0, 6, 12]:
			if not seen.has(Vector2i(c, 0)):
				miss.append("敌人出生点(0,%d)" % c)
		for c in [4, 8]:
			if not seen.has(Vector2i(c, 12)):
				miss.append("玩家出生点(12,%d)" % c)
		if not miss.is_empty():
			unreachable += 1
			fail("%s: %s 到不了鹰巢 —— 被钢/水彻底隔断, 这一侧的敌人永远打不过来"
				% [name, ", ".join(miss)])
	if unreachable == 0:
		ok("%d 张模板的出生点都能通到鹰巢" % templates.size())

	# --- floor 0 档位规则 ---
	# 把 TEMPLATE_MIN_FLOOR 注释里写的那条约定变成可执行的检查, 免得以后有人
	# 往入门池里塞一张风机/传送带图, 让第一层的玩家当场面对没学过的机制。
	print("\n--- floor 0 入门档地形限制 ---")
	var gate: Dictionary = MapTemplates.TEMPLATE_MIN_FLOOR
	var tier0_bad := 0
	var tier0_names: Array[String] = []
	for name in templates:
		var g: Array = templates[name]
		if gate.get(g, 0) != 0:
			continue
		if not _in_act1_pool(name):
			continue
		tier0_names.append(name)
		var used := {}
		for r in range(13):
			for c in range(13):
				used[int(g[r][c])] = true
		var optional: Array = []
		var advanced: Array = []
		for v in used:
			if v in BASIC_TILES:
				continue
			if v in TIER0_OPTIONAL:
				optional.append(v)
			else:
				advanced.append(v)
		if not advanced.is_empty():
			tier0_bad += 1
			fail("%s 在入门池里却用了需要现学的机制地形 %s" % [name, str(advanced)])
		elif optional.size() > 1:
			tier0_bad += 1
			fail("%s 同时用了 %s —— 入门档只允许 {硬黏土,地雷,沙地} 里的一种"
				% [name, str(optional)])
	if tier0_bad == 0:
		ok("入门池 %d 张 (%s) 全部只用基础地形" % [tier0_names.size(), ", ".join(tier0_names)])

	_check_entry_maps_reachable(templates)
	await _check_base_alignment()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL MAP TEMPLATE CHECKS PASSED! <<<")
		quit(0)


## act1 常规战池的成员名单。这里写死是有意的 —— get_layout_for_stage() 把池子
## 建在函数局部变量里, 从外面拿不到, 而这条检查的意义正是"盯住入门池"。
## 池子改了这里没改的话, 下面那条断言会报出来。
func _in_act1_pool(name: String) -> bool:
	return name in [
		"TEMPLATE_CLASSIC", "TEMPLATE_RIVERS", "TEMPLATE_JUNGLE", "TEMPLATE_CHECKERBOARD",
		"TEMPLATE_CITADEL", "TEMPLATE_MEADOW_OUTPOST", "TEMPLATE_BRICK_COURTYARD",
		"TEMPLATE_CREEK_CROSSING", "TEMPLATE_ORCHARD_ROWS",
	]


## 入门图必须真的能在一个 act 里被抽到。
##
## 这条是照着一个真实踩过的坑写的: 新图当初是*追加到 act1_pool 末尾*的, 看着
## 没问题, 实际永远抽不到。原因是 _pick_from_pool 用
## `eligible[floor_idx % eligible.size()]`, 而一个 act 只有 15 层, 再扣掉
## `floor_idx % 3 == 2` 的程序生成层, 真正用模板的只有十层, 能取到的下标就那
## 十个 —— 排在 14 号往后的条目根本轮不上。加图不是往数组里塞一个元素就完事,
## 还得让它落在会被取到的下标上。
func _check_entry_maps_reachable(templates: Dictionary) -> void:
	print("\n--- 入门图在一个 act 内可被抽到 ---")
	var by_layout := {}
	for n in templates:
		by_layout[templates[n]] = n

	GameState.current_act = 1
	var seen := {}
	for f in range(15):        # GameState.max_floors
		var g = MapTemplates.get_layout_for_stage(f, "battle", 1, true)
		var nm = by_layout.get(g, "")
		if nm != "":
			seen[nm] = f

	var want := ["TEMPLATE_MEADOW_OUTPOST", "TEMPLATE_BRICK_COURTYARD",
				 "TEMPLATE_CREEK_CROSSING", "TEMPLATE_ORCHARD_ROWS"]
	var missing: Array[String] = []
	var where: Array[String] = []
	for n in want:
		if seen.has(n):
			where.append("%s@f%d" % [n.replace("TEMPLATE_", ""), seen[n]])
		else:
			missing.append(n)
	if missing.is_empty():
		ok("四张入门图都会在 act 1 的 15 层内出现 (%s)" % ", ".join(where))
	else:
		fail("%s 在 act 1 的任何一层都抽不到 —— 多半是排在了取不到的下标上"
			% ", ".join(missing))

	# 顺带确认它们确实排在前段, 而不是挤到深层去
	for n in want:
		if seen.has(n) and seen[n] > 8:
			fail("%s 出现在 floor %d, 对入门图来说太靠后了" % [n, seen[n]])


func _check_base_alignment() -> void:
	print("\n--- 鹰巢与边界墙对齐 ---")
	var main_inst = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame

	var tile_size := 48.0
	var base_inst = main_inst.get("base_instance")
	if base_inst == null:
		fail("鹰巢没有生成")
		main_inst.queue_free()
		return
	var expected_base_y := 12.5 * tile_size
	if absf(base_inst.position.y - expected_base_y) > 0.1:
		fail("鹰巢 y 应为 %.1f, 实际 %.1f" % [expected_base_y, base_inst.position.y])
	else:
		ok("鹰巢位置 %s" % str(base_inst.position))

	var map_container = main_inst.get_node("GameArea/MapContainer")
	var borders = map_container.get_children().filter(func(c): return c.is_in_group("border"))
	if borders.size() != 4:
		fail("边界墙应有 4 面, 实际 %d" % borders.size())
	else:
		ok("四面边界墙齐全")

	var bottom_border: StaticBody2D = null
	for b in borders:
		if b.position.y > 600:
			bottom_border = b
			break
	if bottom_border == null:
		fail("找不到底部边界墙")
	else:
		var expected := (13 * tile_size) + (tile_size / 2.0)
		if absf(bottom_border.position.y - expected) > 0.1:
			fail("底部边界墙 y 应为 %.1f, 实际 %.1f" % [expected, bottom_border.position.y])
		else:
			ok("底部边界墙零缝对齐 (y=%.1f)" % bottom_border.position.y)

	main_inst.queue_free()
	await process_frame
