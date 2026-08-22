extends SceneTree

## 随机地图控制器 (MapDirector) 的测试。
##
## 锁的是三件事:
##   1. **难度随楼层递增**。程序生成原本完全绕开楼层门禁 —— 敌人有
##      ENEMY_MIN_FLOOR、手搓地图有 TEMPLATE_MIN_FLOOR, 而 generate_map()
##      连 floor 参数都没有。偏偏 get_layout_for_stage() 转到程序生成的第一层
##      就是 floor 2, 实测那张图平均 29 格机制地形 / 6 种机制 (act 3 是 55/7),
##      而同层手搓模板只能是纯地形 —— 全局最难的图出现在第三层。
##   2. **产出一定可玩**: 出生点/鹰巢格留空、出生点通得到鹰巢、不会糊成一堵墙。
##   3. **同种子同图**: 每日挑战全服一张图, 不可复现就等于每人一张。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_map_director.gd

const MapDirector = preload("res://scripts/map_director.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> MAP DIRECTOR TEST <<<")
	print("==================================================")
	_check_tiers()
	_check_budget_and_validity()
	_check_ramp()
	_check_determinism()
	_check_validate_catches_bad()
	_check_repair()
	_check_fallback()
	_check_layout_pipeline()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL MAP DIRECTOR CHECKS PASSED! <<<")
		quit(0)


func _check_tiers() -> void:
	print("\n--- 楼层分档 ---")
	# 与 TEMPLATE_MIN_FLOOR 的 0/2/5 三档对齐
	var want := {0: 0, 1: 0, 2: 1, 3: 1, 4: 1, 5: 2, 9: 2, 14: 2}
	var bad := 0
	for f in want:
		var t: int = MapDirector.tier_for_floor(f)
		if t != want[f]:
			fail("floor %d 应为档 %d, 实际 %d" % [f, want[f], t])
			bad += 1
	if bad == 0:
		ok("楼层→档位与 TEMPLATE_MIN_FLOOR 的 0/2/5 分档一致")


func _mech_families(g: Array) -> Array:
	return MapDirector.families_in(g)


func _check_budget_and_validity() -> void:
	print("\n--- 各档机制族上限 + 产出可玩性 ---")
	for tier in range(3):
		var floor_idx: int = MapDirector.TIER_FLOORS[tier]
		var cap: int = MapDirector.TIER_BUDGET[tier]["families"]
		var worst := 0
		var invalid := 0
		var combos := {}
		var N := 30
		for act in [1, 2, 3]:
			for i in range(N):
				var g = MapDirector.build(floor_idx, act)
				var fams = _mech_families(g)
				worst = maxi(worst, fams.size())
				combos[", ".join(fams)] = true
				var problems = MapDirector.validate(g, tier)
				if not problems.is_empty():
					invalid += 1
					if invalid == 1:
						fail("档 %d act %d 产出未通过验收: %s" % [tier, act, str(problems)])
		if worst > cap:
			fail("档 %d 允许 %d 族, 实际出现 %d 族" % [tier, cap, worst])
		elif invalid == 0:
			ok("档 %d: 最多 %d/%d 族, %d 张全部通过验收, %d 种不同机制组合"
				% [tier, worst, cap, N * 3, combos.size()])


func _check_ramp() -> void:
	print("\n--- 难度确实随楼层上升 ---")
	# 这条是本次修复的核心回归: floor 2 必须明显比 floor 5 温和。
	# 旧实现两者完全一样 (都是满配), 这条会失败。
	var avg := {}
	for f in [0, 2, 5]:
		var tot := 0
		var N := 30
		for act in [1, 2, 3]:
			for i in range(N):
				tot += _mech_families(MapDirector.build(f, act)).size()
		avg[f] = float(tot) / float(N * 3)
	print("    平均机制族数: floor0=%.1f  floor2=%.1f  floor5=%.1f" % [avg[0], avg[2], avg[5]])
	if avg[0] > 0.01:
		fail("floor 0 应该是纯地形图, 实际平均 %.1f 族" % avg[0])
	elif not (avg[2] < avg[5]):
		fail("floor 2 (%.1f 族) 没有比 floor 5 (%.1f 族) 更温和 —— 程序生成又绕开楼层门禁了"
			% [avg[2], avg[5]])
	else:
		ok("0 族 -> %.1f 族 -> %.1f 族, 难度随楼层递增" % [avg[2], avg[5]])


func _check_determinism() -> void:
	print("\n--- 同种子可复现 ---")
	var a = MapDirector.build(5, 2, 987654, 2)
	var b = MapDirector.build(5, 2, 987654, 2)
	var c = MapDirector.build(5, 2, 987655, 2)
	if str(a) != str(b):
		fail("同一个种子生成了两张不同的图 —— 每日挑战会变成每人一张")
	elif str(a) == str(c):
		fail("不同种子生成了同一张图 —— 种子没起作用")
	else:
		ok("同种子同图, 换种子换图")


