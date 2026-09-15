extends SceneTree

## 外观差分 (地形 / 坦克 / 建筑) 的闸门。
##
## 差分这类改动的失效方式**全是无声的**: 漏渲一张图 -> 选到了就是空贴图;
## 两张变体被复制成同一张 -> 看起来"有差分"其实没有; 选择器不确定 -> 同一个
## 房间每次进去墙都在闪; 叠加层画幅错了 -> 焦痕贴在车外面。这些都不会报错。
## 所以这里把每一条都变成断言。
##
## 覆盖的不变量:
##
##   1. 表里登记的每一张图都存在、能加载、是 256x256。
##      256 这条抓的是画幅/分辨率传错 —— CLAUDE.md 记过八张道具因为传错
##      ortho_scale 静默小了 0.82 倍的事故。
##   2. 同一族里任意两张变体的**像素数据不相同**。这条抓的是复制粘贴:
##      CLAUDE.md 记过 title_banner / ui_title_crest / title_logo_banner 三个
##      文件同一个 md5 的事故, 当时也是什么都没报错。
##   3. 坦克叠加层不侵入炮塔中心禁区。炮塔和炮管是玩家判断"这车朝哪、是什么车"
##      的地方; 叠加层无条件画在车体之上, 糊住了不会报错, 只会让车变得读不懂。
##   4. 建筑战区覆盖层必须铺到最大建筑的半宽以外。它靠 clip_children 裁进建筑
##      剪影, 铺得不够远的话大建筑上会露出**贴花自己的弧边** —— 那比飘在建筑
##      外面更假, 因为那是一条与建筑无关的边。
##   5. 战损两档的覆盖面积严格递增。和装甲板同一条理由: 48px 显示尺寸下唯一
##      可靠的信号是覆盖面积 (见 tools/test_armor_plating.gd)。
##   6. 选择器是确定性的、覆盖得到全部变体、换幕真的换图、换房间真的换分布。
##   7. BuildingSkin 真的设了 clip_children、真的抄了 region、档位真的随血量走。
##   8. enemy.gd 的战损档位随血量走, 且伪装中的 MIRAGE 不会把叠加层露出来。

const TerrainVariants = preload("res://scripts/terrain_variants.gd")
const BuildingSkin = preload("res://scripts/building_skin.gd")
const GameState = preload("res://scripts/game_state.gd")
const EnemyTank = preload("res://scripts/enemy.gd")

const TANK_OVERLAYS := [
	"res://assets/sprites/tanks/tank_dmg_t1.png",
	"res://assets/sprites/tanks/tank_dmg_t2.png",
	"res://assets/sprites/tanks/tank_camo_a2.png",
	"res://assets/sprites/tanks/tank_camo_a3.png",
	"res://assets/sprites/tanks/tank_marking_v1.png",
	"res://assets/sprites/tanks/tank_marking_v2.png",
	"res://assets/sprites/tanks/tank_marking_v3.png",
]
const BUILDING_DAMAGE := [
	"res://assets/sprites/buildings/building_dmg_t1.png",
	"res://assets/sprites/buildings/building_dmg_t2.png",
]
const BUILDING_THEME := [
	"res://assets/sprites/buildings/building_theme_a2.png",
	"res://assets/sprites/buildings/building_theme_a3.png",
]

## 炮塔中心禁区。世界单位 0.46, 坦克画幅 ORTHO_SCALE_TANK = 3.6 铺满 256px,
## 所以 0.46 * (256 / 3.6) = 32.7px。取 30 留一点抗锯齿余量。
const TURRET_KEEPOUT_PX := 30.0
## 最大建筑 (fortified_wall) 的半宽 2.85/2 = 1.425 世界单位, 建筑画幅
## ORTHO_SCALE_DEFAULT = 3.3 铺满 256px, 所以 1.425 * (256/3.3) = 110.6px。
const BUILDING_HALF_PX := 110.0

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
	print(">>> ASSET VARIANTS TEST <<<")
	print("==================================================")
	_check_all_files_present()
	_check_variants_are_distinct()
	_check_variant_borders_match()
	_check_tank_overlay_keepout()
	_check_building_decal_reach()
	_check_damage_tiers_grow()
	_check_selector_deterministic()
	_check_selector_covers_all_variants()
	_check_theme_switches_art()
	_check_room_changes_layout()
	_check_building_skin_behaviour()
	_check_enemy_damage_tier_follows_health()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL ASSET VARIANT CHECKS PASSED! <<<")
		quit(0)


