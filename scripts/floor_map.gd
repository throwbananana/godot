class_name FloorMap
extends RefCounted

## 以撒式楼层房间图。取代原来的杀戮尖塔分支节点图 (game_state.gd 里的
## spire_nodes / spire_connections)。
##
## 一个 Act = 一层楼 = 一张房间网格。玩家在 main.tscn 内部走房间, 不换场景;
## 房间之间靠四向门连接, 门开在房间边墙的正中一格。
##
## 和尖塔图的本质区别: 尖塔图是**有向无环图**, 玩家单向向上爬, 走过的节点回
## 不去; 这里是**无向连通图**, 清空过的房间可以随便回头走。所以下面所有可达
## 性判断都是无向 BFS, 不是尖塔那套按 floor 分层的 DP。

# 房间坐标空间。以撒是 13x12; 我们一层的房间数少得多 (8-22), 9x9 足够容纳而
# 不至于让 BFS 把房间摊得太开 —— 网格越大, 同样的房间数走出来越像一条线。
#
# 两个维度都必须是**奇数**: 起始房取 GRID/2 的整数除, 9 -> 4, 在 0..8 里正好
# 居中。用偶数 (原来是 9x8) 的话北边有 4 行而南边只有 3 行, BFS 往北的可扩展
# 空间就比往南多一格 —— 实测 600 层的房间分布 north/south = 1.28, 整层楼肉眼
# 可见地朝上长。东西向当时是 1.06, 因为列数已经是奇数, 正好构成对照。
const GRID_COLS := 9
const GRID_ROWS := 9

const DIR_N := 0
const DIR_E := 1
const DIR_S := 2
const DIR_W := 3

## 索引和 DIR_* 对齐。方向是"房间坐标系"的: +y 向下 (行号增大 = 往南)。
const DIR_VECTORS: Array[Vector2i] = [
	Vector2i(0, -1), # N
	Vector2i(1, 0),  # E
	Vector2i(0, 1),  # S
	Vector2i(-1, 0), # W
]

const DIR_NAMES: Array[String] = ["N", "E", "S", "W"]

static func opposite(d: int) -> int:
	return (d + 2) % 4

## 房间坐标 <-> 字典键。Dictionary 的键用 Vector2i 在运行时没问题, 但
## JSON.stringify 存档时会把它变成 "(3, 4)" 这种没法可靠解析回来的字符串,
## 于是存进去和读出来的键对不上, 表现为"读档后整层楼都是未探索"。统一用
## "col,row" 字符串当键, 存档读档都是同一种东西。
static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

static func parse_key(s: String) -> Vector2i:
	var parts := s.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GRID_COLS and c.y >= 0 and c.y < GRID_ROWS


## 一层楼有多少房间。
##
## 刻意压得又小又平 (8-11), 因为**这个游戏的一个房间不是以撒的一个房间**:
## 每个战斗房是一整场完整的坦克大战遭遇 (12-24 辆车, 同屏上限 4-6, 出怪间隔
## 2-3 秒), 打完一间要一到两分钟, 是以撒那种十几秒一间的四到六倍。
##
## 之前是 8 + (act-1)*2 封顶 22。实测 (60 个种子/幕) 一层的战斗房从第 1 幕的
## 5.0 间涨到第 8 幕的 16.3 间 —— 也就是第 1 幕五分钟、第 8 幕半小时, 而这两层
## 是同一个存档节奏单位。封在 11 之后每层稳定在 5-7 个战斗房 (8-12 分钟),
## 单层长度不再随幕数漂移。
##
## 想要更长的战役, 加的是**幕数** (GameState.max_acts) —— 每幕一个 boss、一个
## 存档点、一次整层重生成, 而不是把单层撑长。
const ROOM_BASE := 8
const ROOM_PER_ACT := 1
const ROOM_MAX := 11

static func target_room_count(act: int) -> int:
	return mini(ROOM_MAX, ROOM_BASE + maxi(0, act - 1) * ROOM_PER_ACT)


