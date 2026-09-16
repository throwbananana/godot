extends SceneTree

# 网络快照短暂停顿的回归测试。
#
# 普通傀儡允许短时间 dead-reckoning 来盖住 30Hz 快照之间的空隙，但不能拿最后一份
# velocity 无限向未来外推；本机预测坦克在权威快照过期后也不能继续被旧目标往回拉。
# 这两条都是纯插值规则，不需要开 socket。

const NetSession = preload("res://scripts/net_session.gd")
const NetPuppet = preload("res://scripts/net_puppet.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run_tests")


func _fail(msg: String) -> void:
	_failed = true
	print("  [FAIL] %s" % msg)


func _ok(msg: String) -> void:
	print("  [PASS] %s" % msg)


func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING NET PUPPET STALL TEST <<<")
	print("==================================================")

	_test_extrapolation_is_bounded()
	_test_fresh_snapshot_rearms_prediction()
	_test_stale_authority_does_not_pull_local_player()

	if _failed:
		print("\n>>> NET PUPPET STALL: 有检查未通过 <<<")
	else:
		print("\n>>> ALL NET PUPPET STALL CHECKS PASSED! <<<")
	quit(1 if _failed else 0)


func _new_puppet(kind: int) -> Node2D:
	var n := Node2D.new()
	root.add_child(n)
	NetPuppet.make_puppet(n, kind)
	return n


func _test_extrapolation_is_bounded() -> void:
	print("\n[STEP] 连续丢快照时，普通傀儡不能无限外推...")
	var n := _new_puppet(NetSession.Kind.BULLET)
	NetPuppet.set_target(n, Vector2.ZERO, 0.0, Vector2(100.0, 0.0))

	# 1 秒都没有新包。100px/s 如果无限外推会到 x=100；现在最多只应使用
	# MAX_EXTRAPOLATION_TIME=0.20s，也就是目标点 x≈20。
	for _i in range(20):
		NetPuppet.update(n, 0.05)
	var tpos: Vector2 = n.get_meta("net_tpos", Vector2.ZERO)
	var expected := 100.0 * NetPuppet.MAX_EXTRAPOLATION_TIME
	if absf(tpos.x - expected) > 0.01:
		_fail("快照停 1 秒后目标点应封顶在 x=%.2f，实际 %.2f（可能仍在无限外推）" % [expected, tpos.x])
	else:
		_ok("外推在 %.0fms 后封顶，目标点停在 x=%.2f。" % [NetPuppet.MAX_EXTRAPOLATION_TIME * 1000.0, tpos.x])
	n.queue_free()


func _test_fresh_snapshot_rearms_prediction() -> void:
	print("\n[STEP] 新快照到达后必须立刻重新允许短期外推...")
	var n := _new_puppet(NetSession.Kind.ENEMY)
	NetPuppet.set_target(n, Vector2.ZERO, 0.0, Vector2(100.0, 0.0))
	for _i in range(10):
		NetPuppet.update(n, 0.05)

	# 新的权威位置落在 x=50；set_target 应把 age 清零，下一 50ms 应推进到 55。
	NetPuppet.set_target(n, Vector2(50.0, 0.0), 0.0, Vector2(100.0, 0.0))
	NetPuppet.update(n, 0.05)
	var tpos: Vector2 = n.get_meta("net_tpos", Vector2.ZERO)
	if absf(tpos.x - 55.0) > 0.01:
		_fail("新快照后目标应从 50 推到 55，实际 %.2f；snapshot age 可能没有重置" % tpos.x)
	else:
		_ok("新快照成功重新激活 dead-reckoning。")
	n.queue_free()


func _test_stale_authority_does_not_pull_local_player() -> void:
	print("\n[STEP] 本机预测坦克不能被过期权威目标往回拉...")
	var n := _new_puppet(NetSession.Kind.PLAYER)
	NetPuppet.make_predicted(n)
	NetPuppet.set_target(n, Vector2.ZERO, 0.0, Vector2(100.0, 0.0))

	# 先把权威快照年龄推进到上限。
	for _i in range(4):
		NetPuppet.reconcile(n, 0.05)

	# 模拟玩家在断流期间继续按键，本地预测已经走到更前方。旧实现会继续拿
	# 冻结/过期目标把它往回拉；现在 stale 后 reconcile 应放手等待新快照。
	n.position = Vector2(200.0, 0.0)
	NetPuppet.reconcile(n, 0.05)
	if n.position.distance_to(Vector2(200.0, 0.0)) > 0.001:
		_fail("过期快照仍在拉扯本机预测位置：期望 x=200，实际 %.2f" % n.position.x)
	else:
		_ok("权威快照过期后，本机预测保持输入响应，不被旧目标回拉。")
	n.queue_free()