# ---------------------------------------------------------------- 工具

func _all_registered_paths() -> Array:
	var out: Array = []
	for kind in TerrainVariants.VARIANT_TABLE:
		for theme in TerrainVariants.VARIANT_TABLE[kind]:
			for f in TerrainVariants.VARIANT_TABLE[kind][theme]:
				var p: String = TerrainVariants.TILES + str(f)
				if not out.has(p):
					out.append(p)
	for kind in TerrainVariants.PROP_VARIANT_TABLE:
		for p in TerrainVariants.PROP_VARIANT_TABLE[kind]:
			if not out.has(p):
				out.append(str(p))
	for p in TANK_OVERLAYS + BUILDING_DAMAGE + BUILDING_THEME:
		if not out.has(p):
			out.append(p)
	return out


func _image_of(path: String) -> Image:
	var tex = load(path)
	if tex == null:
		return null
	return tex.get_image()


## 取四条边的像素 (按 alpha 合成到中灰底上, 同 qa_style_consistency 的口径)。
func _border_pixels(img: Image) -> PackedColorArray:
	var out := PackedColorArray()
	var w := img.get_width()
	var h := img.get_height()
	for x in range(w):
		out.append(img.get_pixel(x, 0))
		out.append(img.get_pixel(x, h - 1))
	for y in range(h):
		out.append(img.get_pixel(0, y))
		out.append(img.get_pixel(w - 1, y))
	return out


## 两组边缘像素的平均差 (0..255 口径)。alpha 参与合成 —— 透明处按中灰算,
## 这样"一边不透明一边透明"也会被算成差异, 而不是被当成 0。
func _border_delta(a: PackedColorArray, b: PackedColorArray) -> float:
	if a.size() != b.size() or a.size() == 0:
		return 999.0
	var total := 0.0
	for i in range(a.size()):
		var ca := a[i]
		var cb := b[i]
		for ch in 3:
			var va: float = ca[ch] * ca.a + 0.5 * (1.0 - ca.a)
			var vb: float = cb[ch] * cb.a + 0.5 * (1.0 - cb.a)
			total += absf(va - vb)
	return 255.0 * total / float(a.size() * 3)


## 覆盖面积 (%) —— 和 test_armor_plating.gd 用同一个量, 好横向比较。
func _coverage(img: Image) -> float:
	var solid := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.35:
				solid += 1
	return 100.0 * float(solid) / float(img.get_width() * img.get_height())


# ---------------------------------------------------------------- 1. 资产齐全

func _check_all_files_present() -> void:
	print("\n--- 1. 差分资产齐全且画幅正确 ---")
	var n := 0
	for p in _all_registered_paths():
		var img := _image_of(p)
		if img == null:
			fail("%s 加载不出来 —— 选择器会选到它, 结果是空贴图" % p)
			continue
		if img.get_width() != 256 or img.get_height() != 256:
			fail("%s 是 %dx%d, 不是 256x256 —— 多半是画幅/分辨率传错了, "
				% [p, img.get_width(), img.get_height()]
				+ "而渲染本身照样会'成功'")
			continue
		n += 1
	if failures == 0:
		ok("%d 张差分资产全部存在且为 256x256" % n)


# ---------------------------------------------------------------- 2. 互不相同

