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
const MapDirector = preload("res://scripts/map_director.gd")
const FloorMap = preload("res://scripts/floor_map.gd")

# 连通性判定统一走 MapDirector.reachable_from_base()。
#
# 这里原本有一份自己的实现 (HARD_BLOCK = [2,3] + CROSSING_TILES), 而
# MapDirector 后来为程序生成又写了一份 —— 同一个"什么叫通得过去"在两处
# 各说各话, 正是本仓库在 build_*.py 上吃过大亏的那种重复。两份还真的不一样:
# 这边把电墙(25)当可通行, 而电墙是 StaticBody2D 且加入 steel 组, 只有 3 阶
# 等离子弹打得穿, 对绝大多数单位就是钢墙。改用生产代码那一份 (含 25, 同时
# 保留"图里备了渡河手段就不把水判成死路"的摆渡语义) —— 已核对过 54 张模板
# 里没有一张因为收紧而变得不连通, 所以这是补上盲区, 不是放宽或收紧标准。

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


## 从鹰巢那一格泛洪, 返回可达格集合。见文件头: 判定本身在 MapDirector 里,
## 这里只是转调, 免得同一套规则在两处漂移。
func _reachable_from_base(g: Array) -> Dictionary:
	return MapDirector.reachable_from_base(g)


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
					# 合法上界跟着 map_templates.gd 顶上那份图例走 (0..39)
					if v < 0 or v > 39:
						errs.append("(%d,%d) 地形号 %d 越界 (合法 0-39)" % [r, c, v])
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
	var want := ["TEMPLATE_MEADOW_OUTPOST", "TEMPLATE_BRICK_COURTYARD",
				 "TEMPLATE_CREEK_CROSSING", "TEMPLATE_ORCHARD_ROWS"]

	# 选图现在按 run_seed 洗牌 (每局换一批图, 见 _pool_index), 所以"这四张
	# 特定的图出现在第几层"不再对任意单局成立 —— 只对旧的确定性取模成立。
	# 但那个断言本来也只是代理: 它真正要守的是**开局几层必须温和**, 以及
	# **新加的图不能落在永远取不到的下标上**。这两条各自直接验。
	var seeds: Array = [0, 1, 7919, 123457, 555555, 987654321]

	# (a) 新图不能是死代码: across 若干局, 每张入门图都必须至少被抽到过一次。
	var ever := {}
	for s in seeds:
		GameState.run_seed = s
		for f in range(15):
			var nm = by_layout.get(MapTemplates.get_layout_for_stage(f, "battle", 1, true), "")
			if nm != "":
				ever[nm] = true
	var missing: Array[String] = []
	for n in want:
		if not ever.has(n):
			missing.append(n.replace("TEMPLATE_", ""))
	if missing.is_empty():
		ok("四张入门图在 %d 局里都被抽到过 (act 1 共见到 %d 张不同模板)"
			% [seeds.size(), ever.size()])
	else:
		fail("%s 在 %d 局 x 15 层里一次都没出现 —— 多半是排在了取不到的下标上"
			% [", ".join(missing), seeds.size()])

	# (b) 真正的不变量: 无论哪一局, floor 0/1 抽到的都必须是入门档的图。
	#     这条比"那四张图排在前面"强 —— 它管的是每一张可能被抽到的图。
	var harsh: Array[String] = []
	for s in seeds:
		GameState.run_seed = s
		for f in [0, 1]:
			var g = MapTemplates.get_layout_for_stage(f, "battle", 1, true)
			var nm = by_layout.get(g, "<procgen>")
			if not _is_entry_tier(g):
				harsh.append("seed %d floor %d -> %s" % [s, f, nm.replace("TEMPLATE_", "")])
	if harsh.is_empty():
		ok("%d 局的 floor 0/1 全部是纯基础地形的入门图" % seeds.size())
	else:
		fail("开局层抽到了非入门档的图: %s" % ", ".join(harsh))

	GameState.run_seed = 0


## 入门档 = 只用基础地形, 外加 {硬黏土/地雷/沙地} 里至多一种。
## 与本文件 "入门池全部只用基础地形" 那条检查同一把尺子。
func _is_entry_tier(g: Array) -> bool:
	var optional_used := {}
	for r in range(g.size()):
		for c in range(g[r].size()):
			var v := int(g[r][c])
			if v in BASIC_TILES:
				continue
			if v in TIER0_OPTIONAL:
				optional_used[v] = true
				continue
			return false
	return optional_used.size() <= 1


func _check_base_alignment() -> void:
	print("\n--- 鹰巢与边界墙对齐 ---")
	var main_inst = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame

	# 以撒式房间下, 起始房既没有敌人也**没有鹰巢** —— 基地只在还没打完的战斗房
	# 里存在, 而且清空之后会被 _despawn_base() 撤掉 (否则它那一坨会永久堵住底边
	# 中段)。所以要先走进一间战斗房再验。
	_enter_first_combat_room(main_inst)
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
	# border 组的成员现在有两类: 边墙本身, 以及关着的门 (RoomDoor 内部那个
	# blocker 也挂 border —— 否则一颗地雷就能在没清空的房间里炸出个出口)。
	# 门是 RoomDoor 的子节点, 不是 MapContainer 的直接子节点, 所以这里只数到墙。
	var borders = map_container.get_children().filter(func(c): return c.is_in_group("border"))
	# 每条边: 没门 = 1 段整墙, 有门 = 正中缺一格, 拆成 2 段。所以总数 = 4 + 门数。
	# 这一条同时验收了"门确实在墙上开了个洞"—— 段数不对就说明缺口没切出来,
	# 而那种情况在画面上看起来完全正常 (门画在那儿), 只是走不过去。
	var door_count: int = main_inst.doors.size()
	var expected_borders: int = 4 + door_count
	if borders.size() != expected_borders:
		fail("边界墙应有 %d 段 (4 条边 + %d 扇门各多切一段), 实际 %d"
			% [expected_borders, door_count, borders.size()])
	else:
		ok("边界墙 %d 段, 对应 %d 扇门" % [borders.size(), door_count])

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


## 走进本层第一间还没打完的战斗房。
##
## 以撒式房间下, main.tscn 一启动进的是**起始房** —— 没有敌人, 也没有鹰巢
## (基地只在战斗房里生成, 而且一清空就被撤掉)。任何要验鹰巢/铲子/敌人的测试
## 都得先挪进一间战斗房, 否则测到的是一间空房, 报出来的是"鹰巢没有生成"这种
## 看起来像功能坏了、实际只是站错房间的结论。
func _enter_first_combat_room(main_node) -> void:
	if GameState.mode != GameState.GameMode.CAMPAIGN:
		return
	for k in GameState.floor_rooms.keys():
		if FloorMap.is_combat_room(GameState.floor_rooms[k]):
			main_node.enter_room(str(k), -1)
			return
