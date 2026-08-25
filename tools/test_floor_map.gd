extends SceneTree

## FloorMap 楼层生成器的结构性验收。
##
## 这里断言的都是"这张图能不能玩"的硬性质, 不是具体形状 —— 形状是随机的,
## 断言具体形状等于把随机数写死。跨多个种子扫, 因为单个种子过了只能说明那个
## 种子过了: 房间摆放本身是掷硬币, 一次采样看不出"某类种子会生成断路的图"。

const FloorMap = preload("res://scripts/floor_map.gd")

const SEEDS := 200

var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func _run() -> void:
	print("==================================================")
	print(">>> RUNNING FLOOR MAP GENERATION TESTS <<<")
	print("==================================================")

	_test_connectivity_and_counts()
	_test_doors_symmetric()
	_test_boss_is_farthest_dead_end()
	_test_special_rooms_unique_and_placed()
	_test_secret_room_rules()
	_test_determinism()

	if failures > 0:
		print("\n>>> FLOOR MAP: %d FAILURE(S) <<<" % failures)
		quit(1)
	print("\n>>> ALL FLOOR MAP CHECKS PASSED! <<<")
	quit(0)


## 无向 BFS: 从 start 出发能不能走到每一个房间。秘密房是故意要炸墙才进的,
## 但它在图上仍然连通, 所以一并要求可达。
func _reachable(rooms: Dictionary, start_key: String) -> Dictionary:
	var seen := {start_key: true}
	var queue: Array = [start_key]
	while not queue.is_empty():
		var k: String = queue.pop_front()
		var c := FloorMap.parse_key(k)
		var doors: Array = rooms[k]["doors"]
		for d in range(4):
			if not bool(doors[d]):
				continue
			var nk := FloorMap.key(c + FloorMap.DIR_VECTORS[d])
			if rooms.has(nk) and not seen.has(nk):
				seen[nk] = true
				queue.append(nk)
	return seen


func _test_connectivity_and_counts() -> void:
	print("\n[STEP 1] 每个种子生成的楼层都必须全连通, 且房间数达标...")
	var short_floors := 0
	for s in range(SEEDS):
		var act := (s % 8) + 1
		var data := FloorMap.generate(act, 1000 + s)
		var rooms: Dictionary = data["rooms"]
		var start_key: String = data["start"]

		if not rooms.has(start_key):
			_fail("seed %d: 起始房 %s 不在 rooms 里" % [s, start_key])
			continue

		var seen := _reachable(rooms, start_key)
		if seen.size() != rooms.size():
			_fail("seed %d (act %d): 有 %d/%d 个房间从起始房走不到" % [s, act, rooms.size() - seen.size(), rooms.size()])

		# 房间数允许略低于 target (摆放是掷硬币, 外层重试 64 次仍可能差一两间),
		# 但不该差太多 —— 差太多说明摆放循环本身有问题。
		var target := FloorMap.target_room_count(act)
		if rooms.size() < target - 1:
			short_floors += 1
		if rooms.size() < target * 0.6:
			_fail("seed %d (act %d): 只摆出 %d 间, target %d" % [s, act, rooms.size(), target])

	# 秘密房是额外加的, 所以正常情况下房间数应当 >= target。允许极少数偏低。
	if short_floors > SEEDS * 0.05:
		_fail("有 %d/%d 个种子房间数低于 target-1, 摆放循环收敛太差" % [short_floors, SEEDS])
	print("  [PASS] %d 个种子全部连通, 房间数收敛正常 (欠额 %d 个)" % [SEEDS, short_floors])


func _test_doors_symmetric() -> void:
	print("\n[STEP 2] 门必须双向一致 (不存在半扇门)...")
	for s in range(SEEDS):
		var data := FloorMap.generate((s % 8) + 1, 5000 + s)
		var rooms: Dictionary = data["rooms"]
		for k in rooms.keys():
			var c := FloorMap.parse_key(str(k))
			for d in range(4):
				var has_door := bool(rooms[k]["doors"][d])
				var nk := FloorMap.key(c + FloorMap.DIR_VECTORS[d])
				var neighbor_exists: bool = rooms.has(nk)

				if has_door and not neighbor_exists:
					_fail("seed %d: %s 的 %s 门通向不存在的房间" % [s, k, FloorMap.DIR_NAMES[d]])
					continue
				if not neighbor_exists:
					continue

				var back := bool(rooms[nk]["doors"][FloorMap.opposite(d)])
				if has_door != back:
					_fail("seed %d: %s->%s 单向门 (%s 侧 %s, 对面 %s)" % [s, k, nk, FloorMap.DIR_NAMES[d], has_door, back])

				var sec := bool(rooms[k]["secret_doors"][d])
				var sec_back := bool(rooms[nk]["secret_doors"][FloorMap.opposite(d)])
				if sec != sec_back:
					_fail("seed %d: %s->%s 的秘密门标记只有一侧" % [s, k, nk])
	print("  [PASS] 所有门双向一致, 秘密门标记也一致")


