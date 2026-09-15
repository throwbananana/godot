extends SceneTree

## 隐藏测试模式 (暗号解锁的关卡跳转 + 战斗内调试面板) 的回归测试。
##
## 分两半, 跟功能本身的两半对应:
## 1. "跳关" 机制 —— 复刻 debug_test_menu.gd::_on_jump_pressed() 对 GameState
##    做的那几步 (reset_campaign -> 指定 act -> generate_floor -> 强改起始房
##    的 type/cleared -> 可选 playtest_layout), 不走真的按钮点击/场景跳转
##    (SceneTree 脚本没有"当前场景"这个概念, change_scene_to_file 在这里没
##    有意义去断言), 而是直接验证这几步产生的 GameState 是不是
##    main.gd::enter_room() 认得的合法状态。
## 2. main.gd 里 F1 呼出的那块调试面板 —— 只有 GameState.debug_unlocked 时
##    才应该被建出来, 且每个按钮的效果都应该是复用游戏本来就有的路径。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_debug_test_mode.gd

const GameState = preload("res://scripts/game_state.gd")
const FloorMap = preload("res://scripts/floor_map.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> HIDDEN TEST MODE (debug jump / F1 panel) TEST <<<")
	print("==================================================")
	call_deferred("_run")


func _run() -> void:
	_test_jump_forces_room_type("boss")
	_test_jump_forces_room_type("shop")
	_test_jump_forces_room_type("challenge")
	await _test_jump_applies_playtest_layout()
	await _test_debug_panel_hidden_by_default()
	await _test_debug_panel_built_when_unlocked()
	await _test_debug_tools_reuse_real_paths()

	GameState.debug_unlocked = false
	GameState.playtest_layout = []

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL HIDDEN TEST MODE CHECKS PASSED! <<<")
		quit(0)


## 复刻 debug_test_menu.gd::_on_jump_pressed() 对 GameState 做的那几步,
## 不含 UI/场景跳转。
func _do_debug_jump(act: int, room_type: String, challenge_kind: String = "") -> void:
	GameState.reset_campaign(1)
	GameState.current_act = act
	GameState.generate_floor()
	var room_key := GameState.current_room
	var room: Dictionary = GameState.floor_rooms[room_key]
	room["type"] = room_type
	room["challenge_mode"] = challenge_kind
	room["cleared"] = false
	GameState.floor_rooms[room_key] = room


func _test_jump_forces_room_type(room_type: String) -> void:
	print("\n--- 跳关强改起始房类型: %s ---" % room_type)
	_do_debug_jump(2, room_type, "bomb_rain" if room_type == "challenge" else "")

	var room: Dictionary = GameState.current_room_data()
	if room.is_empty():
		fail("跳关后 current_room_data() 应该能拿到房间数据")
		return

	if bool(room.get("cleared", true)):
		fail("[%s] 强改类型后 cleared 应该被拨回 false, 否则 is_combat_room() 会当它已经打完" % room_type)
	else:
		ok("[%s] cleared 已拨回 false" % room_type)

	var expect_combat := room_type != "shop"
	if FloorMap.is_combat_room(room) != expect_combat:
		fail("[%s] is_combat_room() 期望 %s, 实际 %s" % [room_type, expect_combat, FloorMap.is_combat_room(room)])
	else:
		ok("[%s] is_combat_room() 判定正确 (%s)" % [room_type, expect_combat])

	var expect_bt := "elite" if room_type == "elite" else room_type
	if room_type == "normal":
		expect_bt = "battle"
	var actual_bt := GameState.battle_type_for_room(room)
	if actual_bt != expect_bt:
		fail("[%s] battle_type_for_room() 期望 %s, 实际 %s" % [room_type, expect_bt, actual_bt])
	else:
		ok("[%s] battle_type_for_room() 正确映射为 %s" % [room_type, expect_bt])


func _test_jump_applies_playtest_layout() -> void:
	print("\n--- 跳关时指定内置模板, 走 playtest_layout 一次性覆盖 ---")
	_do_debug_jump(1, "boss")

	var map_templates_script: Script = load("res://scripts/map_templates.gd")
	var consts: Dictionary = map_templates_script.get_script_constant_map()
	if not consts.has("TEMPLATE_BOSS_ARENA"):
		fail("前置条件失败: 找不到 TEMPLATE_BOSS_ARENA 常量")
		return
	var forced_layout: Array = (consts["TEMPLATE_BOSS_ARENA"] as Array).duplicate(true)
	GameState.playtest_layout = forced_layout

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var m = main_scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame

	if not GameState.playtest_layout.is_empty():
		fail("main.gd::_build_map() 应该在读取 playtest_layout 后立刻清空它")
	else:
		ok("playtest_layout 被 _build_map() 读取并清空 (一次性覆盖语义保持不变)")

	if m.current_map_layout.size() != forced_layout.size():
		fail("跳关指定的模板没有被实际用来建图")
	else:
		ok("跳关指定的内置模板被用来建了图 (%d 行)" % m.current_map_layout.size())

	m.queue_free()
	await process_frame
	GameState.playtest_layout = []