func _check_variants_are_distinct() -> void:
	print("\n--- 2. 同族变体的像素数据互不相同 ---")
	var families: Array = []
	for kind in TerrainVariants.VARIANT_TABLE:
		for theme in TerrainVariants.VARIANT_TABLE[kind]:
			var group: Array = []
			for f in TerrainVariants.VARIANT_TABLE[kind][theme]:
				group.append(TerrainVariants.TILES + str(f))
			families.append(["%s/a%d" % [kind, theme], group])
	for kind in TerrainVariants.PROP_VARIANT_TABLE:
		families.append([kind, TerrainVariants.PROP_VARIANT_TABLE[kind]])
	families.append(["tank_dmg", [TANK_OVERLAYS[0], TANK_OVERLAYS[1]]])
	families.append(["tank_camo", [TANK_OVERLAYS[2], TANK_OVERLAYS[3]]])
	families.append(["tank_marking", [TANK_OVERLAYS[4], TANK_OVERLAYS[5], TANK_OVERLAYS[6]]])
	families.append(["building_dmg", BUILDING_DAMAGE])
	families.append(["building_theme", BUILDING_THEME])

	var dupes := 0
	for entry in families:
		var label: String = entry[0]
		var paths: Array = entry[1]
		var datas: Array = []
		for p in paths:
			var img := _image_of(str(p))
			datas.append(img.get_data() if img else PackedByteArray())
		for i in range(datas.size()):
			for j in range(i + 1, datas.size()):
				if datas[i].size() > 0 and datas[i] == datas[j]:
					fail("%s: %s 和 %s 像素完全相同 —— 差分是假的。"
						% [label, str(paths[i]).get_file(), str(paths[j]).get_file()]
						+ " 多半是构建脚本里复制粘贴之后忘了改, 或者一张图被"
						+ "另一张覆盖了 (CLAUDE.md 记过三个文件同一个 md5 的事故)")
					dupes += 1
	if dupes == 0:
		ok("%d 组变体族内两两不同" % families.size())


# ---------------------------------------------------------------- 2b. 边缘一致

## 同族变体的**边缘**必须一致 —— 变体系统独有的失效模式。
##
## 每张瓦片自己铺开是无缝的 (那是 qa_style_consistency 的 tileseam 在管), 不
## 等于两张**不同变体**贴在一起也无缝。而同一张地图上相邻两格本来就可能抽到
## 不同变体, 所以真正要守的是: 一族里所有变体在四条边上逐像素一致。
##
## 这条以前只写在 build_terrain_variants.py 的注释里, 没有任何东西在检查它,
## 于是漏过了两类问题:
##   - 装饰件本身越过画幅边 (中心在界内, 但自身体积 + 35° 太阳的影子够了出去);
##   - 装饰件没越界, 但它的**间接光**越界了 —— 一整块贴着下边缘的暗砖让弹到
##     边缘砖缝上的光少了一截, 实测下边缘互差 6.97/255, 而左右只有 1.7~2.3。
##
## 阈值 4.0 的来历: 修完之后实测各族 0.08 ~ 2.65 (最高那个是 a1 的饱和绿苔藓
## 往奶白砖缝上的颜色渗染, 物理上真实且消不掉); 而 qa_style_consistency 判
## "肉眼可见接缝"的地板是 6.0。4.0 卡在两者中间, 抓得住新引入的越界, 又不会
## 被渲染噪声和残余渗染误伤。
const BORDER_MAX_DELTA := 4.0

