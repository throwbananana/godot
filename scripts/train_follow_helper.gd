class_name TrainFollowHelper
extends RefCounted

## Snake-style path following: a leader (player/enemy tank, or another
## TrainCarriage further up the chain) records its exact position+rotation
## every physics frame; a follower samples that recorded path at a fixed
## distance behind the leader's current position. Because the leader only
## ever moves in the 4 cardinal directions (see player.gd's input_vec /
## enemy.gd's facing_direction, both if/elif chains that pick exactly one
## axis), the follower's path is a delayed copy of an already axis-aligned
## path -- it can't cut corners diagonally the way lerp-toward-a-point does.

const MAX_HISTORY_DIST: float = 400.0 # generous headroom for a multi-carriage chain

static func record_history(positions: Array[Vector2], rotations: Array[float], pos: Vector2, rot: float) -> void:
	positions.push_back(pos)
	rotations.push_back(rot)

	var total_dist = 0.0
	var trim_to = 0
	for i in range(positions.size() - 1, 0, -1):
		total_dist += positions[i].distance_to(positions[i - 1])
		if total_dist > MAX_HISTORY_DIST:
			trim_to = i
			break
	for _i in range(trim_to):
		positions.pop_front()
		rotations.pop_front()

## 重建一条笔直的合成尾迹, 从 pos 沿 rot 的反方向向后铺 length 距离。
##
## 传送用得着它: 历史路径是"位置采样序列", 而 sample_at_distance 是沿着相邻采样
## 之间的线段累计距离的。瞬移会在序列里留下一条超长线段 (入口 -> 出口), 跟随者
## 累距离时第一条就撞上它, 于是被插值到入口和出口之间的连线上 —— 穿墙横跨半张
## 地图。清空历史也不行: 空数组会让 sample_at_distance 返回 {}, 跟随者那一帧
## 完全不动, 下一帧历史只有一个点又会精确叠在 leader 身上。
## 直接铺一条合成尾迹, 两个问题都没有 —— 整列车在出口处以正确队形直接成形。
const RESEED_STEP: float = 6.0

static func reseed_straight_tail(positions: Array[Vector2], rotations: Array[float],
		pos: Vector2, rot: float, length: float) -> void:
	positions.clear()
	rotations.clear()
	# 最旧的在前, 最新的在后 —— 和 record_history 的 push_back 顺序一致,
	# sample_at_distance 是从末尾往回走的。
	var backward = -Vector2.UP.rotated(rot)
	var steps = int(ceil(maxf(length, RESEED_STEP) / RESEED_STEP))
	for i in range(steps, -1, -1):
		positions.push_back(pos + backward * (RESEED_STEP * float(i)))
		rotations.push_back(rot)


## 找出直接或间接跟随 leader 的全部车厢, 按队列顺序返回。
##
## 不走 player.attached_carriages / enemy.attached_wagons: 那是两个不同的成员名,
## 而且只有第一层。这里顺着每节车厢自己的 leader_node 反查, 玩家链和敌方链用
## 同一套代码, 也拿得到第二节以后的车厢。
## 用鸭子类型而不是 `is TrainCarriage`: train_carriage.gd 已经 preload 了本文件,
## 反向按类名引用会形成循环依赖。
static func collect_followers(leader: Node) -> Array:
	var out: Array = []
	var parent = leader.get_parent()
	if parent == null:
		return out
	var current: Node = leader
	while true:
		var next: Node = null
		for child in parent.get_children():
			if child == leader or out.has(child):
				continue
			if "leader_node" in child and child.leader_node == current:
				next = child
				break
		if next == null:
			break
		out.append(next)
		current = next
	return out


