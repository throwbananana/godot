extends SceneTree

# 经典线升阶卡 (upgrade_selection_dialog.gd::_promote_classic_tier) 的回归闸门。
#
# === 这条守的是什么缺陷 ===
#
# 经典线的阶级在一场战斗里有**两份**值, 而且会分叉:
#   - player.upgrade_tier  —— 战斗中真正被 _shoot()/speed_mult 读的那一份
#   - GameState.player_tier —— 跨幕存档的那一份
# main.gd 开局把后者灌进前者 (_spawn_players), 战斗结束再写回去 (_game_over)。
# 中间这一整场, ⭐ 道具只加 player.upgrade_tier (player.gd 的 STAR 分支), 而
# RPGManager.sync_to_game_state() 的字段表里**没有 player_tier**, 所以 GameState
# 那份一直是落后的。
#
# _live_classic_tier() 已经为了这个分叉改成优先读坦克实例 —— 但那只是"发什么卡"
# 那一半。"点下去做什么"那一半 (_promote_classic_tier) 当时还在拿
# `GameState.player_tier + 1` 再**覆写**回坦克, 于是:
#
#   吃过 1 颗星: 坦克 1 / GameState 0 -> 点卡 -> 两边都成 1。卡面写着
#     TWIN-CANNON, 点下去什么也没发生 —— **一张空卡**。
#   吃过 2 颗星: 坦克 2 / GameState 0 -> 点卡 -> 两边都成 1。玩家选了一张写着
#     PLASMA DREADNOUGHT 的"升阶"卡, 结果**倒退一阶**, 丢掉刚吃到的双管齐射。
#
# 两种情形都没有任何报错。一半的修复等于没修, 所以这条把两半一起钉住。
#
# === 为什么不用 assert ===
#
# 见 CLAUDE.md "Commands": tools/test_*.gd 里的 assert 在 headless 下是挂起而不是
# 失败, run_tests.ps1 只会报一个没有诊断信息的 TIMEOUT; 而散落的 quit(1) 会被
# 同进程后面的 quit(0) 覆盖掉。这里用 _failed 标志 + 末尾唯一一次 quit()。

const PowerUpScript = preload("res://scripts/power_up.gd")

var _failed := false
var _main = null

func _init() -> void:
	call_deferred("_run_tests")

func _fail(msg: String) -> void:
	_failed = true
	print("  [FAIL] %s" % msg)

func _ok(msg: String) -> void:
	print("  [PASS] %s" % msg)

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING CLASSIC TIER PROMOTION TEST <<<")
	print("==================================================")

	if not await _boot():
		print("  [FAIL] main.tscn 没能启动, 无法继续")
		quit(1)
		return

	await _test_card_is_not_a_noop()
	await _test_card_never_regresses()
	await _test_gamestate_matches_tank()

	if _failed:
		print("\n>>> CLASSIC TIER PROMOTION: 有检查未通过 <<<")
	else:
		print("\n>>> ALL CLASSIC TIER PROMOTION CHECKS PASSED! <<<")
	quit(1 if _failed else 0)


func _boot() -> bool:
	GameState.reset_campaign(1)
	GameState.mode = GameState.GameMode.CAMPAIGN
	var scn = load("res://scenes/main.tscn")
	if not scn:
		return false
	_main = scn.instantiate()
	root.add_child(_main)
	current_scene = _main
	await _settle(20)
	return is_instance_valid(_main.get("p1_instance")) and _main.get("upgrade_dialog") != null


## 把经典线拉回起点 —— 两份值都要归零, 否则下一段测的是上一段的残留。
func _reset_tier() -> void:
	_main.rpg_mgr.tank_branch = "default"
	_main.rpg_mgr.branch_tier = 0
	GameState.tank_branch = "default"
	GameState.player_tier = 0
	_main.p1_instance.upgrade_tier = 0


