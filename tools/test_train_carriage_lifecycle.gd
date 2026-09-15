extends SceneTree

## 列车分支车厢的生命周期回归测试。
##
## train_carriage.gd::TrainCarriage.destroyed 信号原来发出去了但全仓库没人
## 接 —— 车厢被打掉之后, attached_carriages 里那个失效引用要等下一次
## _sync_train_carriages() (选分支 / 升 tier / 整个场景重新 _ready()) 才会
## 被清掉, 而这三个触发点在 tier2 之后的一局内都不会再发生。净效果: 车厢
## 一旦被打掉, 本局余下时间就是永久性损失, 没有任何测试覆盖过这一点。
##
## 这条测试补上四个从没被测过的行为:
##   1. 炮塔车厢被打掉 -> 连带炸掉挂在它身后的火箭车厢 (leader 链式失效) ->
##      两节都应该在等待期后一起补回来。
##   2. 只有火箭车厢被打掉、炮塔车厢还活着 -> 补回来的应该只有火箭, 不能把
##      活着的炮塔当成"缺失的一节"重新数一遍 (_sync_train_carriages 原来
##      是按*数量*判断缺哪节, 这种情况下会把幸存的炮塔当成新火箭的 leader
##      去 setup 出第二节火箭, 变成两节火箭、没有炮塔——已经在 player.gd
##      里改成按*类型*判断, 这里验证行为)。
##   3. tier1 -> tier2 升级时车厢数量 1 -> 2, 且升级前就存在的炮塔车厢是
##      同一个实例 (不是推倒重来)。
##   4. 机车自身阵亡时, 每节车厢都该收到自己的 destroyed 信号 (对应各自的
##      爆炸/冲击波表现), 而不是被 queue_free() 静默抹掉。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_train_carriage_lifecycle.gd

const RPGManager = preload("res://scripts/rpg_manager.gd")
const PlayerTank = preload("res://scripts/player.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> TRAIN CARRIAGE LIFECYCLE TEST <<<")
	print("==================================================")
	await _check_turret_destroy_cascades_and_respawns()
	await _check_rocket_only_destroy_no_duplicate_turret()
	_check_tier1_to_tier2_transition()
	_check_locomotive_death_signals_each_carriage()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL TRAIN CARRIAGE LIFECYCLE CHECKS PASSED! <<<")
		quit(0)


## 生成一个真实的 train 分支 PlayerTank (走 .tscn, 不是裸 .new(), 原因同
## test_player_power.gd: @onready var sprite = $Sprite2D 只有从场景实例化
## 才解析得到)。current_scene 换成一个只挂着 rpg_mgr 的最小替身, 车厢的
## setup()/_carriage_damage() 都是靠这个鸭子类型拿到 rpg_mgr 的。
func _spawn_train_player(tier: int) -> Dictionary:
	var host := Node.new()
	host.set_script(load("res://tools/_player_power_host.gd"))
	root.add_child(host)

	var m := RPGManager.new()
	m.reset()
	m.tank_branch = "train"
	m.branch_tier = tier
	host.rpg_mgr = m

	current_scene = host
	var p = load("res://scenes/player.tscn").instantiate()
	root.add_child(p)

	return {"host": host, "mgr": m, "player": p}


func _cleanup(rig: Dictionary) -> void:
	var p = rig["player"]
	if is_instance_valid(p):
		p.queue_free()
	current_scene = null
	if is_instance_valid(rig["host"]):
		rig["host"].free()


func _find_carriage(p, carriage_type: String):
	for c in p.attached_carriages:
		if is_instance_valid(c) and c.carriage_type == carriage_type:
			return c
	return null


# ---------------------------------------------------- 1. 炮塔被打掉的连锁反应

