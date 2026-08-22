class_name MapDirector
extends RefCounted

## 随机地图的逻辑控制器。
##
## 分工: MapGenerator 只管"按方案往格子里填地形"; 这里管**决定给什么方案、
## 生成完验收、不合格就修或者重来**。
##
## 为什么需要它 —— 程序生成原本完全绕开了楼层门禁:
##   * 敌人有 main.gd::ENEMY_MIN_FLOOR 按楼层解锁;
##   * 手搓地图有 MapTemplates.TEMPLATE_MIN_FLOOR 按楼层解锁;
##   * 而 MapGenerator.generate_map(act) 连 floor 参数都没有。
## 结果是 get_layout_for_stage() 在 `floor_idx % 3 == 2` 那几层转到程序生成,
## **第一次触发正好是 floor 2** —— 实测那张图平均有 29 格机制地形、6 种机制
## (act 3 更是 55 格 7 种), 而同一层的手搓模板按规矩只能是纯地形加至多一种
## {硬黏土/地雷/沙地}。也就是说全局最难的一张图出现在第三层。
##
## 难度旋钮取"机制**族**数"而不是"机制格数", 依据是手搓模板量出来的分布:
##   min_floor=0 : 机制族中位数 0
##   min_floor=2 : 机制族中位数 1, 最多 2
##   min_floor=5 : 机制族中位数 5, 最多 8
## 格数没有参考价值 —— GLACIER_ICE 有 48 格机制地形, 但只有"冰面"一种机制,
## 玩家要理解的东西并不多。难的是同时上演四五种互不相干的机制。

const MapGenerator = preload("res://scripts/map_generator.gd")

## 楼层 → 档位, 与 TEMPLATE_MIN_FLOOR 的 0/2/5 三档对齐。
const TIER_FLOORS := [0, 2, 5]

## 每档允许的机制族上限 / 机制总权重。权重是相对 BIOME_TERRAIN 的权重和
## (约 84) 而言的, 30 大致对应三成格子。
const TIER_BUDGET := [
	{"families": 0, "mech_weight": 0},    # 档 0: 纯地形
	{"families": 2, "mech_weight": 14},   # 档 1: 至多两族, 对齐 min_floor=2 的上限
	{"families": 5, "mech_weight": 30},   # 档 2: 至多五族, 对齐 min_floor=5 的中位数
]

## 各群系可选的机制族。选族时从这里抽, 所以沙漠不会冒出虫洞、冰原不会长出沙丘。
const BIOME_FAMILIES := {
	MapGenerator.Biome.PLAINS_FORTRESS: ["conveyor", "barrel", "electric", "shield", "jump", "lamp"],
	MapGenerator.Biome.DESERT_DUNES:    ["wind", "jump", "barrel", "electric", "shield", "lamp"],
	MapGenerator.Biome.GLACIAL_VOID:    ["ice", "wormhole", "platform", "electric", "lamp", "shield"],
}

## 坦克永远过不去的地形 (砖和黏土能打掉, 所以不算)。
## 25 是电墙: 它是 StaticBody2D 且加入 steel 组, 只有 3 阶等离子弹能打穿,
## 对绝大多数单位而言和钢墙没区别。
const HARD_BLOCK := [2, 3, 25]

## 摆渡/越障装置: 移动平台 (10/11/23)、虫洞 (12)、跳板 (22)。
##
## 图里只要有这些, 水面就不再算绝对屏障 —— 这不是放宽标准, 而是这类地图
## 本来就是这么设计的: 手搓的 VOID_CANAL / VOID_FERRY 第 3、9 行是**整幅**
## 水面, 全靠两侧 col1/col11 的竖向平台来回摆渡, 按"水=死路"去算它们必然
## 全军覆没。程序生成同样吃这一条: platform 族和水会同时出现在 PLAINS /
## GLACIAL 的抽样表里, 少了这层判断, 一张本来能玩的图会被自己判死, 白白
## 重摇甚至掉进兜底图。
##
## 语义与 tools/test_map_templates_and_base_fit.gd 对齐 —— 那边是先有的,
## 这边补上, 免得同一个"什么叫通得过去"在两处各说各话。
const CROSSING_TILES := [10, 11, 12, 22, 23]

