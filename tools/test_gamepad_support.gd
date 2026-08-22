extends SceneTree

## 手柄支持的回归测试。
##
## 覆盖两处此前完全缺失的能力:
##   1. 建造系统只认原始 keycode (event.keycode == KEY_Q ...), 手柄玩家一个建筑
##      都放不了 —— 移动和开火早有手柄绑定, 唯独建造没有。
##   2. 全项目一处 grab_focus() 都没有, 所以没有任何控件拿得到初始焦点。没有
##      焦点就没有 ui_up/down/accept 的落点, 手柄连"开始游戏"都按不到。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_gamepad_support.gd

const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> GAMEPAD SUPPORT REGRESSION TEST <<<")
	print("==================================================")

	_check_actions()
	_check_no_button_conflicts()
	# 必须 await —— _check_focus_helper() 内部有 await process_frame (focus_first
	# 是 call_deferred 的)。不 await 的话它只会返回一个协程, _init 直接往下跑到
	# quit(), 那一整节检查一行都不会执行, 测试却报"全部通过"。
	await _check_focus_helper()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL GAMEPAD SUPPORT CHECKS PASSED! <<<")
		quit(0)


func _pad_events(action: String) -> Array:
	var out: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			out.append(e)
	return out


func _check_actions() -> void:
	print("\n--- 每个可玩 action 都必须有手柄绑定 ---")
	# 每名玩家在战斗中需要的全部操作。少任何一个, 那名玩家就有事情做不了。
	var per_player := ["move_up", "move_down", "move_left", "move_right", "fire",
		"build_prev", "build_next", "build_place", "build_cancel"]
	for pid in [1, 2]:
		var missing: Array[String] = []
		for verb in per_player:
			var a := "p%d_%s" % [pid, verb]
			if not InputMap.has_action(a):
				missing.append(a + "(未定义)")
			elif _pad_events(a).is_empty():
				missing.append(a + "(无手柄事件)")
		if missing.is_empty():
			ok("P%d 的 %d 个操作全部可用手柄" % [pid, per_player.size()])
		else:
			fail("P%d 缺失: %s" % [pid, ", ".join(missing)])

	if not InputMap.has_action("pause"):
		fail("pause action 未定义")
	elif _pad_events("pause").is_empty():
		fail("pause 没有手柄绑定 —— 手柄玩家开不了暂停菜单")
	else:
		ok("pause 可用手柄 (%d 个手柄事件)" % _pad_events("pause").size())

	# 两名玩家必须用不同的手柄设备, 否则一个手柄会同时开两辆坦克
	for verb in ["move_up", "fire", "build_place"]:
		var d1 := _devices("p1_" + verb)
		var d2 := _devices("p2_" + verb)
		if d1.is_empty() or d2.is_empty():
			continue
		for d in d1:
			if d2.has(d):
				fail("p1_%s 与 p2_%s 共用手柄设备 %d" % [verb, verb, d])


func _devices(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for e in _pad_events(action):
		if not out.has(e.device):
			out.append(e.device)
	return out


func _check_no_button_conflicts() -> void:
	print("\n--- 同一设备上同一颗键不能绑到两个战斗内 action ---")
	# 只查战斗内同时生效的 action。restart 与 pause 都用 START 是有意的:
	# restart 只在 is_game_over/is_victory 时读取, 而 pause 恰好排除了那两种状态
	# (见 main.gd::_unhandled_input), 所以同一颗键在任一时刻只有一个含义。
	var in_battle: Array[String] = []
	for pid in [1, 2]:
		for verb in ["move_up", "move_down", "move_left", "move_right", "fire",
				"build_prev", "build_next", "build_place", "build_cancel"]:
			in_battle.append("p%d_%s" % [pid, verb])
	in_battle.append("pause")

	var seen := {}   # "device:button" -> action
	for a in in_battle:
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if not (e is InputEventJoypadButton):
				continue
			var key := "%d:%d" % [e.device, e.button_index]
			if seen.has(key) and seen[key] != a:
				fail("设备 %d 的按键 %d 同时绑到 %s 和 %s" % [e.device, e.button_index, seen[key], a])
			else:
				seen[key] = a
	if failures == 0:
		ok("战斗内 %d 个 action 的手柄按键无冲突" % in_battle.size())

	# B(1) 是 Godot 内置 ui_cancel 的默认绑定, 菜单里当"返回"用。
	# 战斗内 action 不能占它, 否则一次按键会既操作战斗又关掉界面。
	for a in in_battle:
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton and e.button_index == 1:
				fail("%s 绑在 B 键上 —— 会和内置 ui_cancel(菜单返回) 打架" % a)


func _check_focus_helper() -> void:
	print("\n--- focus_first 必须挑到可见且可用的按钮 ---")
	var root_node := Control.new()
	root.add_child(root_node)

	var vbox := VBoxContainer.new()
	root_node.add_child(vbox)

	# 第一个隐藏 (标题界面没存档时"继续游戏"就是这样), 第二个禁用, 第三个才是答案
	var hidden := Button.new()
	hidden.text = "hidden"
	hidden.visible = false
	vbox.add_child(hidden)

	var disabled := Button.new()
	disabled.text = "disabled"
	disabled.disabled = true
	vbox.add_child(disabled)

	var good := Button.new()
	good.text = "good"
	vbox.add_child(good)

	UIThemeHelper.focus_first(root_node)
	# focus_first 用的是 call_deferred, 等一帧
	await process_frame
	await process_frame

	if good.has_focus():
		ok("跳过了隐藏和禁用的按钮, 焦点落在第一个可用按钮上")
	elif hidden.has_focus():
		fail("焦点落在隐藏按钮上 —— 手柄会卡在看不见的控件里")
	elif disabled.has_focus():
		fail("焦点落在禁用按钮上")
	else:
		fail("没有任何按钮拿到焦点 —— 手柄在菜单里无从下手")

	# 传 CanvasLayer 不能崩: upgrade_selection_dialog 的根节点就是 CanvasLayer
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var lbtn := Button.new()
	layer.add_child(lbtn)
	UIThemeHelper.focus_first(layer)
	await process_frame
	await process_frame
	if lbtn.has_focus():
		ok("根节点是 CanvasLayer 时同样可用")
	else:
		fail("根节点为 CanvasLayer 时 focus_first 失效")
