extends SceneTree

## 双人战役"共享生命池 + 手动复活"的回归测试。
##
## 直接驱动 main.gd 的真实函数 (_on_player_destroyed / _arm_revive_prompt /
## _consume_shared_life_and_respawn / _settle_player), 不重新实现一份逻辑。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_shared_life_revive.gd

const GameState = preload("res://scripts/game_state.gd")
const FloorMap = preload("res://scripts/floor_map.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> SHARED LIFE / MANUAL REVIVE TEST <<<")
	print("==================================================")
	call_deferred("_run")


func _run() -> void:
	await _test_shared_2p_campaign()
	await _test_room_transition_guard()
	await _test_1p_regression()
	await _test_2p_arcade_regression()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL SHARED LIFE / REVIVE CHECKS PASSED! <<<")
		quit(0)


func _boot_campaign_2p() -> Node:
	GameState.reset_campaign(2)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var m = main_scene.instantiate()
	root.add_child(m)
	return m


func _enter_first_combat_room(m) -> void:
	for k in GameState.floor_rooms.keys():
		if FloorMap.is_combat_room(GameState.floor_rooms[k]):
			m.enter_room(str(k), -1)
			return


## 让一名玩家真正"死亡": queue_free 掉它的坦克并等待删除生效, 而不是直接
## 把变量置空 —— _arm_revive_prompt() 用的是 is_instance_valid(), 跟真实的
## player.gd::_die() -> queue_free() 之后的状态一致才有意义。
func _kill_player(m, pid: int) -> void:
	var inst = m.p1_instance if pid == 1 else m.p2_instance
	if inst and is_instance_valid(inst):
		inst.queue_free()
	await process_frame
	await process_frame


func _test_shared_2p_campaign() -> void:
	print("\n--- 双人战役: 死亡不自动重生, 按键才扣共享命 ---")
	var m = _boot_campaign_2p()
	await process_frame
	_enter_first_combat_room(m)
	await process_frame

	if not (m.p1_instance and is_instance_valid(m.p1_instance)):
		fail("进入战斗房后 P1 应该已经生成")
		m.queue_free()
		return

	var start_lives := GameState.player_lives
	await _kill_player(m, 1)
	m._on_player_destroyed(1)

	if GameState.player_lives != start_lives:
		fail("死亡瞬间就扣了共享生命 (期望死亡不扣命, 复活才扣) —— %d -> %d"
			% [start_lives, GameState.player_lives])
	elif m.p1_awaiting_revive:
		fail("_on_player_destroyed() 不该在延迟结束前就直接挂出复活提示")
	else:
		ok("死亡后共享生命未变 (%d), 也还没挂出复活提示" % GameState.player_lives)

	# 跳过真实的 1.5 秒延迟, 直接调用延迟结束后的那一步。
	m._arm_revive_prompt(1)
	if not m.p1_awaiting_revive:
		fail("_arm_revive_prompt() 之后 p1_awaiting_revive 应为 true")
	elif GameState.player_lives != start_lives:
		fail("挂出复活提示这一步不该扣命")
	else:
		ok("延迟结束后正确挂出 P1 的复活提示, 命数仍是 %d" % GameState.player_lives)

	# 模拟按下 P1 的开火键触发手动复活。
	Input.action_press("p1_fire")
	await process_frame
	Input.action_release("p1_fire")

	if m.p1_awaiting_revive:
		fail("按下开火键之后复活提示应该已经清除")
	if not (m.p1_instance and is_instance_valid(m.p1_instance)):
		fail("按下开火键之后 P1 应该已经重新生成")
	if GameState.player_lives != start_lives - 1:
		fail("按键复活应该恰好扣 1 条共享生命 —— %d -> %d (期望 %d)"
			% [start_lives, GameState.player_lives, start_lives - 1])
	else:
		ok("按开火键复活成功: P1 重新生成, 共享生命 %d -> %d"
			% [start_lives, GameState.player_lives])

	m.queue_free()
	await process_frame


func _test_room_transition_guard() -> void:
	print("\n--- 队友先走门, 等待复活的玩家不能白嫖一条命 ---")
	var m = _boot_campaign_2p()
	await process_frame
	_enter_first_combat_room(m)
	await process_frame

	await _kill_player(m, 2)
	m._arm_revive_prompt(2)
	if not m.p2_awaiting_revive:
		fail("前置条件失败: P2 应处于等待复活状态")
		m.queue_free()
		return

	var lives_before := GameState.player_lives
	# 模拟一次房间切换的重新落位 (_place_players_at_entry 内部会对每个玩家调
	# _settle_player) —— 这是曾经会白送一条命的地方: _settle_player 看到
	# p2_instance 是空的就直接 _spawn_player(2), 完全绕开手动复活的扣命步骤。
	m._place_players_at_entry(-1)
	await process_frame

	if m.p2_instance and is_instance_valid(m.p2_instance):
		fail("房间切换不该白送复活 —— P2 在没按键的情况下被自动生成了")
	elif GameState.player_lives != lives_before:
		fail("房间切换不该扣共享生命 —— %d -> %d" % [lives_before, GameState.player_lives])
	elif not m.p2_awaiting_revive:
		fail("房间切换之后 P2 应该仍处于等待复活状态")
	else:
		ok("房间切换没有让等待复活的 P2 白嫖一条命 (仍等待, 命数仍是 %d)" % lives_before)

	m.queue_free()
	await process_frame


func _test_1p_regression() -> void:
	print("\n--- 回归: 单人模式死亡仍然自动重生 (不受本次改动影响) ---")
	GameState.reset_campaign(1)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var m = main_scene.instantiate()
	root.add_child(m)
	await process_frame
	_enter_first_combat_room(m)
	await process_frame

	var start_lives := GameState.player_lives
	await _kill_player(m, 1)
	m._on_player_destroyed(1)

	if GameState.player_lives != start_lives - 1:
		fail("单人模式死亡应该立刻扣命 (自动重生逻辑) —— %d -> %d"
			% [start_lives, GameState.player_lives])
	elif m.p1_awaiting_revive:
		fail("单人模式不该出现 shared-revive 的等待状态")
	else:
		ok("单人模式死亡行为未变: 立刻扣命 (%d -> %d), 不等待按键"
			% [start_lives, GameState.player_lives])

	m.queue_free()
	await process_frame


func _test_2p_arcade_regression() -> void:
	print("\n--- 回归: 双人街机死亡仍然自动重生 (不走共享池) ---")
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var m = main_scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame

	if not (m.p1_instance and is_instance_valid(m.p1_instance)):
		fail("双人街机应该在 start_game() 里直接生成 P1")
		m.queue_free()
		GameState.reset_campaign(1)
		return

	var before: int = m.p1_lives
	await _kill_player(m, 1)
	m._on_player_destroyed(1)

	if m.p1_lives != before - 1:
		fail("双人街机死亡应该立刻扣本局命数 —— %d -> %d" % [before, m.p1_lives])
	elif m.p1_awaiting_revive:
		fail("双人街机不该出现 shared-revive 的等待状态")
	else:
		ok("双人街机死亡行为未变: 立刻扣命 (%d -> %d), 不等待按键" % [before, m.p1_lives])

	m.queue_free()
	await process_frame
	GameState.reset_campaign(1)
