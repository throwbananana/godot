extends SceneTree

## 强化钢墙 (tile_reinforced_steel, "reinforced_steel" 组) 的火力免疫测试。
##
## 补 tools/test_explosive_terrain_matrix.gd 没覆盖的那一半: 那个文件只测四种
## 爆破物, 这里测子弹(普通/破钢弹两档)、穿透激光、动能推力/挤压夹墙——
## 这几处判定分散在 bullet.gd / laser_piercer.gd / laser_ring_cutter.gd /
## kinetic_push_helper.gd 四个文件里, 各自独立排除 "reinforced_steel", 任何
## 一处漏排除都会让这堵"全火力免疫"的墙悄悄被打穿。
##
## 用失败计数器 + 单次 quit() 收尾, 不用裸 assert() —— 见
## [[assert-on-random-precondition-hangs]]。

const KineticPushHelperScript = preload("res://scripts/kinetic_push_helper.gd")
const LaserPiercer = preload("res://scripts/laser_piercer.gd")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func ok(msg: String) -> void:
	print("  [ok] %s" % msg)

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> REINFORCED STEEL WALL IMMUNITY TEST <<<")
	print("==================================================")

	await _test_normal_bullet_cannot_break_it()
	await _test_tier3_bullet_cannot_break_it()
	await _test_tier3_bullet_still_breaks_regular_steel()
	await _test_laser_stops_but_does_not_destroy_it()
	_test_immune_to_kinetic_push()
	_test_still_counts_as_solid_anvil_for_squeeze_kill()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL REINFORCED STEEL WALL CHECKS PASSED! <<<")
		quit(0)

func _make_wall(pos: Vector2, parent: Node = null) -> StaticBody2D:
	var wall = StaticBody2D.new()
	wall.add_to_group("steel")
	wall.add_to_group("reinforced_steel")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(44.0, 44.0)
	col.shape = shape
	wall.add_child(col)
	(parent if parent else root).add_child(wall)
	wall.global_position = pos
	return wall

func _make_bullet(can_destroy_steel: bool, pos: Vector2) -> Node2D:
	var b = load("res://scenes/bullet.tscn").instantiate()
	b.can_destroy_steel = can_destroy_steel
	b.damage = 2
	b.shooter_type = "player"
	root.add_child(b)
	b.global_position = pos
	return b

func _test_normal_bullet_cannot_break_it() -> void:
	print("\n[STEP 1] 普通子弹打不穿强化钢墙...")
	var wall = _make_wall(Vector2(200, 200))
	var bullet = _make_bullet(false, Vector2(200, 200))

	bullet._on_body_entered(wall)
	# queue_free() 只是登记删除, 不会立刻生效——不等一帧的话, 就算这一发子弹
	# 真的把 body.queue_free() 打过去了, is_instance_valid() 当场查还是 true,
	# 断言会"碰巧"通过。跟 STEP 3 是同一个坑, 三步都要等。
	await process_frame

	if not is_instance_valid(wall):
		fail("普通子弹不该摧毁强化钢墙, 但它被打没了")
	else:
		ok("普通子弹对强化钢墙无效, 墙体存活")

	if is_instance_valid(wall):
		wall.queue_free()
	if is_instance_valid(bullet):
		bullet.queue_free()

func _test_tier3_bullet_cannot_break_it() -> void:
	print("\n[STEP 2] 破钢弹(三级炮弹)也打不穿强化钢墙...")
	var wall = _make_wall(Vector2(300, 200))
	var bullet = _make_bullet(true, Vector2(300, 200))

	bullet._on_body_entered(wall)
	await process_frame # 同 STEP 1, queue_free() 是延迟生效的

	if not is_instance_valid(wall):
		fail("破钢弹不该摧毁强化钢墙 —— 这是它和普通钢墙的关键区别, 但墙被打没了")
	else:
		ok("破钢弹对强化钢墙依然无效, 墙体存活")

	if is_instance_valid(wall):
		wall.queue_free()
	if is_instance_valid(bullet):
		bullet.queue_free()

func _test_tier3_bullet_still_breaks_regular_steel() -> void:
	print("\n[STEP 3] 对照组: 破钢弹依然打得穿普通钢墙 (确认测试本身有区分力)...")
	var wall = StaticBody2D.new()
	wall.add_to_group("steel") # 只挂 steel, 不挂 reinforced_steel
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(44.0, 44.0)
	col.shape = shape
	wall.add_child(col)
	root.add_child(wall)
	wall.global_position = Vector2(400, 200)

	var bullet = _make_bullet(true, Vector2(400, 200))
	bullet._on_body_entered(wall)
	await process_frame # queue_free() only marks for deletion; give it a frame to actually take effect

	if is_instance_valid(wall):
		fail("对照组失败: 普通钢墙本该被破钢弹打穿, 但它还活着 —— 说明上面两条 " +
			"测试可能是因为子弹/collider 没正确交互而'碰巧'通过, 不是真的免疫")
	else:
		ok("对照组通过: 普通钢墙确实被破钢弹打穿了, 前两条测试的'存活'是真的免疫")

	if is_instance_valid(bullet):
		bullet.queue_free()

