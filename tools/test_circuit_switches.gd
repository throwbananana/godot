extends SceneTree

## 电路/活塞开关机制的验收。
##
## 分两层, 跟 test_room_flow.gd / test_floor_map.gd 的分工思路一样:
##  - 建筑级单元测试 (本文件大部分): 直接实例化 electric_wall.tscn /
##    shield_station.tscn / piston_switch.tscn, 直接调用它们的方法/信号
##    处理函数, 不依赖物理重叠判定的时序——跟 tools/test_oil_barrel_blast.gd
##    一样用最小 stub 场景树, 不启动 main.tscn。
##  - 集成测试 (最后一段): 通过 GameState.playtest_layout 走真实的
##    main.gd::_build_map() 地块分派 -> 开关按下 -> main.gd 广播 ->
##    建筑 set_circuit_solved() 这条完整链路, 验证接线本身没接错。
##
## 用失败计数器 + 单次 quit() 收尾, 不用裸 assert()——见
## [[assert-on-random-precondition-hangs]]。

const GameState = preload("res://scripts/game_state.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	call_deferred("_run")


## 最小的"坦克"替身, 带真正的方法而不是动态注入属性——electric_wall 靠
## has_method("take_damage") 鸭子类型判断, shield_station 靠
## has_method("set_invulnerable"), 都需要真方法, 不是随便挂个属性能糊弄的。
class TankStub extends CharacterBody2D:
	var damage_taken: int = 0
	var invuln_calls: int = 0

	func take_damage(amt: int) -> void:
		damage_taken += amt

	func set_invulnerable(_duration: float) -> void:
		invuln_calls += 1


func _run() -> void:
	print("==================================================")
	print(">>> CIRCUIT / PISTON SWITCH TEST <<<")
	print("==================================================")

	_test_electric_wall_gating()
	await _test_shield_station_gating()
	_test_piston_switch_latches()
	await _test_full_wiring_via_playtest_layout()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL CIRCUIT SWITCH CHECKS PASSED! <<<")
		quit(0)


## 普通电墙 (tile 25 / 玩家建造) 完全不受影响: 默认 is_powered=true,
## set_circuit_solved(true) 之后变成完全惰性——不再电人, 碰撞关掉。
func _test_electric_wall_gating() -> void:
	print("\n--- 电墙 gating ---")
	var wall_scene: PackedScene = load("res://scenes/buildings/electric_wall.tscn")
	var wall = wall_scene.instantiate()
	root.add_child(wall)

	if not wall.is_powered:
		fail("电墙默认应该是 is_powered=true (未受电路控制的墙不该受影响)")
	else:
		ok("电墙默认 is_powered=true")

	var tank := TankStub.new()
	root.add_child(tank)

	wall._try_shock_body(tank)
	if tank.damage_taken == 0:
		fail("通电状态下电墙应该对坦克造成伤害, 但 take_damage 没被调用")
	else:
		ok("通电状态下电墙正常电击坦克")

	wall.set_circuit_solved(true)
	if wall.is_powered:
		fail("set_circuit_solved(true) 之后 is_powered 应该是 false")
	else:
		ok("set_circuit_solved(true) 后 is_powered=false")
	if not wall.collision_shape.disabled:
		fail("电路解开后电墙的碰撞体应该被禁用 (变得可以穿过)")
	else:
		ok("电路解开后电墙碰撞体已禁用, 可以穿过")

	wall.shock_timers.clear() # 清掉冷却, 确认不是"冷却期内不电"而是"真的断电了"
	tank.damage_taken = 0
	wall._try_shock_body(tank)
	if tank.damage_taken > 0:
		fail("电路解开后电墙不该再电人, 但 take_damage 又被调用了")
	else:
		ok("电路解开后电墙不再电人")

	wall.queue_free()
	tank.queue_free()


## 电路型充能站默认 is_powered=false (出生即惰性); set_circuit_solved(true)
## 之后立即可用 (充能完毕状态, 不用再等一次冷却)。
func _test_shield_station_gating() -> void:
	print("\n--- 充能站 gating ---")
	var station_scene: PackedScene = load("res://scenes/buildings/shield_station.tscn")
	var station = station_scene.instantiate()
	station.is_powered = false # 模拟 main.gd::_spawn_gated_shield_station() 在 add_child 前的赋值
	root.add_child(station)
	await process_frame

	if station.is_charged:
		fail("没接通电路的充能站不该处于 is_charged=true")
	else:
		ok("没接通电路的充能站正确保持未充能")

	var tank := TankStub.new()
	tank.add_to_group("player")
	root.add_child(tank)

	station._on_body_entered(tank)
	if tank.invuln_calls > 0:
		fail("没接通电路的充能站不该能被玩家使用")
	else:
		ok("没接通电路的充能站正确拒绝玩家使用")

	station.set_circuit_solved(true)
	if not station.is_powered or not station.is_charged:
		fail("set_circuit_solved(true) 之后应该立即 is_powered=true 且 is_charged=true")
	else:
		ok("电路解开后充能站立即可用, 不用再等一次冷却")

	station._on_body_entered(tank)
	if tank.invuln_calls == 0:
		fail("电路解开后充能站应该正常给玩家授予护盾")
	else:
		ok("电路解开后充能站正常工作")

	station.queue_free()
	tank.queue_free()


## 开关按一次永久锁存: 第二次进入 (或非坦克触发) 不应该重复发出
## switch_pressed。
func _test_piston_switch_latches() -> void:
	print("\n--- 活塞开关锁存 ---")
	var switch_scene: PackedScene = load("res://scenes/buildings/piston_switch.tscn")
	var sw = switch_scene.instantiate()
	sw.gate_color = "blue"
	root.add_child(sw)

	var emitted: Array = []
	sw.switch_pressed.connect(func(color): emitted.append(color))

	var tank := TankStub.new()
	root.add_child(tank)

	sw._on_body_entered(tank)
	if emitted.size() != 1 or emitted[0] != "blue":
		fail("开关首次触发应该恰好发出一次 'blue', 实际 %s" % str(emitted))
	else:
		ok("开关首次触发正确发出一次 'blue'")

	sw._on_body_entered(tank)
	var bullet_stub := Area2D.new() # 非 CharacterBody2D, 模拟子弹不该触发开关
	sw._on_body_entered(bullet_stub)
	if emitted.size() != 1:
		fail("开关重复触发/非坦克触发不该再次发出信号, 实际发出了 %d 次" % emitted.size())
	else:
		ok("开关锁存后不再重复触发, 非坦克 (Area2D) 也不能触发")

	sw.queue_free()
	tank.queue_free()
	bullet_stub.queue_free()


## 集成测试: 走真实的 main.gd::_build_map() 地块分派。用
## GameState.playtest_layout 塞一张只有开关+受控电墙的最小布局, 把玩家挪到
## 开关格子上再走几帧物理, 断言电墙的碰撞体被正确禁用——这条链路覆盖了
## tile_type 分派 -> _spawn_piston_switch/_spawn_gated_electric_wall ->
## switch_pressed 信号 -> main.gd::_on_circuit_switch_pressed() ->
## set_circuit_solved() 的完整接线, 单元测试覆盖不到"main.gd 有没有接对线"
## 这一层。
func _test_full_wiring_via_playtest_layout() -> void:
	print("\n--- 集成: 真实地块分派 + 开关接线 ---")
	GameState.reset_campaign(1)

	# 46=红开关 47=蓝开关 48=红受控电墙 49=蓝受控电墙 50=红受控充能站 51=蓝受控充能站
	# 只测蓝色一组: 开关放在 (6,6), 受控电墙放在 (6,7), 均为空地围绕。
	var layout: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		layout.append(row)
	layout[6][6] = 47 # 蓝开关
	layout[7][6] = 49 # 蓝受控电墙
	GameState.playtest_layout = layout

	var main_inst = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame
	await process_frame

	var gated_wall: ElectricWall = null
	for child in main_inst.actors_container.get_children():
		if child is ElectricWall:
			gated_wall = child
			break
	if gated_wall == null:
		fail("没有在 actors_container 里找到蓝色受控电墙实例——tile_type==49 的分派可能没接上")
		main_inst.queue_free()
		await process_frame
		return
	ok("蓝色受控电墙已通过真实地块分派生成")

	if not gated_wall.is_powered:
		fail("受控电墙生成时应该默认通电 (is_powered=true), 电路还没解开")
	else:
		ok("受控电墙生成时默认通电")

	if not main_inst.p1_instance:
		fail("找不到 p1_instance, 无法驱动玩家开上开关")
		main_inst.queue_free()
		await process_frame
		return

	main_inst.p1_instance.global_position = main_inst.map_container.to_global(Vector2(6.5 * 48.0, 6.5 * 48.0))
	for _i in range(6):
		await physics_frame

	if not gated_wall.collision_shape.disabled:
		fail("玩家开上蓝开关之后, 蓝色受控电墙应该变为可穿过, 但碰撞体仍然启用")
	else:
		ok("玩家开上蓝开关后, 蓝色受控电墙正确变为可穿过——完整接线验证通过")

	main_inst.queue_free()
	await process_frame
	await process_frame
