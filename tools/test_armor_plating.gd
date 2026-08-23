extends SceneTree

## 装甲板系统的闸门 —— 锁的是"敌人的强弱必须是整数, 而且必须看得出来"。
##
## 这条不是口味问题, 是这个游戏的类型决定的。坦克大战里装甲车要打四下, 而且
## 它**长得不一样**; 之前的做法是 max_health = ceil(base * (1 + floor * 0.08)),
## 一个隐藏的连续乘数 —— floor 12 的 enemy_basic 有 3 血, 和 floor 0 那只 1 血
## 的长得一模一样, 玩家开两枪没打死, 除了"这游戏在偷偷加数值"读不出任何东西。
##
## 现在血量 = 车种基础血 + 装甲层数 x ARMOR_PLATE_HP, 每一层都有对应的贴图。
## 下面五条把这个约定钉住:
##
##   1. 三张装甲贴图存在, 且**覆盖面积逐级严格变大**。覆盖面积是唯一在 48px
##      显示尺寸下仍然可靠的信号 (世界精灵是 256px 画的, 按 TILE_SCALE 0.1875
##      缩到 48px, 细节全糊掉, 剩下的只有轮廓大小)。
##   2. 逐级压暗。第二重读数, 而且刻意用明度不用色相 —— 金/黄是敌人**车种**的
##      视觉词汇 (见 CLAUDE.md 里 tile_steel 那段), 装甲档位不能来抢这个通道。
##   3. 装甲层数永远不超过 MAX_ARMOR_PLATES。超了就意味着有血量却没有对应外观,
##      等于偷偷退回成隐藏数值。
##   4. 血量增量必须是 ARMOR_PLATE_HP 的整数倍。任何人往回加一个 ceil(x * 1.08)
##      都会在这里露馅。
##   5. floor 0 的常规战里, BASIC 就是 1 血。"杂兵一发一个"是坦克大战的底子,
##      不能被楼层缩放悄悄吃掉。

const EnemyTank = preload("res://scripts/enemy.gd")
const GameState = preload("res://scripts/game_state.gd")

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
	print(">>> ARMOR PLATING TEST <<<")
	print("==================================================")
	_check_sprites()
	_check_plate_range_capped()
	_check_health_is_integer_steps()
	_check_floor0_trash_dies_in_one_shot()
	_check_plate_actually_shows()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL ARMOR PLATING CHECKS PASSED! <<<")
		quit(0)


## 覆盖面积 = alpha > 0.35 的像素占比; 亮度 = 那些像素的平均 RGB。
func _measure(path: String) -> Dictionary:
	var tex = load(path)
	if tex == null:
		return {}
	var img: Image = tex.get_image()
	if img == null:
		return {}
	var w := img.get_width()
	var h := img.get_height()
	var solid := 0
	var lum := 0.0
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a > 0.35:
				solid += 1
				lum += (c.r + c.g + c.b) / 3.0
	if solid == 0:
		return {"cover": 0.0, "lum": 0.0}
	return {
		"cover": 100.0 * float(solid) / float(w * h),
		# Color 的通道是 0..1 的浮点; 换算成 0..255 只是为了打印时好读,
		# 比较用的还是同一个量。
		"lum": 255.0 * lum / float(solid),
	}


func _check_sprites() -> void:
	print("\n--- 三档装甲: 覆盖面积递增, 明度递减 ---")
	var covers: Array[float] = []
	var lums: Array[float] = []
	for t in range(1, EnemyTank.MAX_ARMOR_PLATES + 1):
		var p := "res://assets/sprites/tanks/enemy_plate_t%d.png" % t
		var m := _measure(p)
		if m.is_empty():
			fail("装甲贴图 %s 读不出来 —— 有装甲层数却没有对应外观, "
				% p + "等于把强弱又变回了隐藏数值")
			return
		covers.append(float(m["cover"]))
		lums.append(float(m["lum"]))

	var cov_up := true
	for i in range(1, covers.size()):
		if covers[i] <= covers[i - 1]:
			cov_up = false
	if cov_up:
		ok("覆盖面积逐级变大: %.2f%% -> %.2f%% -> %.2f%%" % [covers[0], covers[1], covers[2]])
	else:
		fail("覆盖面积没有逐级变大 (%.2f / %.2f / %.2f) —— 缩到 48px 之后玩家"
			% [covers[0], covers[1], covers[2]]
			+ "唯一还能读到的就是轮廓大小, 这条塌了三档就分不出来了")

	var lum_down := true
	for i in range(1, lums.size()):
		if lums[i] >= lums[i - 1]:
			lum_down = false
	if lum_down:
		ok("明度逐级压暗: %.0f -> %.0f -> %.0f" % [lums[0], lums[1], lums[2]])
	else:
		fail("明度没有逐级压暗 (%.0f / %.0f / %.0f) —— 这是覆盖面积之外的第二重读数"
			% [lums[0], lums[1], lums[2]])


func _check_plate_range_capped() -> void:
	print("\n--- 装甲层数不得超过 MAX_ARMOR_PLATES (=%d) ---" % EnemyTank.MAX_ARMOR_PLATES)
	var worst := 0
	var worst_at := ""
	for cycle in range(3):
		for f in range(GameState.max_floors):
			for bt in ["battle", "elite", "boss", "challenge"]:
				var r: Vector2i = EnemyTank.armor_plate_range(f, bt, cycle)
				if r.x < 0 or r.x > r.y:
					fail("floor %d / %s / 圈 %d 的上下界不合法: %s" % [f, bt, cycle, str(r)])
					return
				if r.y > worst:
					worst = r.y
					worst_at = "floor %d / %s / 圈 %d" % [f, bt, cycle]
	if worst <= EnemyTank.MAX_ARMOR_PLATES:
		ok("全部 (楼层 x 战斗类型 x 难度圈) 组合的上界都 <= %d (最高出现在 %s)"
			% [EnemyTank.MAX_ARMOR_PLATES, worst_at])
	else:
		fail("最高装甲层数 %d 超过了有贴图的 %d 层 (%s) —— 多出来的血量没有外观"
			% [worst, EnemyTank.MAX_ARMOR_PLATES, worst_at])


