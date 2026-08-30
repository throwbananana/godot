extends SceneTree

## 持久化与同步的往返测试。
##
## CLAUDE.md 里写着: "加一个持久化数值意味着要动 GameState、RPGManager、
## 两处 copy point, **外加 save_campaign()/load_campaign()**, 否则它会在
## 楼层之间或存档之间静默重置。" 这份纪律原本全靠人记 —— 而漏掉的后果
## 不报错、不崩溃, 只是玩家的东西没了。这个测试把它变成自动闸门。
##
## 关键性质: 字段列表是**反射枚举**的, 不是手抄的。以后新增的 static var
## 默认必须能穿过存档往返; 想豁免必须显式写进 EXEMPT 并附理由。也就是说
## "忘了改 save_campaign" 会直接让这个测试变红, 而不是等玩家来报。
## (本文件里的模板测试也吃过手抄清单过期的亏: 那份清单停在 36 张,
##  文件里已经有 50 张。)

const GameState = preload("res://scripts/game_state.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")

## 不要求穿过 save/load 往返的字段, 每条都要有理由。
const EXEMPT := {
	"_daily_best_score":   "每日挑战纪录, 存在独立的 daily_challenge_save.json 里",
	"_daily_best_date":    "同上",
	"_daily_record_loaded":"同上, 且是缓存标志而非数据",
	"floor_rooms":         "字典套字典还带数组, 本测试用 str() 比字段值, 比不了嵌套结构; 由 test_state_and_save.gd 单独验类型还原 (col/row/depth 必须是 int, doors 必须是长度 4 的数组)",
	"max_acts":            "战役配置, 全项目无人赋值, 等同常量",
	"max_floors":          "同上",
	"playtest_layout":     "关卡编辑器试玩用的一次性图层覆盖, main.gd::_build_map() 读到就立刻清空, 不是某一局的存档数据",
	"debug_unlocked":      "隐藏测试模式是否已解锁, 纯运行期状态 (同一进程内输对一次暗号即保持), 不是某一局战役存档的一部分, 关掉游戏就该恢复隐藏",
}

## RPGManager 里不参与 GameState 往返的字段。
const RPG_EXEMPT := {
	"xp_earned_this_battle": "每场清零, 供 main.gd 的工厂奖励倍率读取, 有意不跨场",
}

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> PERSISTENCE & SYNC ROUNDTRIP TEST <<<")
	print("==================================================")
	_check_save_load_roundtrip()
	_check_rpg_sync_roundtrip()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL PERSISTENCE CHECKS PASSED! <<<")
		quit(0)


## 每个非豁免字段都必须能穿过 save_campaign() -> load_campaign()。
func _check_save_load_roundtrip() -> void:
	print("\n--- GameState 存档往返 ---")
	var s: Script = load("res://scripts/game_state.gd")
	var names: Array[String] = []
	for p in s.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := str(p["name"])
		if EXEMPT.has(n) or n == "mode":   # mode 必须留在合法枚举里
			continue
		names.append(n)

	GameState.reset_campaign(2)

	var stamped := {}
	var i := 0
	for n in names:
		i += 1
		var cur = s.get(n)
		var v = null
		match typeof(cur):
			TYPE_INT:        v = 700 + i
			TYPE_BOOL:       v = not bool(cur)
			TYPE_STRING:     v = "probe_%d" % i
			TYPE_DICTIONARY: v = {"probe_key_%d" % i: i}
			TYPE_ARRAY:
				var a: Array[String] = ["probe_%d" % i]
				v = a
			_: continue
		s.set(n, v)
		# 深拷贝存对照 —— 字典/数组是引用类型, 下面 reset_campaign() 会对
		# unlocked_perks 之类调 .clear(), 存引用的话连对照基准都会被清空,
		# 于是往返明明成功却被判成失败。
		stamped[n] = v.duplicate(true) if (v is Dictionary or v is Array) else v

	GameState.save_campaign()

	# 存完之后主动改成另一个哨兵值再读。只靠 reset_campaign() 擦不干净:
	# 它本身就没有重置所有字段, 那样"从没被擦掉"会被误判成"读回来了"。
	GameState.reset_campaign(1)
	for n in stamped:
		var cur = s.get(n)
		match typeof(cur):
			TYPE_INT:        s.set(n, -99999)
			TYPE_BOOL:       s.set(n, not bool(stamped[n]))
			TYPE_STRING:     s.set(n, "__clobbered__")
			TYPE_DICTIONARY: s.set(n, {"__clobbered__": 1})
			TYPE_ARRAY:
				var w: Array[String] = ["__clobbered__"]
				s.set(n, w)

	if not GameState.load_campaign():
		fail("load_campaign() 返回 false")
		return

	var lost: Array[String] = []
	for n in stamped:
		if str(s.get(n)) != str(stamped[n]):
			lost.append("%s (存 %s, 读回 %s)" % [n, str(stamped[n]), str(s.get(n))])

	if lost.is_empty():
		ok("%d 个字段全部穿过 save -> load 往返" % stamped.size())
	else:
		fail("这些字段没能穿过存档往返 —— save_campaign()/load_campaign() 里多半漏了它们:\n         "
			+ "\n         ".join(lost))

	GameState.delete_saved_game()


## RPGManager 的每个非豁免字段都必须能穿过 sync_to -> sync_from 往返。
## 这两个函数是**手写枚举**的, 和 save_campaign() 一样漏一个不报错。
func _check_rpg_sync_roundtrip() -> void:
	print("\n--- RPGManager <-> GameState 同步往返 ---")
	GameState.reset_campaign(1)
	var mgr = RPGManager.new()
	mgr.sync_from_game_state()

	var names: Array[String] = []
	for p in mgr.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := str(p["name"])
		if RPG_EXEMPT.has(n):
			continue
		names.append(n)

	var stamped := {}
	var i := 0
	for n in names:
		i += 1
		var cur = mgr.get(n)
		var v = null
		match typeof(cur):
			# level 参与升级循环, 给个不会触发连锁升级的小值
			TYPE_INT:        v = (5 + i) if n == "level" else (300 + i)
			TYPE_STRING:     v = "probe_%d" % i
			TYPE_DICTIONARY: v = {"probe_perk_%d" % i: 1}
			TYPE_BOOL:       v = not bool(cur)
			_: continue
		mgr.set(n, v)
		stamped[n] = v.duplicate(true) if v is Dictionary else v

	# current_xp 必须小于 xp_to_next, 否则 sync_from 会触发升级并改写 level
	mgr.xp_to_next = 999999
	stamped["xp_to_next"] = 999999

	mgr.sync_to_game_state()

	var fresh = RPGManager.new()
	fresh.sync_from_game_state()

	var lost: Array[String] = []
	for n in stamped:
		if str(fresh.get(n)) != str(stamped[n]):
			lost.append("%s (写入 %s, 同步回来 %s)" % [n, str(stamped[n]), str(fresh.get(n))])

	if lost.is_empty():
		ok("%d 个字段全部穿过 sync_to -> sync_from 往返" % stamped.size())
	else:
		fail("这些字段没能穿过同步往返 —— sync_to_game_state()/sync_from_game_state() 里多半漏了它们:\n         "
			+ "\n         ".join(lost))