func _test_boss_is_farthest_dead_end() -> void:
	print("\n[STEP 3] Boss 房必须存在, 且是最远的死胡同...")
	for s in range(SEEDS):
		var data := FloorMap.generate((s % 8) + 1, 9000 + s)
		var rooms: Dictionary = data["rooms"]
		var boss_key: String = data["boss"]

		if boss_key == "" or not rooms.has(boss_key):
			_fail("seed %d: 没有 boss 房 —— 这一层没有出口" % s)
			continue

		var boss_depth := int(rooms[boss_key]["depth"])
		if boss_depth <= 0:
			_fail("seed %d: boss 房深度 %d, 和起始房重合或不可达" % [s, boss_depth])

		# boss 必须比"所有其它死胡同"都远 (并列可接受)。这是难度曲线的地基:
		# boss 房被排在近处的话, 玩家第一间就能撞见它。
		for k in rooms.keys():
			if str(k) == boss_key or bool(rooms[k]["secret"]):
				continue
			var doors: Array = rooms[k]["doors"]
			var n := 0
			for d in range(4):
				if bool(doors[d]):
					n += 1
			if n == 1 and int(rooms[k]["depth"]) > boss_depth:
				_fail("seed %d: 死胡同 %s (深 %d) 比 boss 房 (深 %d) 还远" % [s, k, int(rooms[k]["depth"]), boss_depth])
	print("  [PASS] Boss 房存在且位于最深的死胡同")


func _test_special_rooms_unique_and_placed() -> void:
	print("\n[STEP 4] 特殊房不重叠, 商店保底数量满足...")
	var no_shop := 0
	for s in range(SEEDS):
		var act := (s % 8) + 1
		var data := FloorMap.generate(act, 13000 + s)
		var rooms: Dictionary = data["rooms"]

		var counts := {}
		for k in rooms.keys():
			var t := str(rooms[k]["type"])
			counts[t] = int(counts.get(t, 0)) + 1

		if int(counts.get("start", 0)) != 1:
			_fail("seed %d: start 房有 %d 个" % [s, int(counts.get("start", 0))])
		if int(counts.get("boss", 0)) != 1:
			_fail("seed %d: boss 房有 %d 个" % [s, int(counts.get("boss", 0))])
		if int(counts.get("treasure", 0)) > 1:
			_fail("seed %d: 宝物房有 %d 个, 应当至多 1" % [s, int(counts.get("treasure", 0))])
		if int(counts.get("secret", 0)) > 1:
			_fail("seed %d: 秘密房有 %d 个, 应当至多 1" % [s, int(counts.get("secret", 0))])

		if int(counts.get("shop", 0)) < FloorMap.MIN_SHOPS_PER_FLOOR:
			no_shop += 1

	# 商店落点依赖死胡同数量, 极少数极端形状 (整层几乎是一条环) 可能没有死胡同
	# 可分。允许小比例, 但不能是常态 —— 一层没有商店等于建造系统那一层断粮。
	if no_shop > SEEDS * 0.05:
		_fail("有 %d/%d 个种子的楼层没有商店 (上限 5%%)" % [no_shop, SEEDS])
	print("  [PASS] 特殊房唯一性成立, 无商店楼层 %d/%d" % [no_shop, SEEDS])


func _test_secret_room_rules() -> void:
	print("\n[STEP 5] 秘密房不贴 boss, 且至少贴 2 个房间...")
	var placed := 0
	for s in range(SEEDS):
		var data := FloorMap.generate((s % 8) + 1, 21000 + s)
		var rooms: Dictionary = data["rooms"]
		var sk: String = data["secret"]
		if sk == "":
			continue
		placed += 1
		if not rooms.has(sk):
			_fail("seed %d: secret key %s 不在 rooms 里" % [s, sk])
			continue

		var c := FloorMap.parse_key(sk)
		var neighbors := 0
		for d in range(4):
			var nk := FloorMap.key(c + FloorMap.DIR_VECTORS[d])
			if not rooms.has(nk):
				continue
			neighbors += 1
			if str(rooms[nk]["type"]) == "boss":
				_fail("seed %d: 秘密房 %s 贴着 boss 房" % [s, sk])
		if neighbors < 2:
			_fail("seed %d: 秘密房 %s 只贴着 %d 个房间" % [s, sk, neighbors])

	if placed < SEEDS * 0.5:
		_fail("只有 %d/%d 个种子放下了秘密房, 太少" % [placed, SEEDS])
	print("  [PASS] 秘密房规则成立, %d/%d 个种子放下了秘密房" % [placed, SEEDS])


func _test_determinism() -> void:
	print("\n[STEP 6] 同一个 (act, seed) 必须生成同一张图...")
	for s in range(20):
		var a := FloorMap.generate(3, 777 + s)
		var b := FloorMap.generate(3, 777 + s)
		if a["start"] != b["start"] or a["boss"] != b["boss"]:
			_fail("seed %d: 两次生成的 start/boss 不同" % s)
			continue
		var ra: Dictionary = a["rooms"]
		var rb: Dictionary = b["rooms"]
		if ra.size() != rb.size():
			_fail("seed %d: 两次生成房间数不同 (%d vs %d)" % [s, ra.size(), rb.size()])
			continue
		for k in ra.keys():
			if not rb.has(k):
				_fail("seed %d: 第二次生成缺少房间 %s" % [s, k])
				break
			if str(ra[k]["type"]) != str(rb[k]["type"]):
				_fail("seed %d: 房间 %s 类型不同 (%s vs %s)" % [s, k, ra[k]["type"], rb[k]["type"]])
				break
	print("  [PASS] 生成是确定性的")
