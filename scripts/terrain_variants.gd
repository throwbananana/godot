class_name TerrainVariants
extends RefCounted

## 地形瓦片差分的选图器。
##
## 同一种地形有多张外观差分 (tools/build_terrain_variants.py 渲的), 这里负责
## 回答"这一格该用哪一张"。两个维度:
##
##   主题 (theme)   —— 按 GameState.get_visual_act() 取 a1/a2/a3。砖和钢是仅有
##                     的两种在三幕模板里都会出现的瓦片, 所以只有它们有主题差分;
##                     沙/树本身就是主题地形 (沙漠出沙、平原出树), 它们的"主题
##                     差分"就是彼此。
##   变体 (variant) —— 同一主题下的磨损/风化差分, 按格子确定性挑一张, 让整面墙
##                     不再是同一张图复制 30 遍。
##
## === 必须是纯哈希, 不能用 randi() ===
##
## 每日挑战在 main.gd::start_game() 里用当天的种子 seed() 了全局 RNG, 然后
## 地图生成和敌人生成都依赖那条流保持确定 —— 全服同一个种子跑出同一局是这个
## 模式的全部意义。在建图中途从那条流里抽数会让后面所有人的随机序列整体错位,
## 而且不报任何错。所以这里一个随机数都不取, 全部由 (格号, 房间, run_seed)
## 哈希出来。
##
## === 为什么要把房间和 run_seed 混进去 ===
##
## 只哈希格号的话, 每个房间的同一格永远是同一张变体 —— 一层楼走下来, 玩家会
## 发现"每个房间左上角那块砖都是长苔藓的那张"。混入 current_room 让不同房间
## 的同一格不同; 混入 run_seed (存档里持久化的) 让不同存档不同, 但**同一存档
## 重进同一个房间时完全一致** —— 房间是可以反复进出的, 每次进去墙都换一副面孔
## 会像贴图在闪。
##
## === 权重不是均匀的 ===
##
## 基础图占一半, 两个变体各占四分之一。均匀三等分意味着三分之二的砖都是"破损/
## 长苔藓"的特殊态, 那样特殊态就不特殊了, 整面墙反而变成另一种均质的噪声。

const TILES := "res://assets/sprites/tiles/"

## kind -> theme -> 该主题下的图列表 (第 0 张是该主题的基础图)。
##
## 沙和树在三个主题下用同一份列表 —— 它们没有主题差分, 见类注释。写成显式
## 三份而不是 fallback, 是为了让 tools/test_asset_variants.gd 能直接遍历这张
## 表断言"表里每一个路径都存在", 而不需要知道哪些键是别名。
const VARIANT_TABLE := {
	"brick": {
		1: ["tile_brick.png", "tile_brick_v1.png", "tile_brick_v2.png"],
		2: ["tile_brick_a2.png", "tile_brick_a2_v1.png", "tile_brick_a2_v2.png"],
		3: ["tile_brick_a3.png", "tile_brick_a3_v1.png", "tile_brick_a3_v2.png"],
	},
	"steel": {
		1: ["tile_steel.png", "tile_steel_v1.png", "tile_steel_v2.png"],
		2: ["tile_steel_a2.png", "tile_steel_a2_v1.png", "tile_steel_a2_v2.png"],
		3: ["tile_steel_a3.png", "tile_steel_a3_v1.png", "tile_steel_a3_v2.png"],
	},
	"sand": {
		1: ["tile_sand.png", "tile_sand_v1.png", "tile_sand_v2.png"],
		2: ["tile_sand.png", "tile_sand_v1.png", "tile_sand_v2.png"],
		3: ["tile_sand.png", "tile_sand_v1.png", "tile_sand_v2.png"],
	},
	"trees": {
		1: ["tile_trees.png", "tile_trees_v1.png", "tile_trees_v2.png"],
		2: ["tile_trees.png", "tile_trees_v1.png", "tile_trees_v2.png"],
		3: ["tile_trees.png", "tile_trees_v1.png", "tile_trees_v2.png"],
	},
}

## 基础图 50%, 两个变体各 25%。累计权重, 和 VARIANT_TABLE 的列表等长。
const VARIANT_WEIGHTS := [50, 25, 25]

## 非地形、但同样会**按格子成排重复**的东西。目前只有加固墙: 它是玩家用建造
## 系统一格一格摆出来的, 一道八格长的墙就是同一张图连贴八次 —— 这正是差分要
## 解决的那个问题, 和地形是同一回事。其余建筑一张图上通常只出现一两次, 不在
## 此列。
##
## 放在这个类里而不是各自为政, 是为了让 tools/test_asset_variants.gd 有**一处**
## 可以遍历的表 —— 变体图漏渲/漏导入是无声的 (选到了就是空贴图), 必须有个地方
## 能枚举出"应该存在哪些图"。
const PROP_VARIANT_TABLE := {
	"fortified_wall": [
		"res://assets/sprites/buildings/fortified_wall.png",
		"res://assets/sprites/buildings/fortified_wall_v1.png",
		"res://assets/sprites/buildings/fortified_wall_v2.png",
	],
}


