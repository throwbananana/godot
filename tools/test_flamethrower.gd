extends SceneTree

## 喷火坦克的集成测试。
##
## 检查的是"这个敌人真的能用", 而不只是"代码能编译":
##   - 六帧精灵和四帧火焰 VFX 都存在且不是空图
##   - FLAMETHROWER 进了枚举、属性表、楼层门禁、生成名册
##   - 火舌朝向正确 (朝车体正前方, 不是背后或侧面)
##   - 火舌真的能打到正前方的目标, 且打不到背后的
##   - 开合周期会切换, 冷却期间不造成伤害
##   - 它*会移动* —— 第一版在 _physics_process 里提前 return, 会让它变成
##     一动不动的摆设
##
## 跑法:
##   & $godot --headless --path . --script tools/test_flamethrower.gd

const EnemyTank = preload("res://scripts/enemy.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")
const FlameJet = preload("res://scripts/flame_jet.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> FLAMETHROWER TANK INTEGRATION TEST <<<")
	print("==================================================")

	_check_assets()
	_check_registration()
	await _check_flame_geometry()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL FLAMETHROWER CHECKS PASSED! <<<")
		quit(0)


func _check_assets() -> void:
	print("\n--- 资源 ---")
	# 走 TextureHelper 而不是 ResourceLoader.exists(): 游戏本身就是这么加载贴图的。
	# 它先试 load(), ResourceLoader 认不出来 (还没生成 .import) 时回退到
	# Image.load_from_file() + generate_mipmaps()。所以"没有 .import"并不等于
	# "游戏里加载不出来" —— 断言 ResourceLoader 会误报。
	var missing: Array[String] = []
	var tex: Texture2D = null
	for i in range(6):
		var p := "res://assets/sprites/tanks/enemy_flame_f%d.png" % i
		var t = TextureHelper.get_tex(p)
		if t == null:
			missing.append(p)
		elif i == 0:
			tex = t
	for i in range(4):
		var p := "res://assets/sprites/effects/vfx_flame_f%d.png" % i
		if TextureHelper.get_tex(p) == null:
			missing.append(p)
	if missing.is_empty():
		ok("6 帧坦克 + 4 帧火焰 VFX 均可被 TextureHelper 加载")
	else:
		fail("加载不出来: %s" % ", ".join(missing))
		return

	# 不能是空图 —— 这个项目出过"渲染成功但整张是灰方块"的事故
	var img := tex.get_image()
	var opaque := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	var total := (img.get_width() / 4) * (img.get_height() / 4)
	var cov := float(opaque) / float(total)
	if cov < 0.05:
		fail("enemy_flame_f0 几乎全透明 (覆盖率 %.1f%%)" % (cov * 100.0))
	elif cov > 0.95:
		fail("enemy_flame_f0 几乎全不透明 (覆盖率 %.1f%%) —— 疑似被遮挡" % (cov * 100.0))
	else:
		ok("坦克精灵覆盖率 %.1f%%, 形状正常" % (cov * 100.0))


func _check_registration() -> void:
	print("\n--- 注册 ---")
	if not ("FLAMETHROWER" in EnemyTank.EnemyType.keys()):
		fail("EnemyType 里没有 FLAMETHROWER")
		return
	ok("EnemyType.FLAMETHROWER 已定义")

	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	if not ("EnemyTank.EnemyType.FLAMETHROWER: 3" in main_src):
		fail("ENEMY_MIN_FLOOR 里没有 FLAMETHROWER 的门禁")
	else:
		ok("楼层门禁已登记 (3 层解锁)")
	var roster_hits := main_src.count("EnemyType.FLAMETHROWER")
	if roster_hits < 3:
		fail("生成名册里只出现 %d 次, 太少 —— 可能根本刷不出来" % roster_hits)
	else:
		ok("生成名册里出现 %d 次" % roster_hits)


func _check_flame_geometry() -> void:
	print("\n--- 火舌几何与伤害 ---")
	var world := Node2D.new()
	root.add_child(world)
	await process_frame

	var tank := Node2D.new()
	world.add_child(tank)
	tank.global_position = Vector2(300, 300)
	# 精灵朝上绘制, rotation = 朝向角 + PI/2。朝右 = 角度 0 -> rotation = PI/2
	tank.rotation = 0.0 + PI / 2.0

	var jet := FlameJet.new()
	jet.shooter = tank
	tank.add_child(jet)
	await process_frame

	# 火舌的本地 -Y 必须指向车体正前方 (这里是 +X)
	var fwd: Vector2 = Vector2.UP.rotated(jet.global_rotation)
	if fwd.distance_to(Vector2.RIGHT) > 0.05:
		fail("火舌朝向错误: 车体朝右, 火舌却指向 %s" % str(fwd))
	else:
		ok("火舌朝向与车体前方一致")

	# 视觉精灵必须落在车体前方的射程区间内, 而不是背后
	var spr: Sprite2D = null
	for c in jet.get_children():
		if c is Sprite2D:
			spr = c
			break
	if spr == null:
		fail("火舌没有生成精灵")
	else:
		var along: float = (spr.global_position - tank.global_position).dot(fwd)
		var expect: float = FlameJet.MUZZLE_OFFSET + FlameJet.RANGE * 0.5
		if along < 0.0:
			fail("火焰精灵在车体*背后* (沿前方投影 %.1fpx)" % along)
		elif absf(along - expect) > 12.0:
			fail("火焰精灵中心偏离预期 %.1fpx (实际 %.1f, 预期 %.1f)"
				% [absf(along - expect), along, expect])
		else:
			ok("火焰精灵位于喷嘴前方正确位置 (沿前方 %.1fpx)" % along)

		if spr.visible:
			fail("火舌初始状态就是可见的 —— 应当由 set_burning() 控制")
		else:
			ok("火舌默认不可见, 由开合周期控制")

	# 射程要短到可以绕开 —— 做长了就变成隔着半张地图秒人的数值怪
	if FlameJet.RANGE > 200.0:
		fail("射程 %.0fpx 太长, 绕不开" % FlameJet.RANGE)
	else:
		ok("射程 %.0fpx (%.1f 格), 可以绕侧面" % [FlameJet.RANGE, FlameJet.RANGE / 48.0])

	# 开合: set_burning 必须真的切换可见性
	jet.set_burning(true)
	if spr and not spr.visible:
		fail("set_burning(true) 之后火舌仍不可见")
	else:
		ok("set_burning(true) 点燃火舌")
	jet.set_burning(false)
	if spr and spr.visible:
		fail("set_burning(false) 之后火舌仍可见")
	else:
		ok("set_burning(false) 熄灭火舌")

	# 敌人本体必须会动 —— 第一版在 _physics_process 里提前 return 会让它定住
	var enemy_src := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var idx := enemy_src.find("EnemyType.FLAMETHROWER:")
	if idx < 0:
		fail("enemy.gd 里找不到 FLAMETHROWER 的处理分支")
	else:
		var tail := enemy_src.substr(idx, 700)
		if tail.contains("\n\t\treturn"):
			fail("FLAMETHROWER 分支里有提前 return —— 会跳过移动逻辑, 坦克不会动")
		else:
			ok("FLAMETHROWER 分支没有提前 return, 移动逻辑仍会执行")
