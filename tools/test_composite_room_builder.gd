extends SceneTree

## CompositeRoomBuilder (大房间/超大房间的拼图逻辑) 的结构验收。
##
## 只验"拼出来的图纸对不对", 不启动 main.tscn -- 跟 test_floor_map.gd 只验
## 抽象房间图、不验实际走位是同一个分工。渲染/摄像机/走位分别由
## test_camera_bounds.gd 和 test_room_flow.gd 里新增的大房间用例覆盖。

const CompositeRoomBuilder = preload("res://scripts/composite_room_builder.gd")
const RoomDoor = preload("res://scripts/room_door.gd")
const MapDirector = preload("res://scripts/map_director.gd")

const SEEDS := 50

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
	print(">>> COMPOSITE ROOM BUILDER TEST <<<")
	print("==================================================")

	_test_dimensions()
	_test_reservations_and_connectivity("large", 26)
	_test_reservations_and_connectivity("huge", 52)

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL COMPOSITE ROOM BUILDER CHECKS PASSED! <<<")
		quit(0)


func _test_dimensions() -> void:
	print("\n--- 输出尺寸 ---")
	var large := CompositeRoomBuilder.build("large", 3, "battle", 1, "dim_large")
	if large.size() != 26:
		fail("large 应该是 26 行, 实际 %d" % large.size())
	elif large[0].size() != 26 or large[25].size() != 26:
		fail("large 每行应该是 26 列, 实际首行 %d / 末行 %d" % [large[0].size(), large[25].size()])
	else:
		ok("large 输出 26x26")

	var huge := CompositeRoomBuilder.build("huge", 6, "battle", 2, "dim_huge")
	if huge.size() != 52:
		fail("huge 应该是 52 行, 实际 %d" % huge.size())
	elif huge[0].size() != 52 or huge[51].size() != 52:
		fail("huge 每行应该是 52 列, 实际首行 %d / 末行 %d" % [huge[0].size(), huge[51].size()])
	else:
		ok("huge 输出 52x52")


## 扫 SEEDS 组 (floor_idx, room_key, battle_type, act), large/huge 各自反复
## 建图, 断言: 真正外沿的保留格确实是空地, 且从真正基地格出发能 BFS 到
## 每一个真正的出生点 -- 对齐 MapDirector.validate()/reachable_from_base()
## 的验收口径, 只是把 13 换成拼出来的 grid_w/grid_h。
func _test_reservations_and_connectivity(room_size: String, expected_dim: int) -> void:
	print("\n--- %s (%dx%d): 保留格 + 连通性, 扫 %d 组 ---" % [room_size, expected_dim, expected_dim, SEEDS])
	var spawn_count: int = CompositeRoomBuilder.enemy_spawn_count_for(room_size)
	var center_col := RoomDoor.center_col_for(expected_dim)
	var base_row := RoomDoor.base_row_for(expected_dim)
	var battle_types := ["battle", "challenge", "elite"]
	var bad_reserved := 0
	var bad_conn := 0

	for i in range(SEEDS):
		var floor_idx := i % 15
		var act := (i % 3) + 1
		var battle_type: String = battle_types[i % battle_types.size()]
		var room_key := "sweep_%s_%d" % [room_size, i]
		var grid := CompositeRoomBuilder.build(room_size, floor_idx, battle_type, act, room_key)

		# 保留格必须是空地 (0)。
		var reserved: Array[Vector2i] = []
		for col in RoomDoor.enemy_spawn_cols_for(expected_dim, spawn_count):
			reserved.append(Vector2i(col, 0))
		for c in [center_col - 1, center_col, center_col + 1]:
			reserved.append(Vector2i(c, base_row - 1))
			reserved.append(Vector2i(c, base_row))
		for c in [center_col - 2, center_col + 2]:
			reserved.append(Vector2i(c, base_row))
		for p in reserved:
			if int(grid[p.y][p.x]) != 0:
				bad_reserved += 1
				fail("[%s seed %d] 保留格 (%d,%d) 被地块 %d 占了" % [room_size, i, p.x, p.y, int(grid[p.y][p.x])])

		# 连通性: 从真正基地格出发, BFS 必须覆盖每一个真正的出生点。
		var seen := _reachable(grid, expected_dim, expected_dim, center_col, base_row)
		for col in RoomDoor.enemy_spawn_cols_for(expected_dim, spawn_count):
			if not seen.has(Vector2i(col, 0)):
				bad_conn += 1
				fail("[%s seed %d] 敌人出生点 (%d,0) 通不到基地" % [room_size, i, col])
		for c in [center_col - 2, center_col + 2]:
			if not seen.has(Vector2i(c, base_row)):
				bad_conn += 1
				fail("[%s seed %d] 玩家出生点 (%d,%d) 通不到基地" % [room_size, i, c, base_row])

	if bad_reserved == 0:
		ok("%d 组: 保留格全部是空地" % SEEDS)
	if bad_conn == 0:
		ok("%d 组: 每个出生点都能 BFS 到基地" % SEEDS)


func _reachable(grid: Array, grid_w: int, grid_h: int, start_col: int, start_row: int) -> Dictionary:
	var blockers: Array = MapDirector.HARD_BLOCK.duplicate()
	var has_crossing := false
	for r in range(grid_h):
		for c in range(grid_w):
			if int(grid[r][c]) in MapDirector.CROSSING_TILES:
				has_crossing = true
				break
		if has_crossing:
			break
	if has_crossing:
		blockers.erase(3)

	var seen := {}
	var start := Vector2i(start_col, start_row)
	seen[start] = true
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.x >= grid_w or nxt.y < 0 or nxt.y >= grid_h:
				continue
			if seen.has(nxt):
				continue
			if int(grid[nxt.y][nxt.x]) in blockers:
				continue
			seen[nxt] = true
			stack.append(nxt)
	return seen