## 按格子挑一张道具/建筑变体图。和地形共用同一套哈希, 所以相邻的两面墙几乎
## 不会撞同一张。
static func prop_texture_for(kind: String, cell: Vector2i) -> Texture2D:
	if not PROP_VARIANT_TABLE.has(kind):
		return null
	var list: Array = PROP_VARIANT_TABLE[kind]
	if list.is_empty():
		return null
	var tex := TextureHelper.get_tex(str(list[variant_index(kind, cell, list.size())]))
	if tex == null:
		tex = TextureHelper.get_tex(str(list[0]))
	return tex


## 这一格该用哪张图。kind 不在表里 (例如 ice / hard_clay 这些还没做差分的)
## 就返回 null, 调用方沿用自己原来的贴图。
static func texture_for(kind: String, cell: Vector2i) -> Texture2D:
	var path := path_for(kind, cell)
	if path.is_empty():
		return null
	var tex := TextureHelper.get_tex(path)
	if tex == null:
		# 图还没导入 (新增美术后忘了跑 import 是很常见的一步), 退回该主题的
		# 基础图, 再退回 a1 的基础图。宁可整面墙没有差分, 也不要空贴图。
		var themed: Array = _list_for(kind, _theme())
		if themed.size() > 0:
			tex = TextureHelper.get_tex(TILES + str(themed[0]))
		if tex == null:
			var base: Array = _list_for(kind, 1)
			if base.size() > 0:
				tex = TextureHelper.get_tex(TILES + str(base[0]))
	return tex


## 单独暴露路径这一层, 好让测试能在不加载纹理的情况下断言选择逻辑
## (确定性、覆盖到全部变体、权重分布)。
static func path_for(kind: String, cell: Vector2i) -> String:
	var list: Array = _list_for(kind, _theme())
	if list.is_empty():
		return ""
	return TILES + str(list[variant_index(kind, cell, list.size())])


## 挑第几个变体。抽出来是为了让测试可以喂任意 (kind, cell) 而不必造一个
## GameState —— 除了 run_seed / current_room 这两个全局态之外它是纯函数。
static func variant_index(kind: String, cell: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	var h := _mix(kind, cell, GameState.current_room, GameState.run_seed)
	# 按权重挑。权重表比变体表短时 (以后加了第 4 张但忘了加权重), 多出来的
	# 变体按权重 1 处理 —— 少见但不至于挑不到。
	var total := 0
	for i in count:
		total += VARIANT_WEIGHTS[i] if i < VARIANT_WEIGHTS.size() else 1
	var roll := int(h % total)
	var acc := 0
	for i in count:
		acc += VARIANT_WEIGHTS[i] if i < VARIANT_WEIGHTS.size() else 1
		if roll < acc:
			return i
	return count - 1


static func _theme() -> int:
	return GameState.get_visual_act()


static func _list_for(kind: String, theme: int) -> Array:
	if not VARIANT_TABLE.has(kind):
		return []
	var by_theme: Dictionary = VARIANT_TABLE[kind]
	if by_theme.has(theme):
		return by_theme[theme]
	return by_theme.get(1, [])


## FNV-1a + 一轮雪崩混合。
##
## 手写而不是用 String.hash(): 这个值决定了地图长什么样, 而 hash() 的实现是
## 引擎内部细节, 换个 Godot 版本就可能变 —— 那会让"同一存档重进同一房间, 墙
## 长得一样"这条保证在升级引擎时静默失效。自己写的话它只取决于这几行代码。
static func _mix(kind: String, cell: Vector2i, room: String, run_seed: int) -> int:
	var h := 2166136261
	for s in [kind, "|", room]:
		for i in str(s).length():
			h = (h ^ str(s).unicode_at(i)) & 0xFFFFFFFF
			h = (h * 16777619) & 0xFFFFFFFF
	h = (h ^ (cell.x * 73856093)) & 0xFFFFFFFF
	h = (h * 16777619) & 0xFFFFFFFF
	h = (h ^ (cell.y * 19349663)) & 0xFFFFFFFF
	h = (h * 16777619) & 0xFFFFFFFF
	h = (h ^ (run_seed * 83492791)) & 0xFFFFFFFF
	# 雪崩: 不做这一步的话相邻格子的低位高度相关, 而"挑第几个变体"取的正是
	# 低位 —— 结果是整片墙按棋盘格规律交替, 比没有差分更扎眼。
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return h


## 由格心像素坐标反推格号。main.gd 里瓦片的 pos 一律是 (c+0.5)*TILE_SIZE,
## 所以整除就还原了 —— 和 _spawn_tile() 里给 tree_sprites 记格号是同一个式子。
static func cell_of(pos: Vector2, tile_size: float) -> Vector2i:
	return Vector2i(int(pos.x / tile_size), int(pos.y / tile_size))
