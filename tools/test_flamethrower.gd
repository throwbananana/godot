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
##   - 以上都会在*真实战场*里再验一遍 (_check_battle_runtime): 前面的检查是
##     在裸 Node2D 上做的, 证明不了它在 main.tscn 里刷得出来、动得了、
##     打得到人。尤其"会移动"那条, 静态检查只是在源码里搜 return 字符串,
##     换个写法就绕过去了 —— 实战段是真的跑物理帧量位移。
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
	await _check_battle_runtime()

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

	world.queue_free()


func _tick(n: int) -> void:
	for i in range(n):
		await physics_frame


## 清掉战场上除 keep 之外的一切能造成伤害的东西, 并把刷兵停掉。
##
## 后面要验的是"这一下掉血是不是火烧的", 而战场本身一直在制造别的掉血理由:
## 别的敌人会开枪、已经在飞的子弹会在几十帧后才命中、SpawnStar 倒计时结束还会
## 再变出一辆坦克来。这些都正好落在检查窗口里。
##
## enemies_alive 卡在 4 是一石二鸟: 刷兵的门是 `enemies_alive < 4`,
## 胜利的门是 `enemies_alive <= 0` —— 一个值同时把两扇门都关上了, 既不会
## 再刷兵, 也不会因为场上被清空而判定通关直接换场景。
## 不动玩家、鹰巢和地形 —— 干掉鹰巢会直接触发 game over 换场景。
func _purge_hazards(main: Node, keep: Node) -> void:
	main.enemies_alive = 4
	for c in main.actors_container.get_children():
		if c == keep:
			continue
		if ("enemy_type" in c) or c.is_in_group("bullet") or c.is_in_group("bullets") \
				or c.name.begins_with("SpawnStar"):
			c.free()


