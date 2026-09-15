class_name CompositeRoomBuilder
extends RefCounted

## 大房间 (26x26, "large") / 超大房间 (52x52, "huge") 的关卡拼装器。
##
## 不重新造一套生成器: 56+ 张手搓模板和 MapDirector 的程序生成都锁死在
## 13x13 (main.gd::_build_map()/一堆 tools/test_*.gd 断言这一点), 改它们
## 风险大、收益低。这里改用"拼积木": 用不同的 room_key 后缀独立抽 N x N 张
## 已经验收过的普通 13x13 关卡, 缝到一张大网格里, 再把"必须是空地"的规则
## (敌人出生点/玩家出生点/老鹰基地) 从"每张 13x13 各自的四角"改成
## "只管拼出来的大网格的真正外沿" —— 内部每张子图自己的四角在拼接后已经是
## 图纸内部, 直接盖掉重新当地板处理, 无所谓。
##
## room_key 里拼进 (qr, qc) 当后缀是关键: MapTemplates.get_layout_for_stage()
## 早就支持按 room_key 哈希出一个 room_entropy 偏移 (给同一层楼里的不同房间
## 挑不同的图), 这里白嫖同一个机制, 让 N x N 个象限各自独立抽图, 不会拿到
## N x N 份完全相同的子图。

const MapTemplates = preload("res://scripts/map_templates.gd")
const MapDirector = preload("res://scripts/map_director.gd")
const RoomDoor = preload("res://scripts/room_door.gd")

const CHUNK := 13
const SIZE_CHUNKS := {"large": 2, "huge": 4}
## 门廊/接缝挖多深, 跟 main.gd::CORRIDOR_DEPTH 保持一致的手感 —— 接缝在
## 建筑意义上就是一条内部门廊, 没有理由挖得比真正的门浅或深。
const CORRIDOR_DEPTH := 2


static func chunk_count_for(room_size: String) -> int:
	return int(SIZE_CHUNKS.get(room_size, 1))


## 单一出处: main.gd 的攻城房加成 (Stage 3) 用同一张表决定摆几个敌人出生点,
## 两边各写一份的话迟早会抽风不一致。
static func enemy_spawn_count_for(room_size: String) -> int:
	match room_size:
		"large": return 5
		"huge": return 7
		_: return 3


## 主入口。room_size 不是 "large"/"huge" 时原样退化成普通单张 13x13 —— 这个
## 分支只在防御性场景下触发 (调用方本该只在 size != "normal" 时才调这个类)。
static func build(room_size: String, floor_idx: int, battle_type: String, act: int, room_key: String) -> Array:
	var n := chunk_count_for(room_size)
	if n <= 1:
		return MapTemplates.get_layout_for_stage(floor_idx, battle_type, act, true, room_key)

	var grid := _stitch_chunks(n, floor_idx, battle_type, act, room_key)
	_carve_seams(grid, n)

	var grid_w := n * CHUNK
	var grid_h := n * CHUNK
	var spawn_count := enemy_spawn_count_for(room_size)
	_apply_true_edge_reservations(grid, grid_w, grid_h, spawn_count)
	_repair_connectivity(grid, grid_w, grid_h, spawn_count)
	return grid


static func _clear_cell(grid: Array, r: int, c: int) -> void:
	if r >= 0 and r < grid.size() and c >= 0 and c < grid[r].size():
		grid[r][c] = 0


## 独立抽 n x n 张已验收的普通 13x13 关卡 (模板或程序生成, 走
## get_layout_for_stage() 原本的分派, 不做任何改动), 深拷贝后拼进一张大网格。
## 必须深拷贝 —— 原因和 main.gd::_build_map() 里那条注释一样: 手搓模板返回的
## 是 const 数组本身的引用, 原地改了就是永久改坏这张模板。
static func _stitch_chunks(n: int, floor_idx: int, battle_type: String, act: int, room_key: String) -> Array:
	var grid: Array = []
	for r in range(n * CHUNK):
		var row: Array = []
		row.resize(n * CHUNK)
		row.fill(0)
		grid.append(row)

	for qr in range(n):
		for qc in range(n):
			var chunk_key := "%s_q%d_%d" % [room_key, qr, qc]
			var chunk: Array = MapTemplates.get_layout_for_stage(floor_idx, battle_type, act, true, chunk_key)
			for rr in range(mini(CHUNK, chunk.size())):
				var src_row: Array = chunk[rr]
				for cc in range(mini(CHUNK, src_row.size())):
					grid[qr * CHUNK + rr][qc * CHUNK + cc] = src_row[cc]
	return grid