## 必须保持空地的格子: 敌人出生点 / 玩家出生点 / 鹰巢与自动围墙
const RESERVED := [
	Vector2i(0, 0), Vector2i(6, 0), Vector2i(12, 0),
	Vector2i(4, 12), Vector2i(8, 12),
	Vector2i(5, 11), Vector2i(6, 11), Vector2i(7, 11),
	Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12),
]

const MAX_ATTEMPTS := 8


static func tier_for_floor(floor_idx: int) -> int:
	var tier := 0
	for i in range(TIER_FLOORS.size()):
		if floor_idx >= TIER_FLOORS[i]:
			tier = i
	return tier


## 主入口。
##   floor_idx     : 当前楼层, 决定档位
##   act           : 视觉幕 (1/2/3), 决定群系
##   custom_seed   : 非 0 则可复现 (每日挑战靠这个)
##   tier_override : >=0 时忽略楼层直接指定档位 (每日挑战要的就是满配)
static func build(floor_idx: int, act: int, custom_seed: int = 0, tier_override: int = -1) -> Array:
	var rng := RandomNumberGenerator.new()
	if custom_seed != 0:
		rng.seed = custom_seed
	else:
		rng.randomize()

	var biome := MapGenerator.Biome.PLAINS_FORTRESS
	match act:
		2: biome = MapGenerator.Biome.DESERT_DUNES
		3: biome = MapGenerator.Biome.GLACIAL_VOID

	var tier := tier_override if tier_override >= 0 else tier_for_floor(floor_idx)
	tier = clampi(tier, 0, TIER_BUDGET.size() - 1)

	for attempt in range(MAX_ATTEMPTS):
		var plan := _make_plan(biome, tier, rng)
		var grid := MapGenerator.generate_planned(plan, rng)
		_enforce_reserved(grid)
		_repair_connectivity(grid)
		if validate(grid, tier).is_empty():
			return grid

	# 八次都没过 —— 与其把一张没验收过的图丢给玩家, 不如给一张一定能玩的。
	# 这里自己拼而不是引用 MapTemplates, 是为了避免
	# map_templates -> map_generator -> map_director -> map_templates 的循环依赖。
	return _fallback_grid()


## 返回问题列表, 空数组表示合格。
static func validate(grid: Array, tier: int = -1) -> Array:
	var problems: Array[String] = []
	if grid.size() != 13:
		problems.append("行数 %d != 13" % grid.size())
		return problems
	for r in range(13):
		if grid[r].size() != 13:
			problems.append("第 %d 行列数 %d != 13" % [r, grid[r].size()])
			return problems
		for c in range(13):
			var v := int(grid[r][c])
			if v < 0 or v > 29:
				problems.append("(%d,%d) 地形号 %d 越界" % [r, c, v])

	for p in RESERVED:
		if int(grid[p.y][p.x]) != 0:
			problems.append("保留格 (%d,%d) 被 %d 占了" % [p.y, p.x, int(grid[p.y][p.x])])

	var seen := reachable_from_base(grid)
	for c in [0, 6, 12]:
		if not seen.has(Vector2i(c, 0)):
			problems.append("敌人出生点 (0,%d) 通不到鹰巢" % c)
	for c in [4, 8]:
		if not seen.has(Vector2i(c, 12)):
			problems.append("玩家出生点 (12,%d) 通不到鹰巢" % c)

	# 别生成一张几乎全是墙的图 —— 可通行面积至少要占四成
	var open_cells := 0
	for r in range(13):
		for c in range(13):
			if not int(grid[r][c]) in HARD_BLOCK:
				open_cells += 1
	if open_cells < 68:
		problems.append("可通行格只有 %d/169, 太堵" % open_cells)

	if tier >= 0:
		var fams := families_in(grid)
		var cap: int = TIER_BUDGET[clampi(tier, 0, TIER_BUDGET.size() - 1)]["families"]
		if fams.size() > cap:
			problems.append("档 %d 只允许 %d 个机制族, 实际 %d 个 (%s)"
				% [tier, cap, fams.size(), ", ".join(fams)])
	return problems


