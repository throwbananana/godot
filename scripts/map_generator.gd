class_name MapGenerator
extends RefCounted

## 随机地图的**采样器**: 按一份"方案(plan)"往格子里填地形, 只管填, 不管好不好玩。
##
## 决定"这一层该给什么样的图"、生成完检查连通性、不合格就重来 —— 那些是
## map_director.gd 的活。这里刻意只保留采样, 免得又出现两套都能生成地图、
## 谁后跑谁说了算的局面 (本仓库在 build_*.py 上已经吃过这个亏)。
##
## 入口是 generate_planned(); generate_map() 是保留的旧签名, 内部也走同一条
## 采样路径, 不另开一份实现。

enum Biome { PLAINS_FORTRESS, DESERT_DUNES, GLACIAL_VOID }
enum Symmetry { HORIZONTAL, ROTATIONAL, ASYMMETRIC }

## 各生物群系的**基础地形**权重 —— 不含任何需要现学的机制。
## [地形号, 权重]
const BIOME_TERRAIN := {
	Biome.PLAINS_FORTRESS: [[0, 34], [1, 18], [8, 10], [2, 7], [3, 7], [4, 8]],
	Biome.DESERT_DUNES:    [[0, 34], [6, 16], [7, 12], [8, 9], [2, 7], [1, 6]],
	Biome.GLACIAL_VOID:    [[0, 34], [1, 12], [8, 10], [2, 8], [3, 8], [4, 4]],
}

## 机制"族"→ 该族包含的地形号。按族而不是按地形号控制难度, 是因为难度来自
## "玩家要同时理解几种新机制", 而不是"屏幕上有多少格". 一张全是冰面的图有
## 48 格机制地形却只有一种机制, 并不难 —— 手搓模板 GLACIER_ICE 就是这样。
const FAMILY_TILES := {
	"ice":      [9],
	"platform": [10, 11, 23],
	"wormhole": [12],
	"shield":   [13],
	"wind":     [14, 15, 16, 17],
	"conveyor": [18, 19, 20, 21],
	"jump":     [22],
	"lamp":     [24],
	"electric": [25],
	"barrel":   [26],
}

## 生成一张 13x13 网格。
##
## plan 字段:
##   biome      : Biome
##   families   : Array[String]  允许出现的机制族 (可为空 -> 纯地形图)
##   mech_weight: int            机制地形的总权重 (相对 BIOME_TERRAIN 的权重和)
##   symmetry   : Symmetry
static func generate_planned(plan: Dictionary, rng: RandomNumberGenerator) -> Array:
	var biome: int = plan.get("biome", Biome.PLAINS_FORTRESS)
	var families: Array = plan.get("families", [])
	var mech_weight: int = plan.get("mech_weight", 0)
	var symmetry: int = plan.get("symmetry", Symmetry.HORIZONTAL)

	# 把地形与机制拼成一张加权表, 一次带权抽样搞定, 不用一串 if roll <
	var table: Array = []
	for entry in BIOME_TERRAIN[biome]:
		table.append([int(entry[0]), int(entry[1])])
	if not families.is_empty() and mech_weight > 0:
		# 总机制权重按族均分, 族内再按地形号均分 —— 这样"族"才是难度旋钮:
		# 允许 4 个方向的风机不会让风比只有 1 种地形的虫洞多占 4 倍面积。
		var per_family: float = float(mech_weight) / float(families.size())
		for fam in families:
			var tiles: Array = FAMILY_TILES.get(fam, [])
			if tiles.is_empty():
				continue
			var per_tile: int = maxi(1, int(round(per_family / float(tiles.size()))))
			for t in tiles:
				table.append([int(t), per_tile])

	var total: int = 0
	for e in table:
		total += int(e[1])

	var grid: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		grid.append(row)

	# 1. 只生成左半边 (含中列)
	for r in range(1, 12):
		for c in range(1, 7):
			if r >= 10 and c >= 4:
				continue          # 鹰巢保护区
			if r <= 1 and (c <= 1 or c == 6):
				continue          # 敌人出生区
			grid[r][c] = _weighted_pick(table, total, rng)

	# 2. 镜像到右半边
	if symmetry == Symmetry.HORIZONTAL:
		for r in range(13):
			for c in range(7, 13):
				grid[r][c] = _mirror_tile_horizontal(grid[r][12 - c])
	elif symmetry == Symmetry.ROTATIONAL:
		for r in range(13):
			for c in range(7, 13):
				grid[r][c] = _mirror_tile_rotational(grid[12 - r][12 - c])

	_carve_critical_paths(grid)
	return grid


static func _weighted_pick(table: Array, total: int, rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi_range(1, maxi(1, total))
	var acc: int = 0
	for e in table:
		acc += int(e[1])
		if roll <= acc:
			return int(e[0])
	return 0


## 旧签名, 保留给不关心楼层的调用方 (以及历史测试)。走的是同一条采样路径,
## 只是自己拼一份"全机制"方案 —— 想要按楼层控难度请用 MapDirector.build()。
static func generate_map(act: int = 1, symmetry: Symmetry = Symmetry.HORIZONTAL, custom_seed: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	if custom_seed != 0:
		rng.seed = custom_seed
	else:
		rng.randomize()

	var biome := Biome.PLAINS_FORTRESS
	match act:
		2: biome = Biome.DESERT_DUNES
		3: biome = Biome.GLACIAL_VOID
		_: biome = Biome.PLAINS_FORTRESS

	return generate_planned({
		"biome": biome,
		"families": FAMILY_TILES.keys(),
		"mech_weight": 30,
		"symmetry": symmetry,
	}, rng)


static func _mirror_tile_horizontal(tile: int) -> int:
	match tile:
		16: return 17 # Wind LEFT -> RIGHT
		17: return 16 # Wind RIGHT -> LEFT
		20: return 21 # Conveyor LEFT -> RIGHT
		21: return 20 # Conveyor RIGHT -> LEFT
		_: return tile


static func _mirror_tile_rotational(tile: int) -> int:
	match tile:
		14: return 15
		15: return 14
		16: return 17
		17: return 16
		18: return 19
		19: return 18
		20: return 21
		21: return 20
		_: return tile


## 清出出生点、鹰巢区和中央走廊。这是**硬约束**, 不是美化:
## main.gd::_spawn_base_and_walls() 会自己在 row11 col5-7 / row12 col5,7 放
## 鹰和围墙, 那几格必须是空的。
static func _carve_critical_paths(grid: Array) -> void:
	for c in range(13):
		grid[0][c] = 0
		grid[12][c] = 0

	for c in [0, 1, 5, 6, 7, 11, 12]:
		grid[0][c] = 0
		grid[1][c] = 0

	for r in [10, 11, 12]:
		for c in [4, 5, 6, 7, 8]:
			grid[r][c] = 0

	# 中央竖向走廊别被永久障碍堵死
	for r in [2, 3, 7, 8, 9]:
		if grid[r][6] == 2 or grid[r][6] == 25:
			grid[r][6] = 0