func _check_turret_destroy_cascades_and_respawns() -> void:
	print("\n--- 炮塔车厢被打掉 -> 火箭连带炸掉 -> 两节都会补回来 ---")
	var rig := _spawn_train_player(2)
	var p = rig["player"]

	if p.attached_carriages.size() != 2:
		fail("tier2 出生时应该有 2 节车厢, 实际 %d 节" % p.attached_carriages.size())
		_cleanup(rig)
		return

	var turret = _find_carriage(p, "turret")
	var rocket = _find_carriage(p, "rocket")
	if turret == null or rocket == null:
		fail("没能同时找到 turret 和 rocket 车厢")
		_cleanup(rig)
		return

	turret.take_damage(999)
	if p.attached_carriages.size() != 1:
		fail("炮塔被打掉之后应该立刻剩 1 节 (火箭), 实际 %d 节 —— destroyed 信号是不是没接上"
			% p.attached_carriages.size())
	elif absf(p.train_respawn_timer - PlayerTank.TRAIN_CARRIAGE_RESPAWN_TIME) > 0.001:
		fail("炮塔被打掉之后 train_respawn_timer 应为 %.1f, 实际 %.1f"
			% [PlayerTank.TRAIN_CARRIAGE_RESPAWN_TIME, p.train_respawn_timer])
	else:
		ok("炮塔被打掉: 车厢数 2 -> 1, 重生计时器已排上 (%.1fs)" % p.train_respawn_timer)

	# turret.queue_free() 是延迟释放; 火箭的 leader_node 指向 turret, 只有
	# turret 真正失效之后, 火箭自己的 _physics_process 才会检测到 leader
	# 失效并自毁 (train_carriage.gd:93-96)。SceneTree 在 await process_frame
	# 期间会真的跑一次物理帧, 所以这里不需要手动调 rocket._physics_process ——
	# 试过手动调用, 这一帧里 rocket 已经被引擎自己的物理循环连带炸掉了,
	# 再调用会报 "previously freed"。
	await process_frame
	await process_frame

	if p.attached_carriages.size() != 0:
		fail("火箭失去 leader 之后应该也自毁, 车厢数应为 0, 实际 %d —— 连锁没有发生"
			% p.attached_carriages.size())
	else:
		ok("火箭失去 leader 后连带自毁, 车厢数 1 -> 0")

	# 快进重生计时器, 不真的等 12 秒。
	p._process_train_respawn(PlayerTank.TRAIN_CARRIAGE_RESPAWN_TIME + 1.0)

	var new_turret = _find_carriage(p, "turret")
	var new_rocket = _find_carriage(p, "rocket")
	if p.attached_carriages.size() != 2 or new_turret == null or new_rocket == null:
		fail("重生计时器到期后应该补回炮塔+火箭两节, 实际车厢数 %d (turret=%s, rocket=%s)"
			% [p.attached_carriages.size(), str(new_turret != null), str(new_rocket != null)])
	elif new_rocket.leader_node != new_turret:
		fail("补回来的火箭没有跟在新炮塔身后 (leader_node 指向别的节点)")
	else:
		ok("重生计时器到期后两节车厢都补回来了, 火箭正确跟在新炮塔身后")

	_cleanup(rig)


# ------------------------------------------- 2. 只打掉火箭不应该复制出第二个炮塔

func _check_rocket_only_destroy_no_duplicate_turret() -> void:
	print("\n--- 只打掉火箭车厢 -> 补回来的只能是火箭, 炮塔不能被当成缺失的一节 ---")
	var rig := _spawn_train_player(2)
	var p = rig["player"]

	var turret = _find_carriage(p, "turret")
	var rocket = _find_carriage(p, "rocket")
	if turret == null or rocket == null:
		fail("没能同时找到 turret 和 rocket 车厢")
		_cleanup(rig)
		return
	var turret_id: int = turret.get_instance_id()

	rocket.take_damage(999)
	if p.attached_carriages.size() != 1:
		fail("火箭被打掉之后应该剩 1 节 (炮塔), 实际 %d 节" % p.attached_carriages.size())
		_cleanup(rig)
		return
	if p.attached_carriages[0].get_instance_id() != turret_id:
		fail("剩下的那节车厢不是原来那个炮塔实例 —— 炮塔不该受影响")
		_cleanup(rig)
		return
	ok("火箭被打掉后炮塔原地不动, 车厢数 2 -> 1")

	p._process_train_respawn(PlayerTank.TRAIN_CARRIAGE_RESPAWN_TIME + 1.0)

	var turret_count := 0
	var rocket_count := 0
	for c in p.attached_carriages:
		if c.carriage_type == "turret":
			turret_count += 1
		elif c.carriage_type == "rocket":
			rocket_count += 1

	if turret_count != 1 or rocket_count != 1:
		fail("重生后应该是 1 炮塔 + 1 火箭, 实际 %d 炮塔 + %d 火箭 —— 按数量判断缺口的旧逻辑会在这里把幸存的炮塔当 leader 再 setup 出第二节火箭"
			% [turret_count, rocket_count])
	elif _find_carriage(p, "turret").get_instance_id() != turret_id:
		fail("重生流程不该动原来那节还活着的炮塔, 但它的实例变了")
	else:
		ok("重生后车厢阵型正确 (1 炮塔 + 1 火箭), 且原炮塔实例未被重建")

	_cleanup(rig)