## 在真实的 main.tscn 里把喷火兵刷出来跑起来。
##
## 上面那些检查都是在裸 Node2D 上做的 —— 能证明 FlameJet 这个类自己是对的,
## 但证明不了它装到敌人身上、放进战场以后还成立。这一段验的是集成:
## 刷得出来、动得了、会开合、打得到玩家、打不到友军。
func _check_battle_runtime() -> void:
	print("\n--- 实战场景 (main.tscn) ---")
	var scene = load("res://scenes/main.tscn")
	if scene == null:
		fail("main.tscn 加载失败")
		return
	var main = scene.instantiate()
	root.add_child(main)
	await _tick(3)

	main._instantiate_enemy(Vector2(200, 200), EnemyTank.EnemyType.FLAMETHROWER, false, 0)
	var foe: Node = null
	for c in main.actors_container.get_children():
		if "enemy_type" in c and c.enemy_type == EnemyTank.EnemyType.FLAMETHROWER:
			foe = c
			break
	if foe == null:
		fail("FLAMETHROWER 在 main.tscn 里没能实例化出来")
		main.queue_free()
		return
	ok("在战场里成功刷出 FLAMETHROWER")

	# 挪到一块空地上, 否则它可能被生成在墙里, 位移检查会假阴性。
	# get_random_empty_tile_position() 返回的是*全局*坐标 (见 CLAUDE.md 坐标系一节)
	foe.global_position = main.get_random_empty_tile_position()
	await _tick(2)

	if foe.flame_jet == null or not is_instance_valid(foe.flame_jet):
		fail("敌人身上没有挂 flame_jet 子节点")
		main.queue_free()
		return
	if not foe.flame_jet.is_inside_tree():
		fail("flame_jet 不在场景树里, 不会收到 _physics_process")
		main.queue_free()
		return
	ok("flame_jet 已挂在敌人身上并进入场景树")

	# --- 会不会动 (动态版, 不靠搜源码字符串) ---
	var p0: Vector2 = foe.global_position
	await _tick(60)
	if not is_instance_valid(foe):
		fail("跑了 60 物理帧之后喷火兵已经不存在了")
		main.queue_free()
		return
	var moved: float = foe.global_position.distance_to(p0)
	if moved < 2.0:
		fail("1 秒内只移动了 %.2fpx —— 它是个不会动的摆设" % moved)
	else:
		ok("1 秒内移动 %.1fpx, 确实在跑" % moved)

	# --- 开合周期真的会被 enemy.gd 的 _physics_process 驱动 ---
	var was_on: bool = foe.flame_is_on
	foe.flame_cycle_t = 0.02
	await _tick(10)
	if foe.flame_is_on == was_on:
		fail("周期计时归零后开合状态没有翻转 (仍为 %s)" % str(was_on))
	elif foe.flame_jet.is_burning != foe.flame_is_on:
		fail("flame_is_on=%s 但 flame_jet.is_burning=%s, 两边不同步"
			% [str(foe.flame_is_on), str(foe.flame_jet.is_burning)])
	else:
		ok("开合周期翻转 %s -> %s, 火舌状态同步" % [str(was_on), str(foe.flame_is_on)])

	# 清场: 后面要验"血掉了是被火烧的"。别的敌人会开枪, 而且*已经飞在半空的
	# 子弹*会在几十帧之后才打到玩家 —— 那正好落在伤害检查的窗口里, 会被误判成
	# 火焰伤害。所以敌人和子弹都得清掉。
	_purge_hazards(main, foe)
	await _tick(1)

	# --- 打得到正前方的玩家 ---
	var p1 = main.p1_instance
	if p1 == null or not is_instance_valid(p1):
		fail("战场里没有 P1, 无法验伤害")
		main.queue_free()
		return
	# 出生保护会吞掉伤害
	p1.is_invulnerable = false
	p1.invulnerable_timer = 0.0
	# 一级玩家 max_health 就是 1 (挨一发子弹也是死), 拿它验伤害等于没验:
	# 就算火舌完全不生效, 喷火兵撞上来也能把人撞没, 测试照样绿。
	# 加厚血条 + 冻住双方物理, 让唯一可能的掉血来源只剩火舌。
	p1.max_health = 6
	p1.current_health = 6
	# 让喷火兵朝右, 玩家摆在它正前方射程内
	foe.rotation = PI / 2.0
	p1.global_position = foe.global_position + Vector2.RIGHT * 70.0
	foe.set_physics_process(false)
	p1.set_physics_process(false)
	foe.flame_jet.set_burning(true)
	# 同上: 先让物理服务器把挪过去的位置吃进去, 再开始计分
	await _tick(2)
	foe.flame_jet._tick_t = 0.0
	var hp_before: int = p1.current_health
	# 0.75s / TICK_INTERVAL(0.30) => 期望结算 2~3 次
	await _tick(45)
	if not is_instance_valid(p1):
		fail("玩家被一路烧穿 6 点血 —— 伤害频率远高于设计值")
	else:
		var lost: int = hp_before - p1.current_health
		if lost <= 0:
			fail("玩家站在火舌正中 0.75 秒, 血量没变 (%d)" % hp_before)
		elif lost > 4:
			fail("0.75 秒掉了 %d 点血, 结算次数远超 TICK_INTERVAL 的预期 (2~3)" % lost)
		else:
			ok("正前方的玩家掉血 %d -> %d (0.75s 内 %d 次结算, 符合节流)"
				% [hp_before, p1.current_health, lost])

	# 背后打不到 —— 火舌是有方向的锥形, 不是以自己为中心的光环
	if is_instance_valid(p1):
		_purge_hazards(main, foe)
		p1.global_position = foe.global_position + Vector2.LEFT * 70.0
		# 挪完必须先空跑两帧再开始计分。改 global_position 不会立刻同步到物理
		# 服务器的 broadphase, 而 _apply_damage 走的是 intersect_shape ——
		# 传送后的第一帧查到的还是玩家*原来*的位置 (也就是正前方), 于是"站在
		# 背后"照样挨一下。这不是游戏里的问题 (真实玩家是 move_and_slide 连续
		# 移动的, 不会瞬移), 而是测试自己造出来的假阳性: 之前正是这一下让
		# 这条检查一直报错。
		await _tick(2)
		var back_hp: int = p1.current_health
		foe.flame_jet._tick_t = 0.0
		await _tick(30)
		if is_instance_valid(p1) and p1.current_health < back_hp:
			fail("站在喷火兵*背后*的玩家也掉血了 —— 判定不是朝前的锥形")
		else:
			ok("背后的玩家不受伤害, 火舌确实只朝前")

	# --- 打不到友军 ---
	if is_instance_valid(foe):
		main._instantiate_enemy(Vector2(200, 200), EnemyTank.EnemyType.BASIC, false, 1)
		var buddy: Node = null
		for c in main.actors_container.get_children():
			if "enemy_type" in c and c != foe:
				buddy = c
				break
		if buddy == null:
			fail("友军测试用的 BASIC 敌人没刷出来")
		else:
			buddy.global_position = foe.global_position + Vector2.RIGHT * 70.0
			# 让它站着别动, 免得自己走出火舌范围导致假阴性
			buddy.set_physics_process(false)
			await _tick(2)
			var b_hp = buddy.health
			foe.flame_jet._tick_t = 0.0
			await _tick(30)
			if not is_instance_valid(buddy):
				fail("友军被自己人的火烧死了 —— 火焰不应该伤害敌方阵营")
			elif buddy.health < b_hp:
				fail("友军掉血 %d -> %d —— 火焰不应该伤害敌方阵营" % [b_hp, buddy.health])
			else:
				ok("站在火舌里的友军毫发无伤 (HP %d)" % buddy.health)

	main.queue_free()
	await _tick(1)