## 一层楼保底几个商店。
##
## 原来的尖塔图是"一幕 15 层保底 3 个商店"(game_state.gd 的
## MIN_SHOPS_PER_ACT), 那是按一条 15 战的路线定的。现在一个 act 只有一层楼,
## 战斗房数量和敌人总量都少得多, 沿用 3 会让玩家钱不够花; 用以撒的 1 又会
## 让建造系统 (structure_inventory 只能从商店买) 断粮。折中: 保底 1 个, 房间
## 数够大 (>= SHOP_SECOND_ROOMS) 时给第 2 个。
##
## 注意这个数字**没有经过 tools/probe_balance_report.gd 重新测量** —— 那个
## 探针的 act_econ 模型是建立在尖塔 DAG 上的, 跟着这次改动一起失效了。
## 见 CLAUDE.md "The gold economy has exactly one sink" 一节。
const MIN_SHOPS_PER_FLOOR := 1
const SHOP_SECOND_ROOMS := 13

## 挑战房的四种模式, 和 main.gd::start_game() 读的 GameState.challenge_mode
## 是同一套字符串。按视觉幕换池子, 沿用原 _generate_spire_map() 的分配。
static func _challenge_modes_for(visual_act: int) -> Array:
	match visual_act:
		1: return ["bomb_rain", "night_ops", "vault"]
		2: return ["night_ops", "bomb_rain", "night_bombs"]
		_: return ["night_bombs", "bomb_rain", "night_ops"]