# ---------------------------------------------------- 3. tier1 -> tier2 过渡

func _check_tier1_to_tier2_transition() -> void:
	print("\n--- tier1 -> tier2 升级: 车厢数量 1 -> 2, 原炮塔实例保留 ---")
	var rig := _spawn_train_player(1)
	var p = rig["player"]
	var mgr: RPGManager = rig["mgr"]

	if p.attached_carriages.size() != 1 or _find_carriage(p, "turret") == null:
		fail("tier1 出生时应该只有炮塔车厢一节, 实际车厢数 %d" % p.attached_carriages.size())
		_cleanup(rig)
		return
	var turret_id: int = p.attached_carriages[0].get_instance_id()
	ok("tier1 出生: 1 节炮塔车厢")

	mgr.promote_branch_tier(1) # 触发 branch_changed -> player._on_branch_changed -> _sync_train_carriages(2)

	if p.attached_carriages.size() != 2:
		fail("升到 tier2 后车厢数应为 2, 实际 %d" % p.attached_carriages.size())
	elif _find_carriage(p, "turret") == null or _find_carriage(p, "rocket") == null:
		fail("升到 tier2 后应该同时有炮塔和火箭")
	elif _find_carriage(p, "turret").get_instance_id() != turret_id:
		fail("升 tier 不该重建原来那节炮塔车厢, 但实例变了")
	else:
		ok("升到 tier2 后车厢数 1 -> 2, 原炮塔实例保留, 新增火箭车厢")

	_cleanup(rig)


# --------------------------------------- 4. 机车阵亡时车厢各自播放自己的死亡表现

func _check_locomotive_death_signals_each_carriage() -> void:
	print("\n--- 机车阵亡 -> 每节车厢都该收到自己的 destroyed 信号, 不是被静默 queue_free ---")
	var rig := _spawn_train_player(2)
	var p = rig["player"]

	if p.attached_carriages.size() != 2:
		fail("tier2 出生时应该有 2 节车厢, 实际 %d 节" % p.attached_carriages.size())
		_cleanup(rig)
		return

	var death_count := {"n": 0}
	for c in p.attached_carriages:
		c.destroyed.connect(func(_c): death_count["n"] += 1)

	p._die()

	if death_count["n"] != 2:
		fail("机车阵亡后应该有 2 节车厢各自发出 destroyed 信号, 实际 %d —— 是不是又变回直接 queue_free() 了"
			% death_count["n"])
	elif p.attached_carriages.size() != 0:
		fail("机车阵亡后 attached_carriages 应该清空, 实际还剩 %d" % p.attached_carriages.size())
	elif p.train_respawn_timer > 0.0:
		fail("机车正在死亡时不该排一次没有意义的车厢重生 (train_respawn_timer=%.1f)" % p.train_respawn_timer)
	else:
		ok("机车阵亡: 2 节车厢各自收到 destroyed 信号, 没有排多余的重生")

	current_scene = null
	if is_instance_valid(rig["host"]):
		rig["host"].free()
	# p 在 _die() 里已经自己 queue_free() 了, 不需要 _cleanup() 再管一次