func _check_variant_borders_match() -> void:
	print("\n--- 2b. 同族变体的边缘逐像素一致 (相邻格可能是不同变体) ---")
	var worst := 0.0
	var worst_label := ""
	var checked := 0
	for kind in TerrainVariants.VARIANT_TABLE:
		# trees 不参加 —— 它不是满幅瓦片。它没有底板, 四周透明, main.gd 把它
		# 当 z_index=10 的独立 Sprite2D 画在坦克*上面*, 从不和自己拼接。变体
		# 整体转个角度是合法的美术手段, 却必然改变靠近画幅边的树冠轮廓; 把它
		# 圈进来只会制造一条谁也不该遵守的约束。
		if kind == "trees":
			continue
		for theme in TerrainVariants.VARIANT_TABLE[kind]:
			var paths: Array = []
			for f in TerrainVariants.VARIANT_TABLE[kind][theme]:
				paths.append(TerrainVariants.TILES + str(f))
			var borders: Array = []
			for p in paths:
				var img := _image_of(str(p))
				borders.append(_border_pixels(img) if img else PackedColorArray())
			for i in range(borders.size()):
				for j in range(i + 1, borders.size()):
					var d := _border_delta(borders[i], borders[j])
					checked += 1
					if d > worst:
						worst = d
						worst_label = "%s/a%d: %s vs %s" % [
							kind, theme, str(paths[i]).get_file(), str(paths[j]).get_file()]
					if d > BORDER_MAX_DELTA:
						fail("%s/a%d: %s 与 %s 的边缘互差 %.2f (上限 %.1f) —— "
							% [kind, theme, str(paths[i]).get_file(),
							   str(paths[j]).get_file(), d, BORDER_MAX_DELTA]
							+ "这两个变体贴在一起会露出一道沿格子边的台阶。"
							+ "检查装饰件是否越过画幅边 (含自身体积与 35° 太阳的"
							+ "影长), 或者有大面积暗/饱和色块贴着边缘改变了间接光")

	# 自检: 这个度量必须真的分得出边缘不同的两张图, 否则上面全绿也说明不了
	# 任何事。拿两个**不同主题**的砖去比 —— 它们配色不同, 边缘理应差很多。
	var a1 := _image_of(TerrainVariants.TILES + "tile_brick.png")
	var a2 := _image_of(TerrainVariants.TILES + "tile_brick_a2.png")
	if a1 and a2:
		var cross := _border_delta(_border_pixels(a1), _border_pixels(a2))
		if cross <= BORDER_MAX_DELTA:
			fail("自检失败: 两个不同主题的砖 (tile_brick vs tile_brick_a2) "
				+ "边缘互差只有 %.2f, 没有超过 %.1f —— " % [cross, BORDER_MAX_DELTA]
				+ "说明这个度量根本分不出边缘差异, 上面的全绿是假的")
		else:
			ok("自检: 跨主题对照差 %.2f, 远大于阈值 %.1f, 度量有效"
				% [cross, BORDER_MAX_DELTA])
	if worst <= BORDER_MAX_DELTA:
		ok("%d 对变体边缘一致, 最差 %.2f (%s)" % [checked, worst, worst_label])


# ---------------------------------------------------------------- 3. 炮塔禁区

func _check_tank_overlay_keepout() -> void:
	print("\n--- 3. 坦克叠加层不侵入炮塔中心 ---")
	var bad := 0
	for p in TANK_OVERLAYS:
		var img := _image_of(p)
		if img == null:
			continue
		var inside := 0
		var total := 0
		var cx := img.get_width() * 0.5 - 0.5
		var cy := img.get_height() * 0.5 - 0.5
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var d := Vector2(x - cx, y - cy).length()
				if d >= TURRET_KEEPOUT_PX:
					continue
				total += 1
				if img.get_pixel(x, y).a > 0.35:
					inside += 1
		var pct := 100.0 * float(inside) / float(maxi(total, 1))
		if pct > 0.5:
			fail("%s 有 %.2f%% 的像素落在炮塔禁区 (r<%.0fpx) —— "
				% [p.get_file(), pct, TURRET_KEEPOUT_PX]
				+ "叠加层无条件画在车体之上, 会糊住炮塔和炮管, "
				+ "玩家读不出这辆车朝哪、是什么车")
			bad += 1
	if bad == 0:
		ok("%d 张坦克叠加层全部避开炮塔中心" % TANK_OVERLAYS.size())


# ---------------------------------------------------------------- 4. 贴花铺得够远