## 血量增量必须整除 ARMOR_PLATE_HP。这一条专门挡"有人又加了一个乘数"。
func _check_health_is_integer_steps() -> void:
	print("\n--- 血量增量是 %d 的整数倍 (没有乘数, 没有 ceil) ---" % EnemyTank.ARMOR_PLATE_HP)
	var scn: PackedScene = load("res://scenes/enemy.tscn")
	# 基础血用 floor 0 常规战量出来 —— 那里上下界都是 0, 拿到的就是车种基础值。
	# 不在测试里手抄一份基础血表: 抄的表必然和 _setup_tank_type() 发散。
	GameState.reset_campaign(1)
	GameState.current_act = 1
	GameState.current_floor = 0
	GameState.battle_type = "battle"

	var base: Dictionary = {}
	for tname in EnemyTank.EnemyType.keys():
		var t: int = EnemyTank.EnemyType[tname]
		var e = scn.instantiate()
		e.enemy_type = t
		root.add_child(e)
		base[t] = int(e.max_health)
		e.free()

	var bad: Array[String] = []
	var seen_plated := 0
	for f in [4, 8, 12, 14]:
		for bt in ["battle", "elite", "boss"]:
			GameState.current_floor = f
			GameState.battle_type = bt
			for tname in EnemyTank.EnemyType.keys():
				var t: int = EnemyTank.EnemyType[tname]
				var e = scn.instantiate()
				e.enemy_type = t
				root.add_child(e)
				var delta: int = int(e.max_health) - int(base[t])
				var plates: int = int(e.armor_plates)
				e.free()
				if delta != plates * EnemyTank.ARMOR_PLATE_HP:
					bad.append("%s@f%d/%s: +%d 血却是 %d 层装甲" % [tname, f, bt, delta, plates])
				if plates > 0:
					seen_plated += 1
	if bad.is_empty():
		ok("扫过的所有 (车种 x 楼层 x 战斗类型) 血量都等于 基础血 + 层数x%d (其中 %d 例带装甲)"
			% [EnemyTank.ARMOR_PLATE_HP, seen_plated])
	else:
		fail("这些样本的血量对不上装甲层数, 说明血量上还挂着别的缩放: %s"
			% ", ".join(bad.slice(0, 5)))


## 前面几条都只查数据。这一条查**实机上真的挂上去了** —— 层数算对了但贴图
## 没挂上, 从玩家角度和隐藏数值毫无区别, 而且不会报任何错。
func _check_plate_actually_shows() -> void:
	print("\n--- 带装甲的车身上真的有装甲贴图 ---")
	var scn: PackedScene = load("res://scenes/enemy.tscn")
	GameState.reset_campaign(1)
	GameState.current_act = 1
	GameState.current_floor = GameState.max_floors - 1
	GameState.battle_type = "boss" # 下界 2, 保证每辆都带甲

	var checked := 0
	var missing := 0
	for i in range(20):
		var e = scn.instantiate()
		e.enemy_type = EnemyTank.EnemyType.BASIC
		root.add_child(e)
		var plates := int(e.armor_plates)
		var has_visual: bool = e.plate_sprite != null \
			and is_instance_valid(e.plate_sprite) \
			and e.plate_sprite.texture != null
		# 挂成 sprite 的子节点是有意的: 缩放/旋转/后坐力/受击挤压全部自动跟随,
		# 不需要每帧同步坐标 —— 那正是这个项目踩过好几次的坑。
		var parented_to_sprite: bool = has_visual and e.plate_sprite.get_parent() == e.sprite
		e.free()
		if plates <= 0:
			continue
		checked += 1
		if not has_visual or not parented_to_sprite:
			missing += 1
	if checked == 0:
		fail("boss 层一辆带装甲的车都没摇出来 —— armor_plate_range 的下界是不是没生效")
	elif missing == 0:
		ok("%d 辆带装甲的车全部挂上了装甲贴图, 且都是 Sprite2D 的子节点" % checked)
	else:
		fail("%d/%d 辆车有装甲层数却没有贴图 —— 玩家看到的就是隐藏数值"
			% [missing, checked])


func _check_floor0_trash_dies_in_one_shot() -> void:
	print("\n--- floor 0 的常规战: 杂兵还是一发一个 ---")
	var scn: PackedScene = load("res://scenes/enemy.tscn")
	GameState.reset_campaign(1)
	GameState.current_act = 1
	GameState.current_floor = 0
	GameState.battle_type = "battle"

	var bad: Array[String] = []
	for i in range(40):
		for tname in ["BASIC", "FAST"]:
			var e = scn.instantiate()
			e.enemy_type = EnemyTank.EnemyType[tname]
			root.add_child(e)
			var hp := int(e.max_health)
			var plates := int(e.armor_plates)
			e.free()
			if hp != 1 or plates != 0:
				bad.append("%s 有 %d 血 / %d 层装甲" % [tname, hp, plates])
	if bad.is_empty():
		ok("floor 0 的 BASIC/FAST 恒定 1 血 0 装甲 (40 次采样)")
	else:
		fail("floor 0 的杂兵不再是一发一个: %s —— 这是坦克大战的底子, "
			% bad[0] + "第一层就收走的话玩家读到的是'炮哑了'而不是'变难了'")
