extends SceneTree

## 关卡编辑器后端的自动化覆盖: CustomMapStore 的存档往返、
## MapTemplates.validate_layout() 的结构/连通性判定、以及自定义图确实能被
## get_layout_for_stage() 的池子抽到 (不是排在取不到的下标上那种死代码,
## 参见 tools/test_map_templates_and_base_fit.gd 里同一个教训)。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_custom_map_editor.gd

const MapTemplates = preload("res://scripts/map_templates.gd")
const CustomMapStore = preload("res://scripts/custom_map_store.gd")
const GameState = preload("res://scripts/game_state.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> CUSTOM MAP EDITOR TEST <<<")
	print("==================================================")
	call_deferred("_run")


func _run() -> void:
	_test_store_roundtrip()
	_test_validate_layout()
	_test_pool_splicing()
	_test_boss_branch_regression()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL CUSTOM MAP EDITOR CHECKS PASSED! <<<")
		quit(0)


## 造一张保证合法连通的图: TEMPLATE_CLASSIC 的深拷贝, 不直接用引用是因为
## 下面的测试会原地改格子, 改了常量数组本身会污染其它测试和真实游戏。
func _sample_valid_grid() -> Array:
	return MapTemplates.TEMPLATE_CLASSIC.duplicate(true)


# ---------------------------------------------------------------------------
# 1. CustomMapStore 存档往返 —— 全程重定向到临时文件, 绝不碰玩家真实的
#    user://custom_maps.json。
# ---------------------------------------------------------------------------
func _test_store_roundtrip() -> void:
	print("\n--- CustomMapStore 存档往返 ---")
	var real_path := CustomMapStore.save_path
	CustomMapStore.save_path = "user://test_custom_maps_tmp.json"
	CustomMapStore.invalidate_cache()

	var entry := {
		"id": "test_entry_1",
		"name": "测试关卡",
		"layout": _sample_valid_grid(),
		"acts": [1, 2],
		"battle_types": ["battle"],
		"min_floor": 3,
	}
	CustomMapStore.upsert(entry)

	CustomMapStore.invalidate_cache()  # 强制重新读盘, 而不是信任内存缓存
	var loaded := CustomMapStore.get_by_id("test_entry_1")
	if loaded.is_empty():
		fail("upsert 后重新读盘找不到条目")
	elif loaded.get("name", "") != "测试关卡" or loaded.get("min_floor", -1) != 3:
		fail("读盘后字段不一致: %s" % str(loaded))
	else:
		ok("新增条目正确落盘并可重新读出")

	entry["name"] = "测试关卡(改名)"
	CustomMapStore.upsert(entry)
	CustomMapStore.invalidate_cache()
	var all := CustomMapStore.load_all()
	if all.size() != 1:
		fail("按 id 覆盖失败, 变成了 %d 条而不是 1 条" % all.size())
	elif CustomMapStore.get_by_id("test_entry_1").get("name", "") != "测试关卡(改名)":
		fail("按 id 覆盖没有更新字段")
	else:
		ok("同 id 再次 upsert 是覆盖, 不是追加")

	CustomMapStore.delete("test_entry_1")
	CustomMapStore.invalidate_cache()
	if not CustomMapStore.get_by_id("test_entry_1").is_empty():
		fail("delete 之后条目还在")
	else:
		ok("delete 之后条目消失")

	# 清理临时文件, 恢复真实路径 —— 顺序很重要: 先删文件, 再切回真实路径
	# 并让下次 load_all() 强制重新读盘, 否则后面的测试会一直读到这份缓存。
	var tmp_global := ProjectSettings.globalize_path(CustomMapStore.save_path)
	if FileAccess.file_exists(CustomMapStore.save_path):
		DirAccess.remove_absolute(tmp_global)
	CustomMapStore.save_path = real_path
	CustomMapStore.invalidate_cache()