func _check_building_decal_reach() -> void:
	print("\n--- 4. 建筑贴花铺到最大建筑半宽以外 ---")
	# 覆盖层要求严 (30%): 它是"落了一层沙/雪", 边缘露出来就是一条弧线横在墙上。
	# 战损贴花要求松 (3%): 裂纹本来就是稀疏的, 稀疏不等于露边。
	for entry in [[BUILDING_THEME, 30.0, "战区覆盖层"], [BUILDING_DAMAGE, 3.0, "战损贴花"]]:
		var paths: Array = entry[0]
		var need: float = entry[1]
		var label: String = entry[2]
		for p in paths:
			var img := _image_of(str(p))
			if img == null:
				continue
			var solid := 0
			var total := 0
			var cx := img.get_width() * 0.5 - 0.5
			var cy := img.get_height() * 0.5 - 0.5
			for y in range(img.get_height()):
				for x in range(img.get_width()):
					var d := Vector2(x - cx, y - cy).length()
					if d < BUILDING_HALF_PX or d > 127.0:
						continue
					total += 1
					if img.get_pixel(x, y).a > 0.35:
						solid += 1
			var pct := 100.0 * float(solid) / float(maxi(total, 1))
			if pct < need:
				fail("%s %s 在 r>%.0fpx 的外环只有 %.1f%% (需要 >%.0f%%) —— "
					% [label, str(p).get_file(), BUILDING_HALF_PX, pct, need]
					+ "贴到最大的建筑上会露出贴花自己的边缘")
			else:
				ok("%s %s 外环覆盖 %.1f%%" % [label, str(p).get_file(), pct])


# ---------------------------------------------------------------- 5. 战损递增

func _check_damage_tiers_grow() -> void:
	print("\n--- 5. 战损两档覆盖面积严格递增 ---")
	for entry in [[TANK_OVERLAYS[0], TANK_OVERLAYS[1], "坦克"],
				  [BUILDING_DAMAGE[0], BUILDING_DAMAGE[1], "建筑"]]:
		var a := _image_of(str(entry[0]))
		var b := _image_of(str(entry[1]))
		if a == null or b == null:
			continue
		var ca := _coverage(a)
		var cb := _coverage(b)
		if cb <= ca:
			fail("%s战损 t2 (%.2f%%) 没有比 t1 (%.2f%%) 更大 —— "
				% [entry[2], cb, ca]
				+ "48px 下唯一可靠的信号就是覆盖面积, 两档一样大等于只有一档")
		else:
			ok("%s战损 t1 %.2f%% -> t2 %.2f%%" % [entry[2], ca, cb])


# ---------------------------------------------------------------- 6. 选择器确定性

func _check_selector_deterministic() -> void:
	print("\n--- 6. 选择器确定性 (同一房间重进, 墙长得一样) ---")
	GameState.current_act = 1
	GameState.current_room = "4,5"
	GameState.run_seed = 987654
	var first: Array = []
	for r in range(13):
		for c in range(13):
			first.append(TerrainVariants.path_for("brick", Vector2i(c, r)))
	var same := true
	for i in range(3):
		var k := 0
		for r in range(13):
			for c in range(13):
				if TerrainVariants.path_for("brick", Vector2i(c, r)) != first[k]:
					same = false
				k += 1
	if same:
		ok("同一 (房间, run_seed) 下 169 格连查 4 遍结果一致")
	else:
		fail("选择器不确定 —— 同一个房间反复进出, 墙面贴图会闪。"
			+ "多半是有人在 TerrainVariants 里引入了 randi()")


func _check_selector_covers_all_variants() -> void:
	print("\n--- 6b. 选择器覆盖得到全部变体, 且权重大致成立 ---")
	GameState.current_act = 1
	GameState.current_room = "2,3"
	GameState.run_seed = 424242
	var counts := {0: 0, 1: 0, 2: 0}
	# 单个房间只有 169 格, 样本太小时分布判断没意义; 这里横跨多个房间取样,
	# 每个房间都是玩家真的会走进去的那种规模。
	for room_i in range(40):
		GameState.current_room = "%d,%d" % [room_i % 9, room_i / 9]
		for r in range(13):
			for c in range(13):
				counts[TerrainVariants.variant_index("brick", Vector2i(c, r), 3)] += 1
	var total: int = counts[0] + counts[1] + counts[2]
	for i in range(3):
		if counts[i] == 0:
			fail("变体 %d 一次都没被选到 —— 渲了一张永远用不上的图" % i)
	var p0 := 100.0 * float(counts[0]) / float(total)
	var p1 := 100.0 * float(counts[1]) / float(total)
	var p2 := 100.0 * float(counts[2]) / float(total)
	# 期望 50/25/25。容差给到 ±6 个百分点 —— 抓的是"权重表被改坏了"或者
	# "哈希退化成常数", 不是统计涨落 (样本 6760 格, 标准差不到 0.7 个点)。
	if absf(p0 - 50.0) > 6.0 or absf(p1 - 25.0) > 6.0 or absf(p2 - 25.0) > 6.0:
		fail("变体分布 %.1f/%.1f/%.1f 偏离权重 50/25/25 太多 —— "
			% [p0, p1, p2]
			+ "要么 VARIANT_WEIGHTS 被改坏了, 要么哈希退化了")
	else:
		ok("变体分布 %.1f%% / %.1f%% / %.1f%% (期望 50/25/25, 样本 %d)"
			% [p0, p1, p2, total])