## 把整列车一起搬到 leader 的新位置。传送后必须调用, 否则队列会被扯断。
##
## 只清 leader 自己的历史是不够的 —— 那样第一节车厢确实能跟上, 但第二节跟的是
## 第一节, 而第一节的历史里仍然留着那条跨图线段, 于是问题只是从第一节转移到了
## 第二节。这里对链上每一节都重铺尾迹, 并按 follow_distance 依次摆好位置。
static func teleport_train_chain(leader: Node) -> void:
	if not ("history_positions" in leader and "history_rotations" in leader):
		return

	var rot: float = leader.rotation
	var backward = -Vector2.UP.rotated(rot)
	var followers = collect_followers(leader)

	# leader 的尾迹要够第一节车厢采样, 留一点余量
	var first_gap: float = 38.0
	if followers.size() > 0 and "follow_distance" in followers[0]:
		first_gap = followers[0].follow_distance
	reseed_straight_tail(leader.history_positions, leader.history_rotations,
		leader.global_position, rot, first_gap + RESEED_STEP * 4.0)

	var prev_pos: Vector2 = leader.global_position
	for i in range(followers.size()):
		var f = followers[i]
		var gap: float = f.follow_distance if "follow_distance" in f else 38.0
		var pos: Vector2 = prev_pos + backward * gap
		f.global_position = pos
		f.rotation = rot
		# 下一节要采样这一节的历史, 所以尾迹长度按*下一节*的 follow_distance 算
		var next_gap: float = 38.0
		if i + 1 < followers.size() and "follow_distance" in followers[i + 1]:
			next_gap = followers[i + 1].follow_distance
		if "history_positions" in f and "history_rotations" in f:
			reseed_straight_tail(f.history_positions, f.history_rotations,
				pos, rot, next_gap + RESEED_STEP * 4.0)
		prev_pos = pos


static func sample_at_distance(positions: Array[Vector2], rotations: Array[float], follow_distance: float) -> Dictionary:
	if positions.is_empty():
		return {}
	var accum = 0.0
	for i in range(positions.size() - 1, 0, -1):
		var seg = positions[i].distance_to(positions[i - 1])
		if accum + seg >= follow_distance:
			var t = (follow_distance - accum) / seg if seg > 0.001 else 0.0
			return {
				"position": positions[i].lerp(positions[i - 1], t),
				"rotation": lerp_angle(rotations[i], rotations[i - 1], t),
			}
		accum += seg
	return {"position": positions[0], "rotation": rotations[0]}


## 把一个"车队的某一节"解析回真正驾驶它的那辆坦克。
##
## train 分支的玩家会挂上 train_carriage.gd 的跟随车厢, 而车厢在 _ready()
## 里 add_to_group("player") —— 它得在"player"组里, 敌方子弹和伤害判定才认
## 得它。副作用是**所有只判 is_in_group("player") 的拾取物都会被车厢触发**。
##
## 大多数收集物无所谓: 金币/钻石/补给/宝箱/钥匙都是把奖励记到
## get_tree().current_scene 上的团队账户, 谁碰到都一样。但有两处不是:
##   * power_up.gd 是对 body 本身调 apply_powerup()。车厢没有这个方法,
##     于是道具被销毁、音效照播、效果为零 —— 车队越长, 被白吃的概率越大。
##   * gold_coin.gd / diamond_gem.gd 要读 body.player_id 才能算
##     magnetic_salvage 的加成; 车厢没有这个字段, 加成静默丢失。
##
## 沿 leader_node 往前走即可 —— 车厢的 leader 可能是上一节车厢, 所以要一直
## 走到链头。返回 null 表示这个 body 压根不是车队的一部分 (调用方原样处理)。
static func resolve_train_owner(body: Node) -> Node:
	if body == null or not is_instance_valid(body):
		return null
	var cur: Node = body
	# 链长有硬上限 (player.gd::_sync_train_carriages 只挂几节), 这里再给一个
	# 保险计数, 免得万一有人把 leader_node 接成环就死循环。
	for _i in range(16):
		if cur.has_method("apply_powerup"):
			return cur
		if not ("leader_node" in cur):
			return null
		var nxt = cur.leader_node
		if nxt == null or not is_instance_valid(nxt):
			return null
		cur = nxt
	return null