func _test_laser_stops_but_does_not_destroy_it() -> void:
	print("\n[STEP 4] 穿透激光在强化钢墙前停下, 墙体不受损...")
	# Node2D 父容器, 不是裸 root(Window) —— LaserPiercer 需要一个 Node2D
	# 父节点挂光束精灵, 同一坑见 test_kinetic_push_and_squeeze.gd 那次修复。
	var actors = Node2D.new()
	root.add_child(actors)

	var wall = _make_wall(Vector2(300.0, 300.0), actors)
	var shooter = Node2D.new()
	actors.add_child(shooter)
	shooter.global_position = Vector2(100.0, 300.0)

	await process_frame
	await process_frame

	LaserPiercer.fire_linear_laser(actors, Vector2(126.0, 300.0), Vector2.RIGHT, shooter, "enemy", 2)
	await process_frame

	if not is_instance_valid(wall):
		fail("激光不该摧毁强化钢墙, 但它被打没了")
	else:
		ok("激光对强化钢墙无效, 墙体存活")

	# 光束视觉端点不该跑到墙的右边去 —— 说明激光确实在墙前停住而不是穿透过去。
	var beam: Sprite2D = null
	for c in actors.get_children():
		if c is Sprite2D:
			beam = c
			break
	if beam == null:
		fail("没有生成光束精灵, 无法验证光束是否在墙前停住")
	else:
		var half_len: float = beam.texture.get_height() * beam.scale.y * 0.5
		var beam_end_x: float = beam.global_position.x + half_len
		if beam_end_x > wall.global_position.x + 4.0:
			fail("光束末端 (x=%.1f) 越过了强化钢墙 (x=%.1f) —— 应该在墙前停住" % [beam_end_x, wall.global_position.x])
		else:
			ok("光束正确在强化钢墙前停住 (光束末端 x=%.1f, 墙 x=%.1f)" % [beam_end_x, wall.global_position.x])

	actors.queue_free()

func _test_immune_to_kinetic_push() -> void:
	print("\n[STEP 5] 强化钢墙不可被任何等级的动能推力推动...")
	var wall = _make_wall(Vector2(500, 200))

	if KineticPushHelperScript.can_push(wall, false):
		fail("普通动能弹不该能推动强化钢墙")
	else:
		ok("普通动能弹推不动强化钢墙")

	if KineticPushHelperScript.can_push(wall, true):
		fail("破钢等级的动能推力也不该能推动强化钢墙")
	else:
		ok("破钢等级动能推力也推不动强化钢墙")

	wall.queue_free()

func _test_still_counts_as_solid_anvil_for_squeeze_kill() -> void:
	print("\n[STEP 6] 强化钢墙依然算实心死角, 能被用来做挤压夹墙判定...")
	# _is_position_blocked_solid(context_node, pos, ignore_collider, ...) 会把
	# context_node 和 ignore_collider 自己的 RID 排除在查询之外——如果把 wall
	# 同时传成这两者, 查询会把 wall 自己排除掉, 检测不到任何东西, 断言必然
	# (错误地)失败。真实用法里这两个参数是"被推的方块"和"被夹的单位",
	# 都不是 wall 本身, 所以这里用两个独立的占位节点。
	var pusher_stub = Node2D.new()
	root.add_child(pusher_stub)
	var victim_stub = CharacterBody2D.new()
	victim_stub.add_to_group("enemy")
	root.add_child(victim_stub)

	var wall = _make_wall(Vector2(600, 200))

	await process_frame
	await process_frame

	var is_blocked = KineticPushHelperScript._is_position_blocked_solid(pusher_stub, Vector2(600, 200), victim_stub, null, 24.0, 1000.0)
	if not is_blocked:
		fail("强化钢墙应该继续被 _is_position_blocked_solid() 判定为实心死角 (用于挤压击杀), 但没被判定到")
	else:
		ok("强化钢墙依然被正确判定为实心死角, 挤压击杀机制不受影响")

	wall.queue_free()
	pusher_stub.queue_free()
	victim_stub.queue_free()