func _test_debug_panel_hidden_by_default() -> void:
	print("\n--- 未解锁时: main.tscn 不应该建出调试面板 ---")
	GameState.debug_unlocked = false
	_do_debug_jump(1, "normal")

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var m = main_scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame

	if m.debug_panel != null:
		fail("GameState.debug_unlocked=false 时不该建出 debug_panel 节点")
	else:
		ok("debug_panel 保持为 null, 正常玩家的场景里没有这个节点")

	m.queue_free()
	await process_frame


func _test_debug_panel_built_when_unlocked() -> void:
	print("\n--- 解锁后: 面板存在但默认隐藏, F1 切换可见性 ---")
	GameState.debug_unlocked = true
	_do_debug_jump(1, "normal")

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var m = main_scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame

	if m.debug_panel == null:
		fail("GameState.debug_unlocked=true 时应该建出 debug_panel 节点")
		m.queue_free()
		await process_frame
		return
	if m.debug_panel.visible:
		fail("debug_panel 应该默认隐藏, 需要按 F1 才出现")
	else:
		ok("debug_panel 存在且默认隐藏")

	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_F1
	m._unhandled_input(ev)
	if not m.debug_panel.visible:
		fail("按一次 F1 之后 debug_panel 应该显示")
	else:
		ok("F1 正确切换 debug_panel 为可见")

	m._unhandled_input(ev)
	if m.debug_panel.visible:
		fail("再按一次 F1 应该把 debug_panel 收起来")
	else:
		ok("再按一次 F1 正确收起 debug_panel")

	m.queue_free()
	await process_frame


func _test_debug_tools_reuse_real_paths() -> void:
	print("\n--- 调试工具按钮效果: 无敌切换 / 清空本房敌人 ---")
	GameState.debug_unlocked = true
	_do_debug_jump(1, "normal")

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var m = main_scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame

	if not (m.p1_instance and is_instance_valid(m.p1_instance)):
		fail("前置条件失败: P1 应该已经在战斗房里生成")
		m.queue_free()
		await process_frame
		return

	# 出生自带的 3.5s 无敌先跑完, 否则下面 "OFF" 那一段会被它掩盖掉,
	# 看不出 _debug_apply_god_mode(false) 到底有没有真的关掉无敌。
	m.p1_instance.is_invulnerable = false
	m.p1_instance.invulnerable_timer = 0.0

	m._debug_apply_god_mode(true)
	if not m.p1_instance.is_invulnerable:
		fail("GOD MODE 打开后 P1 应该处于无敌状态")
	else:
		ok("GOD MODE 打开后 P1 无敌 (set_invulnerable 复用现有倒计时逻辑)")

	m._debug_apply_god_mode(false)
	if m.p1_instance.is_invulnerable:
		fail("GOD MODE 关闭后 P1 不应该继续无敌")
	else:
		ok("GOD MODE 关闭后正确恢复")

	# 刷怪走 spawn_star 的 finished 回调, 不是同一帧就位 (CLAUDE.md 的平衡采样
	# 踩过这个坑, 那边的 _await_spawns() 轮询上限是 240-600 帧) —— 轮询到出现
	# 存活敌人为止, 而不是固定等几帧。同时按同一个理由每帧强制解除暂停:
	# 场上刷出的敌人互相残杀会掉 XP, 升级会弹 upgrade_selection_dialog.gd,
	# 它会把整棵 SceneTree 暂停, 而暂停期间 spawn_star 的 _process() 计时器
	# 永远走不完, 后面所有 finished 回调都不会再来。
	var waited := 0
	while m.enemies_alive <= 0 and waited < 400:
		if paused:
			paused = false
		await process_frame
		waited += 1

	var before_alive: int = m.enemies_alive
	if before_alive <= 0:
		fail("前置条件失败: 战斗房应该已经有存活敌人, 否则清房测试没有意义")
	else:
		await m._debug_clear_room()
		if m.enemies_alive > 0:
			fail("_debug_clear_room() 之后 enemies_alive 应该归零 (期望 0, 实际 %d)" % m.enemies_alive)
		elif m.total_enemies != m.enemies_spawned:
			fail("_debug_clear_room() 应该把 total_enemies 拉平到 enemies_spawned, 避免 spawner 继续补怪")
		else:
			ok("_debug_clear_room() 杀光了本房 %d 只敌人, 且不再补新的" % before_alive)

	m.queue_free()
	await process_frame