## 每条内部象限边界挖一条 CORRIDOR_DEPTH*2 格深的直通道, 通道对齐子块自己的
## 中心列/行 (跟一张普通房间的东西向门用房间中心行是同一个道理) —— 不需要
## 避让老鹰基地, 因为基地只会出现在整张拼图的真正外沿, 内部接缝够不着。
static func _carve_seams(grid: Array, n: int) -> void:
	var mid_col := RoomDoor.center_col_for(CHUNK)
	var mid_row := RoomDoor.center_row_for(CHUNK)

	for qr in range(n - 1):
		var boundary_row := (qr + 1) * CHUNK
		for qc in range(n):
			var col := qc * CHUNK + mid_col
			for step in range(CORRIDOR_DEPTH):
				_clear_cell(grid, boundary_row - 1 - step, col)
				_clear_cell(grid, boundary_row + step, col)

	for qc in range(n - 1):
		var boundary_col := (qc + 1) * CHUNK
		for qr in range(n):
			var row := qr * CHUNK + mid_row
			for step in range(CORRIDOR_DEPTH):
				_clear_cell(grid, row, boundary_col - 1 - step)
				_clear_cell(grid, row, boundary_col + step)


## 只清"整张拼图"的真正外沿: 顶边 spawn_count 个敌人出生点、底边老鹰基地
## (3 格本体+两侧各一) 和两个玩家出生点。跟 MapDirector.RESERVED 的形状
## 完全对应, 只是把字面量 6/12/5/7/4/8 换成 RoomDoor 的通用公式。
## 每个子块自己原本的四角保留格在这里被直接盖成普通地板 —— 拼接后它们已经
## 是图纸内部, 不再需要"是空地"这条硬性要求。
static func _apply_true_edge_reservations(grid: Array, grid_w: int, grid_h: int, spawn_count: int) -> void:
	for col in RoomDoor.enemy_spawn_cols_for(grid_w, spawn_count):
		_clear_cell(grid, 0, col)

	var center_col := RoomDoor.center_col_for(grid_w)
	var base_row := RoomDoor.base_row_for(grid_h)
	for c in [center_col - 1, center_col, center_col + 1]:
		_clear_cell(grid, base_row - 1, c)
		_clear_cell(grid, base_row, c)
	for c in [center_col - 2, center_col + 2]:
		_clear_cell(grid, base_row, c)


static func _reachable_from_base(grid: Array, grid_w: int, grid_h: int) -> Dictionary:
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
	var start := Vector2i(RoomDoor.center_col_for(grid_w), RoomDoor.base_row_for(grid_h))
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


## 接缝走廊按固定的子块中心列/行走, 极少数情况下 (例如某张子图恰好在自己
## 内部把那条直线彻底封死) 缝完之后某个真正的出生点仍然到不了基地 ——
## 跟 MapDirector._repair_connectivity() 完全一样的思路: 就地铲出一条 L 形
## 直角通道接回去, 而不是整张推倒重来。
static func _repair_connectivity(grid: Array, grid_w: int, grid_h: int, spawn_count: int) -> void:
	var center_col := RoomDoor.center_col_for(grid_w)
	var base_row := RoomDoor.base_row_for(grid_h)
	var target := Vector2i(center_col, base_row)

	var checkpoints: Array[Vector2i] = []
	for col in RoomDoor.enemy_spawn_cols_for(grid_w, spawn_count):
		checkpoints.append(Vector2i(col, 0))
	for c in [center_col - 2, center_col + 2]:
		checkpoints.append(Vector2i(c, base_row))

	for start in checkpoints:
		if _reachable_from_base(grid, grid_w, grid_h).has(start):
			continue
		var cur: Vector2i = start
		while cur.y != target.y:
			cur.y += 1 if target.y > cur.y else -1
			if int(grid[cur.y][cur.x]) in MapDirector.HARD_BLOCK:
				grid[cur.y][cur.x] = 0
		while cur.x != target.x:
			cur.x += 1 if target.x > cur.x else -1
			if int(grid[cur.y][cur.x]) in MapDirector.HARD_BLOCK:
				grid[cur.y][cur.x] = 0

	_apply_true_edge_reservations(grid, grid_w, grid_h, spawn_count)