# ---------------------------------------------------------------------------
# 2. validate_layout(): 一个通过用例, 两个刻意造坏的失败用例。
# ---------------------------------------------------------------------------
func _test_validate_layout() -> void:
	print("\n--- MapTemplates.validate_layout() ---")

	var good := _sample_valid_grid()
	var errs_good := MapTemplates.validate_layout(good)
	if not errs_good.is_empty():
		fail("TEMPLATE_CLASSIC 的拷贝本应合法, 却报错: %s" % ", ".join(errs_good))
	else:
		ok("TEMPLATE_CLASSIC 拷贝通过校验 (0 项错误)")

	var bad_eagle := _sample_valid_grid()
	bad_eagle[12][6] = 1  # 鹰巢格摆了砖墙
	var errs_eagle := MapTemplates.validate_layout(bad_eagle)
	if errs_eagle.is_empty():
		fail("鹰巢格 (12,6) 非空却没有报错")
	elif errs_eagle.filter(func(e: String): return e.contains("鹰巢格")).is_empty():
		fail("鹰巢格非空但错误信息里没提到鹰巢: %s" % ", ".join(errs_eagle))
	else:
		ok("鹰巢格被占用能正确报错: %s" % ", ".join(errs_eagle))

	# 角落 (0,0) 是敌人出生点, 把它两条唯一的出路 (0,1)/(1,0) 都堵上钢墙,
	# 让它跟鹰巢彻底断联, 同时保持其它结构规则合法。
	var bad_conn := []
	for r in range(13):
		var row: Array = []
		row.resize(13)
		row.fill(0)
		bad_conn.append(row)
	bad_conn[0][1] = 2
	bad_conn[1][0] = 2
	var errs_conn := MapTemplates.validate_layout(bad_conn)
	if errs_conn.is_empty():
		fail("敌人出生点被钢墙彻底封死却没有报连通性错误")
	elif errs_conn.filter(func(e: String): return e.contains("到不了鹰巢")).is_empty():
		fail("连通性失败但错误信息没提到'到不了鹰巢': %s" % ", ".join(errs_conn))
	else:
		ok("被封死的出生点能正确报连通性错误: %s" % ", ".join(errs_conn))


# ---------------------------------------------------------------------------
# 3. 自定义图确实会被 get_layout_for_stage() 的池子抽到, 不是死代码。
# ---------------------------------------------------------------------------
func _test_pool_splicing() -> void:
	print("\n--- 自定义图接入 get_layout_for_stage() 的池子 ---")
	var real_path := CustomMapStore.save_path
	CustomMapStore.save_path = "user://test_custom_maps_tmp2.json"
	CustomMapStore.invalidate_cache()

	# 造一张跟任何内置模板都不同的图 (在角落画一格地雷做标记), 这样可以用
	# 数组相等来判断"这次抽到的到底是不是我们的自定义图"。
	var custom_layout := _sample_valid_grid()
	custom_layout[1][1] = 5
	CustomMapStore.upsert({
		"id": "test_pool_entry",
		"name": "池子测试图",
		"layout": custom_layout,
		"acts": [1],
		"battle_types": ["battle"],
		"min_floor": 0,
	})

	var old_seed := GameState.run_seed
	var drawn := false
	for s in [0, 1, 7919, 123457, 555555]:
		GameState.run_seed = s
		for f in range(15):
			var g = MapTemplates.get_layout_for_stage(f, "battle", 1, false, "")
			if g == custom_layout:
				drawn = true
				break
		if drawn:
			break
	GameState.run_seed = old_seed

	if drawn:
		ok("自定义图在若干局里确实被 battle 池抽到过至少一次")
	else:
		fail("自定义图在 5 局 x 15 层里一次都没被抽到 —— 多半是拼接位置有问题")

	CustomMapStore.delete("test_pool_entry")
	var tmp_global := ProjectSettings.globalize_path(CustomMapStore.save_path)
	if FileAccess.file_exists(CustomMapStore.save_path):
		DirAccess.remove_absolute(tmp_global)
	CustomMapStore.save_path = real_path
	CustomMapStore.invalidate_cache()


# ---------------------------------------------------------------------------
# 4. 回归防护: Boss 分支从"返回单张固定模板"改成"从池子里选"之后, 在没有
#    任何自定义图时必须原样返回改造前的那张图 —— 池子大小恰好是 1。
#
#    Act 1~3 (第一轮周目, get_difficulty_cycle() == 0) 各自固定一张主题
#    专属图; act 4 (第二轮周目起, cycle >= 1) 换成 TITAN_BOSS 的太阳神泰坦
#    神殿, 与 main.gd 的 Boss 类型选择 (同样按 difficulty_cycle 切换) 对齐 ——
#    见 map_templates.gd::get_layout_for_stage() 里的说明。
# ---------------------------------------------------------------------------
func _test_boss_branch_regression() -> void:
	print("\n--- Boss 分支空自定义池回归检查 ---")
	var real_path := CustomMapStore.save_path
	CustomMapStore.save_path = "user://test_custom_maps_tmp3.json"
	CustomMapStore.invalidate_cache()  # 空文件 = 空自定义池

	var expected := {
		1: MapTemplates.TEMPLATE_BOSS_ARENA,
		2: MapTemplates.TEMPLATE_SPEEDWAY,
		3: MapTemplates.TEMPLATE_GLACIER_BUNKER_REDOUBT,
		4: MapTemplates.TEMPLATE_SOLAR_TITAN_SANCTUM,
	}
	var bad := 0
	for act in expected:
		var g = MapTemplates.get_layout_for_stage(10, "boss", act, false, "")
		if g != expected[act]:
			bad += 1
			fail("act %d 的 boss 图在空自定义池下变了" % act)
	if bad == 0:
		ok("四个 act 的 boss 图在空自定义池下都符合预期 (含第二轮周目切换)")

	CustomMapStore.save_path = real_path
	CustomMapStore.invalidate_cache()