func _check_theme_switches_art() -> void:
	print("\n--- 6c. 换幕真的换图 ---")
	GameState.current_room = "1,1"
	GameState.run_seed = 5150
	var cell := Vector2i(6, 6)
	var by_act := {}
	for act in [1, 2, 3]:
		GameState.current_act = act
		by_act[act] = TerrainVariants.path_for("brick", cell)
	if by_act[1] == by_act[2] or by_act[2] == by_act[3] or by_act[1] == by_act[3]:
		fail("砖块三幕选到了重复的图: %s / %s / %s —— 主题差分没生效"
			% [str(by_act[1]).get_file(), str(by_act[2]).get_file(), str(by_act[3]).get_file()])
	else:
		ok("砖块三幕分别是 %s / %s / %s"
			% [str(by_act[1]).get_file(), str(by_act[2]).get_file(), str(by_act[3]).get_file()])

	# 沙和树**故意**没有主题差分 (它们本身就是主题地形), 三幕同图是对的。
	# 断言这一条是为了让以后有人给它们加主题时, 这里会红, 提醒他连带更新注释。
	GameState.current_act = 1
	var sand1 := TerrainVariants.path_for("sand", cell)
	GameState.current_act = 3
	var sand3 := TerrainVariants.path_for("sand", cell)
	if sand1 != sand3:
		fail("沙地在第 1/3 幕选到了不同的图 —— 现在的设计是沙/树没有主题差分"
			+ " (它们本身就是主题地形), 如果这是有意加的, 记得更新"
			+ " TerrainVariants 的类注释和本测试")
	else:
		ok("沙/树三幕同图 (按设计: 它们本身就是主题地形)")


func _check_room_changes_layout() -> void:
	print("\n--- 6d. 换房间真的换排布 ---")
	GameState.current_act = 1
	GameState.run_seed = 31337
	GameState.current_room = "0,0"
	var a: Array = []
	for r in range(13):
		for c in range(13):
			a.append(TerrainVariants.variant_index("brick", Vector2i(c, r), 3))
	GameState.current_room = "7,2"
	var diff := 0
	var k := 0
	for r in range(13):
		for c in range(13):
			if TerrainVariants.variant_index("brick", Vector2i(c, r), 3) != a[k]:
				diff += 1
			k += 1
	# 两个独立的 3 选 1 有约 1/3 概率撞上, 所以期望差异率约 62%。
	# 阈值 40% 只抓"房间键根本没混进哈希"这种退化 (那会是 0%)。
	var pct := 100.0 * float(diff) / 169.0
	if pct < 40.0:
		fail("换房间后只有 %.0f%% 的格子换了变体 —— current_room 大概没有真的"
			% pct + "混进哈希, 结果是每个房间的同一格永远是同一张图")
	else:
		ok("换房间后 %.0f%% 的格子换了变体" % pct)


# ---------------------------------------------------------------- 7. BuildingSkin

