extends SceneTree

## train 分支的跟随车厢不能把队伍自己的道具白吃掉。
##
## 车厢在 _ready() 里 add_to_group("player") —— 它**必须**在这个组里, 否则
## 敌方子弹和伤害判定不认它。副作用是所有只判 is_in_group("player") 的拾取物
## 都会被车厢触发。
##
## 大多数收集物无所谓 (金币/钻石/补给/宝箱/钥匙都是记到 current_scene 上的
## 团队账户, 谁碰到都一样), 但有两处不是:
##   1. power_up.gd 是对 body 本身调 apply_powerup()。车厢没这个方法, 于是
##      道具被 queue_free、音效照播、效果为零 —— 车队越长白吃得越多, 而且
##      完全无声, 不报错。
##   2. gold_coin.gd / diamond_gem.gd 要读 body.player_id 才能算
##      magnetic_salvage 的加成, 车厢没这个字段, 加成静默丢失。
##
## 两处都改成先经 TrainFollowHelper.resolve_train_owner() 沿 leader_node
## 解析回车头那辆坦克。
##
## 这里用鸭子类型 stub 而不是启动 main.tscn (同 tools/_train_stub.gd 的思路):
## 被测的只是"从某一节解析回车头"这一件事, 不需要贴图、物理和地图。

const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


## 车头替身: 有 apply_powerup 和 player_id, 记录吃到了什么。
class TankStub extends Node2D:
	var player_id: int = 1
	var got: Array = []
	func apply_powerup(t) -> void:
		got.append(t)


## 车厢替身: 只有 leader_node, 没有 apply_powerup / player_id ——
## 和真的 train_carriage.gd 一致。
class CarriageStub extends Node2D:
	var leader_node: Node2D = null


func _init() -> void:
	print("==================================================")
	print(">>> TRAIN CARRIAGE PICKUP TEST <<<")
	print("==================================================")
	_check_resolve_chain()
	_check_non_train_bodies()
	_check_cycle_guard()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL TRAIN PICKUP CHECKS PASSED! <<<")
		quit(0)


func _check_resolve_chain() -> void:
	print("\n--- 车队任意一节都要解析回车头 ---")
	var tank := TankStub.new()
	root.add_child(tank)

	var chain: Array = [tank]
	for i in range(3):
		var c := CarriageStub.new()
		c.leader_node = chain[chain.size() - 1]
		root.add_child(c)
		chain.append(c)

	for i in range(chain.size()):
		var got = TrainFollowHelper.resolve_train_owner(chain[i])
		if got == tank:
			ok("第 %d 节 -> 车头" % i)
		else:
			fail("第 %d 节解析到了 %s, 应为车头 —— 道具会被这一节白吃掉"
				% [i, str(got)])

	# 车头自己也要能解析 (它本身就有 apply_powerup)
	var last = chain[chain.size() - 1]
	var owner_tank = TrainFollowHelper.resolve_train_owner(last)
	if owner_tank and owner_tank.has_method("apply_powerup"):
		owner_tank.apply_powerup("STAR")
		if tank.got == ["STAR"]:
			ok("经最后一节拾取, 效果落到车头身上")
		else:
			fail("车头没有收到效果: %s" % str(tank.got))

	for n in chain:
		n.free()


func _check_non_train_bodies() -> void:
	print("\n--- 不属于车队的 body 必须返回 null (道具留在原地) ---")
	var stray := Node2D.new()
	root.add_child(stray)
	var got = TrainFollowHelper.resolve_train_owner(stray)
	if got == null:
		ok("既无 apply_powerup 也无 leader_node 的 body -> null")
	else:
		fail("返回了 %s, 应为 null" % str(got))
	stray.free()

	if TrainFollowHelper.resolve_train_owner(null) == null:
		ok("null 输入 -> null")
	else:
		fail("null 输入没有返回 null")

	# leader_node 悬空 (车头已经被 free) 也不能炸
	var orphan := CarriageStub.new()
	root.add_child(orphan)
	orphan.leader_node = null
	if TrainFollowHelper.resolve_train_owner(orphan) == null:
		ok("leader_node 为空的车厢 -> null, 不崩")
	else:
		fail("leader_node 为空时没有返回 null")
	orphan.free()


func _check_cycle_guard() -> void:
	print("\n--- leader_node 成环时不能死循环 ---")
	var a := CarriageStub.new()
	var b := CarriageStub.new()
	root.add_child(a)
	root.add_child(b)
	a.leader_node = b
	b.leader_node = a
	var got = TrainFollowHelper.resolve_train_owner(a)
	if got == null:
		ok("环形 leader 链在上限内退出并返回 null")
	else:
		fail("环形链返回了 %s" % str(got))
	a.free()
	b.free()
