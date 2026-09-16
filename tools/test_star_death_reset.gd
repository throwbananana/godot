extends SceneTree

# 硬核成长规则回归闸门：战场上吃到的 STAR 是“这一条命”的强化，不是永久存档。
#
# 当前架构里经典线 tier 有两份值：
#   - PlayerTank.upgrade_tier：当前这条命真正使用的战斗 tier
#   - GameState.player_tier / p2_tier：跨场景/战役状态的基线
#
# STAR 只能修改第一份。玩家死亡后重新 _spawn_player() 时，会从 GameState 的
# 基线重新建立坦克，因此本条命吃到的 STAR 必须丢失。这是硬核难度设计，不是
# “掉级 bug”。如果以后有人把 STAR 即时写回 GameState（例如为了所谓
# “死亡后不回退”），这个测试必须立刻报红。
#
# 升级卡/地图外奖励是否修改 GameState 是另一条规则，本测试不干预；这里只钉住
# “战场 STAR 不持久化”以及 P1/P2 两条出生路径行为一致。

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
	print(">>> RUNNING STAR DEATH RESET TEST <<<")
	print("==================================================")

	if not await _boot():
		print("  [FAIL] main.tscn 没能启动或双人坦克未生成")
		quit(1)
		return

	await _check_player(1)
	await _check_player(2)

	if _failed:
		print("\n>>> STAR DEATH RESET: 有检查未通过 <<<")
	else:
		print("\n>>> ALL STAR DEATH RESET CHECKS PASSED! <<<")
	quit(1 if _failed else 0)


func _boot() -> bool:
	GameState.reset_campaign(2)
	GameState.mode = GameState.GameMode.CAMPAIGN
	GameState.player_tier = 0
	GameState.p2_tier = 0
	GameState.tank_branch = "default"
	GameState.p2_branch = "default"

	var scn = load("res://scenes/main.tscn")
	if not scn:
		return false
	_main = scn.instantiate()
	root.add_child(_main)
	current_scene = _main
	await _settle(24)
	return is_instance_valid(_main.get("p1_instance")) and is_instance_valid(_main.get("p2_instance"))


func _tank(pid: int):
	return _main.p1_instance if pid == 1 else _main.p2_instance


func _stored_tier(pid: int) -> int:
	return GameState.player_tier if pid == 1 else GameState.p2_tier


func _set_stored_tier(pid: int, value: int) -> void:
	if pid == 1:
		GameState.player_tier = value
	else:
		GameState.p2_tier = value


func _check_player(pid: int) -> void:
	print("\n[STEP] P%d：STAR 只强化当前生命，复活回到基线..." % pid)

	# 每段都从最基础 tier 开始。rpg_mgr 的共享 level 会继续增长，但它不是这里
	# 要验证的武器 tier；本测试只盯 PlayerTank.upgrade_tier 的生命期。
	_set_stored_tier(pid, 0)
	var before = _tank(pid)
	if not is_instance_valid(before):
		_fail("P%d 测试开始前坦克不存在" % pid)
		return
	before.upgrade_tier = 0

	before.apply_powerup(PowerUpScript.Type.STAR)
	await _settle(4)

	if before.upgrade_tier != 1:
		_fail("P%d 吃 1 颗 STAR 后现场 tier 应为 1，实际 %d" % [pid, before.upgrade_tier])
		return
	if _stored_tier(pid) != 0:
		_fail("P%d 的 STAR 被错误写入 GameState：基线从 0 变成 %d；死亡后将不会掉级" % [pid, _stored_tier(pid)])
		return
	_ok("P%d：STAR 只改现场 tier，GameState 基线仍为 0。" % pid)

	# 不调用完整 take_damage()：那条路径包含无敌帧、共享生命池和延迟复活，
	# 会把这个单一规则测试变成整套死亡系统测试。这里直接模拟死亡后真正发生的
	# “旧实例消失 -> _spawn_player(pid) 新建实例”这条边界。
	before.queue_free()
	await _settle(2)
	if pid == 1:
		_main.p1_instance = null
	else:
		_main.p2_instance = null
	_main._spawn_player(pid)
	await _settle(6)

	var after = _tank(pid)
	if not is_instance_valid(after):
		_fail("P%d 模拟复活后没有重新生成坦克" % pid)
		return
	if after.upgrade_tier != 0:
		_fail("P%d 复活后应回到基础 tier 0（游戏内等级 1），实际 tier %d" % [pid, after.upgrade_tier])
	else:
		_ok("P%d：复活后 tier 1 -> 0，硬核死亡惩罚保持。" % pid)


func _settle(frames: int) -> void:
	for _i in range(frames):
		# STAR 的 add_level() 可能触发升级选择并暂停场景树；测试没有真人点卡，
		# 所以每帧强制解除暂停，避免 await 卡死成假 TIMEOUT。
		paused = false
		await process_frame