static func families_in(grid: Array) -> Array:
	var out: Array[String] = []
	for r in range(13):
		for c in range(13):
			var v := int(grid[r][c])
			for fam in MapGenerator.FAMILY_TILES:
				if v in MapGenerator.FAMILY_TILES[fam] and not fam in out:
					out.append(fam)
	out.sort()
	return out


static func reachable_from_base(grid: Array) -> Dictionary:
	var blockers: Array = HARD_BLOCK.duplicate()
	var has_crossing := false
	for r in range(13):
		for c in range(13):
			if int(grid[r][c]) in CROSSING_TILES:
				has_crossing = true
				break
		if has_crossing:
			break
	if has_crossing:
		blockers.erase(3)

	var seen := {}
	var start := Vector2i(6, 12)
	seen[start] = true
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.x > 12 or n.y < 0 or n.y > 12:
				continue
			if seen.has(n):
				continue
			if int(grid[n.y][n.x]) in blockers:
				continue
			seen[n] = true
			stack.append(n)
	return seen


static func _make_plan(biome: int, tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var budget: Dictionary = TIER_BUDGET[tier]
	var pool: Array = BIOME_FAMILIES[biome].duplicate()
	# 洗牌后取前 N 族 —— 每张图只挑几族, 所以同一档位的两张图也会长得不一样,
	# 而不是每张都把整个机制表铺满 (旧实现就是后者)。
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var n: int = mini(int(budget["families"]), pool.size())
	return {
		"biome": biome,
		"families": pool.slice(0, n),
		"mech_weight": int(budget["mech_weight"]),
		"symmetry": MapGenerator.Symmetry.HORIZONTAL,
	}


static func _enforce_reserved(grid: Array) -> void:
	for p in RESERVED:
		grid[p.y][p.x] = 0


## 把通不到鹰巢的出生点用一条直角走廊接回来。
##
## 修而不是单纯重摇, 是因为重摇会丢掉整张图的其它优点, 而且在高档位
## (钢/水/电墙都多) 下可能连摇八次都过不了。碰到永久障碍就地铲平成空地。
static func _repair_connectivity(grid: Array) -> void:
	var spawns: Array[Vector2i] = [Vector2i(0, 0), Vector2i(6, 0), Vector2i(12, 0),
		Vector2i(4, 12), Vector2i(8, 12)]
	for start in spawns:
		if reachable_from_base(grid).has(start):
			continue
		var target := Vector2i(6, 12)
		var cur: Vector2i = start
		# 先竖后横, 走一条 L 形
		while cur.y != target.y:
			cur.y += 1 if target.y > cur.y else -1
			if int(grid[cur.y][cur.x]) in HARD_BLOCK:
				grid[cur.y][cur.x] = 0
		while cur.x != target.x:
			cur.x += 1 if target.x > cur.x else -1
			if int(grid[cur.y][cur.x]) in HARD_BLOCK:
				grid[cur.y][cur.x] = 0
	_enforce_reserved(grid)


## 兜底图: 一张一定能玩的对称纯地形图。写死在这里而不是引用 MapTemplates,
## 是为了不制造循环依赖 (见 build() 的说明)。
static func _fallback_grid() -> Array:
	var g: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		g.append(row)
	for r in [3, 4, 8, 9]:
		for c in [2, 3, 9, 10]:
			g[r][c] = 1
	for c in [5, 6, 7]:
		g[6][c] = 1
	g[6][6] = 2
	_apply_reserved_to(g)
	return g


static func _apply_reserved_to(g: Array) -> void:
	for p in RESERVED:
		g[p.y][p.x] = 0
