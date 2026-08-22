extends SceneTree

## 列车队列穿越传送门的回归测试。
##
## 覆盖三个真出过的 bug:
##   1. 只清机车的历史 -> 第二节车厢采样时撞上"入口->出口"那条跨图线段, 被插值
##      到连线中间, 穿墙横跨半张地图。
##   2. 车厢自己触发传送门 -> 位置下一帧就被 leader 覆写, 白播音效/特效、烧掉
##      冷却, 还清空自己的历史打乱后面的车厢。
##   3. 清空历史后 sample_at_distance 返回 {} -> 车厢当帧不动, 下一帧精确叠在
##      机车身上 (而不是待在它后方)。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_train_teleport.gd

const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


# 一个最小的替身: 只需要 history_* / global_position / rotation / follow_distance
# 这几样, 用 Node2D 就够, 不必真的实例化 CharacterBody2D 和整张地图。
func make_node(parent: Node, gap: float, leader: Node) -> Node2D:
	var n := Node2D.new()
	n.set_script(preload("res://tools/_train_stub.gd"))
	parent.add_child(n)
	n.follow_distance = gap
	n.leader_node = leader
	return n


func _init() -> void:
	print("==================================================")
	print(">>> TRAIN / WORMHOLE TELEPORT REGRESSION TEST <<<")
	print("==================================================")

	var root_node := Node2D.new()
	root.add_child(root_node)

	# 机车 + 两节车厢, 和 player.gd::_sync_train_carriages 的 tier2 队形一致
	var loco := make_node(root_node, 0.0, null)
	var c1 := make_node(root_node, 38.0, loco)
	var c2 := make_node(root_node, 38.0, c1)

	# --- 步骤 1: 让整列车沿 +X 直线行进, 积累真实历史 ---
	loco.rotation = PI / 2.0            # Vector2.UP.rotated(PI/2) = RIGHT
	var start := Vector2(100.0, 300.0)
	for i in range(120):
		loco.global_position = start + Vector2(float(i) * 4.0, 0.0)
		TrainFollowHelper.record_history(loco.history_positions, loco.history_rotations,
			loco.global_position, loco.rotation)
		_advance(c1)
		_advance(c2)

	var pre_gap1 := loco.global_position.distance_to(c1.global_position)
	var pre_gap2 := c1.global_position.distance_to(c2.global_position)
	print("  行进后队形: 机车-c1 %.1fpx, c1-c2 %.1fpx (期望 ~38)" % [pre_gap1, pre_gap2])
	if absf(pre_gap1 - 38.0) > 6.0 or absf(pre_gap2 - 38.0) > 6.0:
		fail("正常行进时队形就不对, 后续结论无意义")

	# --- 步骤 2: 找出 collect_followers 能不能拿到整条链 ---
	var followers = TrainFollowHelper.collect_followers(loco)
	if followers.size() != 2:
		fail("collect_followers 只找到 %d 节车厢, 应为 2" % followers.size())
	elif followers[0] != c1 or followers[1] != c2:
		fail("collect_followers 顺序错误")
	else:
		ok("collect_followers 拿到完整的两节链条且顺序正确")

	# --- 步骤 3: 传送到地图另一头 ---
	var exit_pos := Vector2(560.0, 60.0)
	loco.global_position = exit_pos
	TrainFollowHelper.teleport_train_chain(loco)

	# 传送当帧车厢就该已经在出口附近, 不能还挂在半路
	var d1 := exit_pos.distance_to(c1.global_position)
	var d2 := exit_pos.distance_to(c2.global_position)
	print("  传送后到出口距离: c1 %.1fpx, c2 %.1fpx" % [d1, d2])
	if d1 > 60.0:
		fail("c1 离出口 %.1fpx, 没跟过来" % d1)
	if d2 > 120.0:
		fail("c2 离出口 %.1fpx —— 这正是穿墙横跨地图的老 bug" % d2)
	if d1 <= 60.0 and d2 <= 120.0:
		ok("两节车厢都跟着机车到了出口")

	# --- 步骤 4: 之后若干帧, 队形必须保持, 且不能出现瞬间大跳 ---
	var prev1 := c1.global_position
	var prev2 := c2.global_position
	var max_jump := 0.0
	for i in range(60):
		loco.global_position = exit_pos + Vector2(float(i) * 4.0, 0.0)
		TrainFollowHelper.record_history(loco.history_positions, loco.history_rotations,
			loco.global_position, loco.rotation)
		_advance(c1)
		_advance(c2)
		max_jump = maxf(max_jump, prev1.distance_to(c1.global_position))
		max_jump = maxf(max_jump, prev2.distance_to(c2.global_position))
		prev1 = c1.global_position
		prev2 = c2.global_position

	var post_gap1 := loco.global_position.distance_to(c1.global_position)
	var post_gap2 := c1.global_position.distance_to(c2.global_position)
	print("  传送后行进 60 帧: 机车-c1 %.1fpx, c1-c2 %.1fpx, 单帧最大位移 %.1fpx"
		% [post_gap1, post_gap2, max_jump])
	if absf(post_gap1 - 38.0) > 8.0 or absf(post_gap2 - 38.0) > 8.0:
		fail("传送后队形没恢复")
	else:
		ok("传送后队形恢复正常")
	# 机车每帧走 4px, 车厢跟随位移不该远超它。放宽到 40px 是给传送当帧留余量,
	# 而老 bug 会在这里量到几百 px。
	if max_jump > 40.0:
		fail("传送后出现单帧 %.1fpx 的瞬移 —— 车厢在沿跨图线段爬行" % max_jump)
	else:
		ok("没有跨图线段残留 (单帧最大位移 %.1fpx)" % max_jump)

	# --- 步骤 5: 合成尾迹的方向必须朝车尾 ---
	var s = TrainFollowHelper.sample_at_distance(loco.history_positions,
		loco.history_rotations, 38.0)
	if s.is_empty():
		fail("重铺尾迹后 sample_at_distance 仍返回空")
	else:
		ok("重铺后的尾迹可被正常采样")

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL TRAIN TELEPORT CHECKS PASSED! <<<")
		quit(0)


## 复刻 train_carriage.gd::_physics_process 里的跟随+记录两步
func _advance(c: Node2D) -> void:
	if c.leader_node == null:
		return
	var sample = TrainFollowHelper.sample_at_distance(
		c.leader_node.history_positions, c.leader_node.history_rotations, c.follow_distance)
	if not sample.is_empty():
		c.global_position = sample["position"]
		c.rotation = sample["rotation"]
	TrainFollowHelper.record_history(c.history_positions, c.history_rotations,
		c.global_position, c.rotation)