func _check_building_skin_behaviour() -> void:
	print("\n--- 7. BuildingSkin: 裁剪 / region / 档位随血量 ---")
	var stub_script = load("res://tools/_building_stub.gd")
	if stub_script == null:
		fail("tools/_building_stub.gd 加载不出来")
		return
	GameState.current_act = 3   # 第 3 幕 -> 应该挂上积雪覆盖层

	var stub = stub_script.new()
	root.add_child(stub)
	var skin = BuildingSkin.attach(stub)
	if skin == null:
		fail("BuildingSkin.attach() 返回 null —— 找不到 Sprite2D?")
		stub.queue_free()
		return

	if stub.sprite.clip_children != CanvasItem.CLIP_CHILDREN_AND_DRAW:
		fail("没有设 clip_children —— 通用贴花会飘在建筑轮廓外面, "
			+ "读起来是'地上多了几道裂纹'而不是'这座建筑裂了'")
	else:
		ok("clip_children = CLIP_CHILDREN_AND_DRAW")

	# region 必须抄过去, 否则被 region 切成四块的建筑 (fortified_wall)
	# 每一块都会贴上一整张完整贴花。
	var themed: Sprite2D = null
	for ch in stub.sprite.get_children():
		if ch is Sprite2D:
			themed = ch
	if themed == null:
		fail("第 3 幕没有挂上战区覆盖层")
	elif not themed.region_enabled or themed.region_rect != stub.sprite.region_rect:
		fail("覆盖层没有抄父 Sprite2D 的 region (%s vs %s) —— "
			% [str(themed.region_rect), str(stub.sprite.region_rect)]
			+ "被 region 切块的建筑会四块各贴一整张")
	else:
		ok("战区覆盖层已挂, 且抄了 region_rect %s" % str(themed.region_rect))

	# 档位随血量走
	var seen: Array = []
	for hp in [6, 3, 1]:
		stub.current_health = hp
		skin._refresh()
		seen.append(skin._tier)
	if seen != [0, 1, 2]:
		fail("战损档位随血量的变化是 %s, 期望 [0, 1, 2] "
			% str(seen) + "(满血 / 50% / 17%)")
	else:
		ok("战损档位 6->0, 3->1, 1->2 血")

	stub.queue_free()


# ---------------------------------------------------------------- 8. 敌人战损

func _check_enemy_damage_tier_follows_health() -> void:
	print("\n--- 8. 敌人战损档位随血量, 且伪装时不外露 ---")
	var scene = load("res://scenes/enemy.tscn")
	if scene == null:
		fail("enemy.tscn 加载不出来")
		return
	var e = scene.instantiate()
	root.add_child(e)

	# 直接摆血量, 不走 _setup_tank_type() —— 这里测的是"档位跟着血量走"这条
	# 映射, 不该被车种表和楼层缩放牵着走。
	e.max_health = 10
	e.damage_tier = 0
	var seen: Array = []
	for hp in [10, 5, 2]:
		e.health = hp
		e._update_damage_overlay()
		seen.append(e.damage_tier)
	if seen != [0, 1, 2]:
		fail("敌人战损档位随血量的变化是 %s, 期望 [0, 1, 2]" % str(seen))
	else:
		ok("敌人战损档位 10->0, 5->1, 2->2 血")

	# 伪装中的 MIRAGE 不能顶着战损贴花站在树丛里 —— 那等于自曝位置。
	e.is_camouflaged = true
	e.damage_tier = 0
	e.health = 2
	e._update_damage_overlay()
	if e.damage_sprite != null and e.damage_sprite.visible:
		fail("伪装状态下战损贴花仍然可见 —— 潜行单位自曝位置 "
			+ "(同样的理由见 main.gd::_update_tree_transparency 跳过伪装 MIRAGE)")
	else:
		ok("伪装状态下战损贴花不显示")

	# 1 血的车没有中间态, 不该挂贴花
	e.is_camouflaged = false
	e.max_health = 1
	e.damage_tier = 0
	if e.damage_sprite:
		e.damage_sprite.queue_free()
		e.damage_sprite = null
	e.health = 1
	e._update_damage_overlay()
	if e.damage_sprite != null:
		fail("max_health=1 的车挂上了战损贴花 —— 它挨一下就死, 贴花永远不会显示")
	else:
		ok("max_health=1 的车不挂战损贴花")

	e.queue_free()