func _check_validate_catches_bad() -> void:
	print("\n--- 验收能抓出坏图 ---")
	# 全钢的图: 既堵死又隔断
	var walled: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(2)
		walled.append(row)
	var p1 = MapDirector.validate(walled, 0)
	if p1.is_empty():
		fail("一张全是钢墙的图居然通过了验收")
	else:
		ok("全钢图被拦下 (%d 条问题, 首条: %s)" % [p1.size(), p1[0]])

	# 占用鹰巢格
	var g2 = MapDirector.build(0, 1)
	g2[12][6] = 2
	if MapDirector.validate(g2, 0).is_empty():
		fail("鹰巢格被钢占用却通过了验收")
	else:
		ok("鹰巢格被占用能被抓出")

	# 超出档位的机制族
	var g3 = MapDirector.build(0, 1)
	g3[5][2] = 25   # 电墙
	g3[5][4] = 22   # 跳板
	g3[7][2] = 12   # 虫洞
	if MapDirector.validate(g3, 0).is_empty():
		fail("档 0 的图混进了三种机制却通过了验收")
	else:
		ok("超档机制族能被抓出")


func _check_repair() -> void:
	print("\n--- 隔断能被修复 ---")
	# 用一整道钢墙把上半张图和鹰巢隔开, 看控制器还能不能交出可玩的图。
	# 直接调 build() 是验"整条流水线"而不是某个私有函数: 无论它是靠重摇还是
	# 靠开路解决的, 只要交出来的图是通的就算过。
	var stuck := 0
	for i in range(20):
		var g = MapDirector.build(5, 1)
		var seen = MapDirector.reachable_from_base(g)
		for c in [0, 6, 12]:
			if not seen.has(Vector2i(c, 0)):
				stuck += 1
				break
	if stuck > 0:
		fail("20 张里有 %d 张的敌人出生点通不到鹰巢" % stuck)
	else:
		ok("20 张随机图的出生点全部通得到鹰巢")

	# 直接验修复函数: 手工造一张被钢墙腰斩的图
	var g2: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(2 if r == 6 else 0)
		g2.append(row)
	MapDirector._repair_connectivity(g2)
	var seen2 = MapDirector.reachable_from_base(g2)
	var still_cut: Array[String] = []
	for c in [0, 6, 12]:
		if not seen2.has(Vector2i(c, 0)):
			still_cut.append("(0,%d)" % c)
	if not still_cut.is_empty():
		fail("腰斩图修复后 %s 仍然通不过去" % ", ".join(still_cut))
	else:
		ok("被钢墙腰斩的图能被开出通路")


func _check_fallback() -> void:
	print("\n--- 兜底图自己也得合格 ---")
	# build() 连摇八次都没过验收时会交出 _fallback_grid()。这是最后一道防线,
	# 而它是手写死的、不经过验收就直接返回 —— 一旦有人改动它 (比如为了好看
	# 多摆两块钢), 整个"至少给一张能玩的图"的承诺会静默失效, 而且恰恰只在
	# 最坏情况下才暴露。所以这里明确验一遍。
	var g = MapDirector._fallback_grid()
	var problems = MapDirector.validate(g, 0)
	if problems.is_empty():
		ok("_fallback_grid() 通过验收 (13x13 / 留空格 / 连通 / 不堵)")
	else:
		fail("兜底图自己就不合格: %s" % str(problems))


func _check_layout_pipeline() -> void:
	print("\n--- 端到端: get_layout_for_stage() 交出去的每张图都能玩 ---")
	# 上面所有检查都是直接调 MapDirector.build()。但真正喂给
	# main.gd::_build_map() 的是 MapTemplates.get_layout_for_stage(),
	# 中间还隔着"按 floor_idx % 3 == 2 分流到程序生成"和
	# "raw act -> GameState.get_visual_act() 折算"两步 —— 接线错了的话
	# 上面的检查一条都不会红。
	#
	# act 取 1/2/3 之外还取了 5: 第 4 幕以后会绕回三套视觉主题, 传原始幕号
	# 进去必须被折算成 1-3, 否则 MapDirector 拿到的 biome 是错的。
	#
	# validate 传 -1 (跳过机制族上限): 这一支还会返回手搓模板, 而模板本来就
	# 允许堆机制, 族数上限只约束程序生成。结构/留空格/连通/不堵这四项对两者
	# 一视同仁。
	var bad := 0
	var checked := 0
	for act in [1, 2, 3, 5]:
		for f in range(15):
			var g = MapTemplates.get_layout_for_stage(f, "battle", act, true)
			checked += 1
			var problems = MapDirector.validate(g, -1)
			if not problems.is_empty():
				bad += 1
				if bad <= 3:
					fail("act %d floor %d 交出的图不合格: %s" % [act, f, str(problems)])
	if bad == 0:
		ok("%d 组 (act x floor) 全部合格, 含 5 个程序生成层" % checked)
	else:
		fail("共 %d/%d 组不合格" % [bad, checked])