## 从当前卡面里找经典线升阶卡并点它; 找不到返回 false。
func _pick_classic_card() -> bool:
	var dlg = _main.upgrade_dialog
	var choices = dlg._generate_choices(_main.rpg_mgr, 1)
	for c in choices:
		if str(c.get("type", "")) == "classic_tier":
			dlg._on_card_picked(c, _main.rpg_mgr)
			await _settle(2)
			return true
	return false


func _test_card_is_not_a_noop() -> void:
	print("\n[STEP] 吃 1 颗 ⭐ 之后, 经典线卡必须真的升一阶 (不能是空卡)...")
	_reset_tier()
	_main.p1_instance.apply_powerup(PowerUpScript.Type.STAR)
	await _settle(4)
	var after_star: int = _main.p1_instance.upgrade_tier
	if after_star != 1:
		_fail("⭐ 本身应把坦克从 0 升到 1, 实际 %d —— 前提就不成立, 后面的结论无效" % after_star)
		return

	if not await _pick_classic_card():
		_fail("tier 1 时卡面应该还提供经典线升阶卡, 但没找到")
		return

	var after_card: int = _main.p1_instance.upgrade_tier
	if after_card <= after_star:
		_fail("点了经典线升阶卡, 坦克阶级仍是 %d (点之前 %d) —— 这是一张空卡" % [after_card, after_star])
	else:
		_ok("⭐ 0->1, 卡 1->%d: 卡面不是空卡。" % after_card)


func _test_card_never_regresses() -> void:
	print("\n[STEP] 吃 2 颗 ⭐ 之后再点经典线卡, 阶级不得倒退...")
	_reset_tier()
	_main.p1_instance.apply_powerup(PowerUpScript.Type.STAR)
	await _settle(4)
	_main.p1_instance.apply_powerup(PowerUpScript.Type.STAR)
	await _settle(4)
	var before: int = _main.p1_instance.upgrade_tier
	if before != 2:
		_fail("连吃两颗 ⭐ 应到 tier 2, 实际 %d —— 前提不成立" % before)
		return

	if not await _pick_classic_card():
		_fail("tier 2 时卡面应该还提供经典线升阶卡 (下一阶是 3), 但没找到")
		return

	var after: int = _main.p1_instance.upgrade_tier
	if after < before:
		_fail("点了一张升阶卡, 坦克阶级从 %d **倒退**到 %d —— 玩家丢掉了刚吃到的那一阶" % [before, after])
	elif after == before:
		_fail("tier %d 时点经典线卡毫无变化 —— 空卡" % before)
	else:
		_ok("⭐⭐ 0->2, 卡 2->%d: 没有倒退。" % after)


func _test_gamestate_matches_tank() -> void:
	print("\n[STEP] 升阶之后, 跨幕存档的那一份必须和坦克身上的对齐...")
	# 接着上一段的状态: 坦克应该在 3, GameState 也该是 3。两份不一致的话,
	# 这一阶会在 _game_over 回写时被坦克那份覆盖(还好), 或者在下一幕开局被
	# GameState 那份灌回坦克(丢阶) —— 取决于谁先跑, 属于静默的存档漂移。
	var tank_tier: int = _main.p1_instance.upgrade_tier
	if GameState.player_tier != tank_tier:
		_fail("GameState.player_tier=%d 与坦克的 upgrade_tier=%d 不一致" % [GameState.player_tier, tank_tier])
	else:
		_ok("GameState.player_tier 与坦克一致 (都是 %d)。" % tank_tier)


## 推进若干帧, 并且每帧强行解除暂停。
##
## 升级弹窗 (_show_cards) 会 set paused = true, 而这个测试没有人去点卡;
## paused 挂在 SceneTree 上而不是场景上, 所以它活得比场景久 —— CLAUDE.md
## "the upgrade dialog can pause the tree out from under you" 说的就是这件事,
## 不清的话后面所有 await 都不再推进。
func _settle(frames: int) -> void:
	for _i in range(frames):
		paused = false
		await process_frame