## 生成一层楼。
##
## 返回 {"rooms": {key: room_dict}, "start": key, "boss": key}。
## room_dict 的字段见 _new_room()。
##
## 全程走自带的 RandomNumberGenerator 而不是全局 randi()/randf(): 每日挑战
## 在 main.gd::start_game() 里 seed() 了全局流并依赖它逐帧确定, 在任意时刻
## 从那条流里抽数会让当天所有人的 run 分叉 (和 balance_log.gd::session_id()
## 不用 randi() 是同一个理由)。
static func generate(act: int, seed_value: int, visual_act: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if visual_act <= 0:
		visual_act = ((act - 1) % 3) + 1

	var target := target_room_count(act)
	var start := Vector2i(GRID_COLS / 2, GRID_ROWS / 2)

	# 放置本身可能收不满 target (每个方向只有 50% 概率、且邻居数 >= 2 的格子
	# 直接跳过), 所以外面套一层重试。重试要**换种子偏移**, 否则同一个 rng 状态
	# 会走出同一个结果, 循环到上限还是不够。
	var cells: Dictionary = {}
	for attempt in range(64):
		cells = _place_cells(start, target, rng)
		if cells.size() >= target:
			break
	# 极端情况下 (target 大于网格能塞下的量, 或者运气极差) 就用摆到的那些,
	# 只要连通就是一张能玩的图 —— _place_cells 只从已放置的房间向外扩,
	# 所以结果天然连通。
	if cells.is_empty():
		cells[key(start)] = true

	var rooms: Dictionary = {}
	for k in cells.keys():
		var c := parse_key(str(k))
		rooms[k] = _new_room(c)

	_compute_doors(rooms)
	_compute_depth(rooms, start)
	_assign_types(rooms, start, rng, visual_act)
	var secret_key := _place_secret(rooms, rng)

	var boss_key := ""
	for k in rooms.keys():
		if str(rooms[k]["type"]) == "boss":
			boss_key = str(k)
			break

	return {
		"rooms": rooms,
		"start": key(start),
		"boss": boss_key,
		"secret": secret_key,
	}


static func _new_room(c: Vector2i) -> Dictionary:
	return {
		"col": c.x,
		"row": c.y,
		"type": "normal",
		"depth": 0,
		# doors[d] 为 true 表示 d 方向有门。由 _compute_doors() 从相邻关系
		# 直接算出来, 所以 A 的 doors[d] 和 B 的 doors[opposite(d)] 必然一致
		# —— 不是靠两边各自记一遍再指望它们对得上。
		"doors": [false, false, false, false],
		# secret_doors[d]: 这个方向的门通向秘密房, 要先炸开裂缝墙才算数。
		"secret_doors": [false, false, false, false],
		"cleared": false,
		"visited": false,
		"secret": false,
		"challenge_mode": "",
	}


## 以撒的经典摆放循环: 从起始房 BFS 向外, 每个方向掷一次硬币, 并且拒绝那些
## "已经贴着 2 个以上已放置房间"的格子。后面这条是形状的关键 —— 没有它,
## 房间会糊成一大坨方阵; 有了它, 结果是一棵带少量回环的树, 也就是以撒地图
## 那种细长分叉的样子, 顺便保证了死胡同 (特殊房的落点) 一定存在。
static func _place_cells(start: Vector2i, target: int, rng: RandomNumberGenerator) -> Dictionary:
	var cells: Dictionary = {}
	cells[key(start)] = true
	var queue: Array[Vector2i] = [start]

	# 外层是**轮次**: 一轮把队列走干, 房间还不够就把所有已放置的房间重新灌回
	# 队列, 再刷一轮。单轮 BFS 的 50% 掷骰会砍掉一半分支, 基本摆不满 target。
	#
	# 这里原本写成"灌完就 break", 于是重灌进队列的房间一次都没被处理过, 单轮
	# 走完就返回 —— 达标全靠 generate() 外面那 64 次重试硬碰。那样能出结果,
	# 但每次重试是**整张图重摇**而不是把当前这张补全, 绝大部分采样被丢掉。
	for _round in range(16):
		while not queue.is_empty() and cells.size() < target:
			var cur: Vector2i = queue.pop_front()
			for d in range(4):
				if cells.size() >= target:
					break
				var n: Vector2i = cur + DIR_VECTORS[d]
				if not in_bounds(n):
					continue
				if cells.has(key(n)):
					continue
				if _neighbor_count(cells, n) > 1:
					continue
				if rng.randf() < 0.5:
					continue
				cells[key(n)] = true
				queue.append(n)

		if cells.size() >= target:
			break

		var refill: Array[Vector2i] = []
		for k in cells.keys():
			refill.append(parse_key(str(k)))
		# 洗牌: 不洗的话每轮都按 Dictionary 的键序从同一头开始长, 图会偏向一侧。
		for i in range(refill.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := refill[i]
			refill[i] = refill[j]
			refill[j] = tmp
		queue.append_array(refill)

	return cells


static func _neighbor_count(cells: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in range(4):
		if cells.has(key(c + DIR_VECTORS[d])):
			n += 1
	return n


## 门 = 两个相邻格子都是房间。从相邻关系算而不是在摆放时记录, 是为了对称性
## 由构造保证: 不存在"A 有门 B 没门"的半扇门。
static func _compute_doors(rooms: Dictionary) -> void:
	for k in rooms.keys():
		var c := parse_key(str(k))
		var doors: Array = rooms[k]["doors"]
		for d in range(4):
			doors[d] = rooms.has(key(c + DIR_VECTORS[d]))


## 无向 BFS 距离。用来选 boss 房 (最远的死胡同) 和排特殊房的优先级。
static func _compute_depth(rooms: Dictionary, start: Vector2i) -> void:
	for k in rooms.keys():
		rooms[k]["depth"] = -1
	var start_key := key(start)
	if not rooms.has(start_key):
		return
	rooms[start_key]["depth"] = 0
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		var cur_depth: int = int(rooms[key(cur)]["depth"])
		for d in range(4):
			var n := cur + DIR_VECTORS[d]
			var nk := key(n)
			if rooms.has(nk) and int(rooms[nk]["depth"]) < 0:
				rooms[nk]["depth"] = cur_depth + 1
				queue.append(n)


## 死胡同 = 只有一扇门的房间, 起始房除外。特殊房只放死胡同, 理由和以撒一样:
## 放在通路上的话玩家会顺路白捡, 放在死胡同就得**多走一趟**, 于是"要不要为
## 了商店绕这一段"变成一个决策。
static func _dead_ends(rooms: Dictionary, start_key: String) -> Array:
	var result: Array = []
	for k in rooms.keys():
		if str(k) == start_key:
			continue
		var doors: Array = rooms[k]["doors"]
		var n := 0
		for d in range(4):
			if doors[d]:
				n += 1
		if n == 1:
			result.append(str(k))
	# 深的排前面: boss 要最远的那个, 其余特殊房也倾向于远一点。
	result.sort_custom(func(a, b): return int(rooms[a]["depth"]) > int(rooms[b]["depth"]))
	return result


static func _assign_types(rooms: Dictionary, start: Vector2i, rng: RandomNumberGenerator, visual_act: int) -> void:
	var start_key := key(start)
	if rooms.has(start_key):
		rooms[start_key]["type"] = "start"
		rooms[start_key]["cleared"] = true
		rooms[start_key]["visited"] = true

	var ends := _dead_ends(rooms, start_key)

	# 1. Boss —— 必须有, 而且必须是最远的那个死胡同。没有死胡同 (整层是一个
	#    环) 时退而求其次取深度最大的普通房, 否则这一层没有出口, 玩家会卡死。
	var boss_key := ""
	if not ends.is_empty():
		boss_key = str(ends.pop_front())
	else:
		var best_depth := -1
		for k in rooms.keys():
			if str(k) == start_key:
				continue
			if int(rooms[k]["depth"]) > best_depth:
				best_depth = int(rooms[k]["depth"])
				boss_key = str(k)
	if boss_key != "":
		rooms[boss_key]["type"] = "boss"

	# 2. 商店 —— 保底数量见 MIN_SHOPS_PER_FLOOR。商店取**最浅**的死胡同:
	#    建材和强化早点拿到才有的用, 全堆在 boss 门口等于没给 (这条是从原来
	#    _ensure_shop_coverage() 的 30%/55%/80% 插点逻辑继承下来的结论)。
	var want_shops := MIN_SHOPS_PER_FLOOR
	if rooms.size() >= SHOP_SECOND_ROOMS:
		want_shops += 1
	var placed_shops := 0
	for _i in range(want_shops):
		if ends.is_empty():
			break
		var shop_key := str(ends.pop_back()) # 尾部 = 最浅
		rooms[shop_key]["type"] = "shop"
		placed_shops += 1

	# 死胡同不够分的时候 (整层几乎是一条环, 实测约 400 层里出 1 次), 上面那个
	# 循环会一个商店都放不下。商店是 structure_inventory 的**唯一**来源, 一层
	# 没有商店 = 这一层的建造系统断粮, 而玩家无从分辨这是运气还是功能坏了。
	#
	# 所以退一步: 从通路上的普通房里挑最浅的那间改成商店。放在通路上不如放在
	# 死胡同 (少了"要不要绕这一趟"的取舍), 但那是风味问题, 没商店是功能问题。
	if placed_shops < MIN_SHOPS_PER_FLOOR:
		var fallback: Array = []
		for k in rooms.keys():
			if str(k) == start_key:
				continue
			if str(rooms[k]["type"]) != "normal":
				continue
			fallback.append(str(k))
		fallback.sort_custom(func(a, b): return int(rooms[a]["depth"]) < int(rooms[b]["depth"]))
		while placed_shops < MIN_SHOPS_PER_FLOOR and not fallback.is_empty():
			rooms[str(fallback.pop_front())]["type"] = "shop"
			placed_shops += 1

	# 3. 宝物房 —— 以撒的 Item Room, 一层一个, 免费拿一次强化。
	if not ends.is_empty():
		rooms[str(ends.pop_front())]["type"] = "treasure"

	# 4. 剩下的死胡同分给挑战房 / 事件房 / 休息房。挑战房带 challenge_mode。
	var extras := ["challenge", "event", "rest"]
	var extra_idx := 0
	while not ends.is_empty() and extra_idx < extras.size():
		var k := str(ends.pop_front())
		var t: String = extras[extra_idx]
		rooms[k]["type"] = t
		if t == "challenge":
			var modes := _challenge_modes_for(visual_act)
			rooms[k]["challenge_mode"] = str(modes[rng.randi_range(0, modes.size() - 1)])
		extra_idx += 1

	# 剩下的一切 (通路上的房间 + 用不完的死胡同) 都是普通战斗房, _new_room()
	# 的默认值已经是 "normal", 不用再写一遍。


## 秘密房: 挑一个**空格**, 它周围贴着的已有房间越多越好 (以撒也是这么选的 ——
## 藏在地图最"实"的地方, 玩家才需要靠推理而不是穷举去找)。
##
## 返回它的 key, 没放成返回 ""。
static func _place_secret(rooms: Dictionary, rng: RandomNumberGenerator) -> String:
	var candidates: Array = []
	var best_n := 0

	for col in range(GRID_COLS):
		for row in range(GRID_ROWS):
			var c := Vector2i(col, row)
			if rooms.has(key(c)):
				continue
			var neighbors: Array = []
			for d in range(4):
				var nk := key(c + DIR_VECTORS[d])
				if rooms.has(nk):
					neighbors.append(nk)
			if neighbors.is_empty():
				continue
			# 不贴着 boss 房: 秘密房的意义是绕过战斗拿资源, 贴 boss 等于给了
			# 一条"不打 boss 直接摸到终点旁边"的近路。
			var touches_boss := false
			for nk in neighbors:
				if str(rooms[nk]["type"]) == "boss":
					touches_boss = true
					break
			if touches_boss:
				continue
			if neighbors.size() > best_n:
				best_n = neighbors.size()
				candidates = [c]
			elif neighbors.size() == best_n:
				candidates.append(c)

	if candidates.is_empty() or best_n < 2:
		return ""

	var pick: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	var pk := key(pick)
	var room := _new_room(pick)
	room["type"] = "secret"
	room["secret"] = true
	rooms[pk] = room

	# 秘密房的门要**双向**标成 secret: 玩家从任意一侧看到的都该是一堵裂缝墙,
	# 而不是"从里面出来时是普通门"。同时补上双方的 doors, 因为 _compute_doors()
	# 在秘密房存在之前就跑完了。
	for d in range(4):
		var nk := key(pick + DIR_VECTORS[d])
		if not rooms.has(nk):
			continue
		room["doors"][d] = true
		room["secret_doors"][d] = true
		rooms[nk]["doors"][opposite(d)] = true
		rooms[nk]["secret_doors"][opposite(d)] = true

	# 深度: 秘密房不参与主路径的难度爬升, 给它挂上邻居里最浅的那个深度。
	var min_depth := 9999
	for d in range(4):
		var nk := key(pick + DIR_VECTORS[d])
		if rooms.has(nk) and not bool(rooms[nk]["secret"]):
			min_depth = mini(min_depth, int(rooms[nk]["depth"]))
	room["depth"] = 0 if min_depth == 9999 else min_depth

	return pk


# ---------------------------------------------------------------- 查询辅助
#
# 下面这些是给 main.gd / minimap.gd / 测试共用的只读查询。放在这里而不是各自
# 写一份, 是因为"哪扇门能走"这种判断一旦有两份实现就一定会分叉 (门画开着但
# 走不过去, 或者反过来)。

## 这扇门现在能不能走。房间没清空时所有门都锁着 (以撒的门闩), 秘密门要先被
## 炸开 (opened_secret_doors 里记着已经打通的)。
static func is_door_passable(room: Dictionary, d: int, opened_secret: bool) -> bool:
	if not bool(room["doors"][d]):
		return false
	if bool(room["secret_doors"][d]) and not opened_secret:
		return false
	return bool(room["cleared"])


## 这个房间要不要打。start 是空房, 已清空的不再刷怪; 其余都要。
static func is_combat_room(room: Dictionary) -> bool:
	var t := str(room["type"])
	if t in ["start", "shop", "treasure", "event", "rest", "secret"]:
		return false
	return not bool(room["cleared"])


## 小地图和门牌用的图标名, 对应 assets/sprites/map/node_*.png。
## 没有专属图标的房型退回 node_battle —— 缺图标不该让小地图整块画不出来。
static func icon_for_type(t: String) -> String:
	match t:
		"boss": return "node_boss"
		"shop": return "node_shop"
		"event": return "node_event"
		"rest": return "node_rest"
		"challenge": return "node_challenge"
		"treasure": return "node_elite"
		_: return "node_battle"
