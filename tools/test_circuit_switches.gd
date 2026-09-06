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
const BombSwitch = preload("res://scripts/buildings/bomb_switch.gd")
const EnergyWall = preload("res://scripts/buildings/energy_wall.gd")

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

	await _test_electric_wall_gating()
	await _test_shield_station_gating()
	_test_piston_switch_latches()
	_test_bomb_switch_destructible()
	_test_energy_wall_immunity()
	await _test_full_wiring_via_playtest_layout()
	await _test_bomb_switch_energy_wall_wiring()

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
	# 注意本函数改成 async (调用处 await 它): set_circuit_solved() 里的碰撞体
	# 改动是 set_deferred, 不是同步生效——这是为了让开关在真实游戏里能在
	# body_entered (物理查询 flush 期间) 调用它而不撞 "Can't change this
	# state while flushing queries" (跟 shop_dialog.gd 的 reroll 同一类坑,
	# 见 CLAUDE.md), 所以这里也要等一帧再检查 disabled。
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
	await process_frame # collision_shape.disabled 是 set_deferred, 要等一帧
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


## 可摧毁开关: 2 HP, 打两下才炸, 炸的时候恰好发一次 switch_pressed。
func _test_bomb_switch_destructible() -> void:
	print("\n--- 可摧毁开关 (bomb_switch) ---")
	var switch_scene: PackedScene = load("res://scenes/buildings/bomb_switch.tscn")
	var sw = switch_scene.instantiate()
	sw.gate_color = "red"
	root.add_child(sw)

	var emitted: Array = []
	sw.switch_pressed.connect(func(color): emitted.append(color))

	sw.take_damage(1)
	if sw.is_destroyed or not emitted.is_empty():
		fail("开关只挨了 1 点伤害 (满血 2) 就被打爆了")
	else:
		ok("开关扛住第一下 (1/2 血) 没有提前触发")

	sw.take_damage(1)
	if not sw.is_destroyed:
		fail("开关打满 2 点伤害后应该被摧毁, 但 is_destroyed 仍是 false")
	elif emitted.size() != 1 or emitted[0] != "red":
		fail("开关打爆时应该恰好发出一次 'red', 实际 %s" % str(emitted))
	else:
		ok("开关打满血量后正确摧毁并发出一次 'red'")

	sw.queue_free()


## 能量墙: 对一切火力免疫的核心是"不挂 buildings/building 组、也不暴露
## take_damage/destroy"——这里直接断言分组和方法表, 而不是逐个重放 9 处
## 判定逻辑 (那是 bullet.gd/laser_piercer.gd 等文件自己的事, 这里只保证
## energy_wall 满足它们全部依赖的那个前提)。set_circuit_solved(true) 才是
## 唯一能让它消失的路径。
func _test_energy_wall_immunity() -> void:
	print("\n--- 能量墙 (energy_wall) 免疫与摧毁 ---")
	var wall_scene: PackedScene = load("res://scenes/buildings/energy_wall.tscn")
	var wall = wall_scene.instantiate()
	wall.gate_color = "blue"
	root.add_child(wall)

	if not wall.is_in_group("steel") or not wall.is_in_group("border"):
		fail("能量墙必须同时在 steel 和 border 组里才能继承全套免疫反馈")
	elif wall.is_in_group("buildings") or wall.is_in_group("building"):
		fail("能量墙不能挂 buildings/building 组, 否则会在 bullet.gd 的 elif 链里抢在 steel 分支之前短路掉免疫")
	elif wall.has_method("take_damage") or wall.has_method("destroy"):
		fail("能量墙不该暴露 take_damage()/destroy()——那两个方法名会被 bullet.gd 的鸭子分派直接调用, 绕过免疫")
	else:
		ok("能量墙分组/方法表满足全免疫前提 (steel+border, 无 buildings, 无 take_damage/destroy)")

	wall.set_circuit_solved(false)
	if wall.is_queued_for_deletion():
		fail("set_circuit_solved(false) 不该摧毁能量墙")
	else:
		ok("set_circuit_solved(false) 对能量墙无效果 (还没解开)")

	wall.set_circuit_solved(true)
	if not wall.is_queued_for_deletion():
		fail("set_circuit_solved(true) 之后能量墙应该被摧毁 (queue_free)")
	else:
		ok("set_circuit_solved(true) 后能量墙正确摧毁——唯一的摧毁路径")


## 集成测试: 打爆开关 (52/53) -> 摧毁受控能量墙 (54/55) 这条链路, 跟压力板
## 走的是同一份 main.gd::_on_circuit_switch_pressed(), 只是触发方式换成直接
## 调用 take_damage() 而不是驱动坦克重叠——bomb_switch 打爆判定本身已经在
## _test_bomb_switch_destructible() 里独立验过, 这里只验"main.gd 接线有没有
## 把它和 _spawn_energy_wall() 接到一起"。
func _test_bomb_switch_energy_wall_wiring() -> void:
	print("\n--- 集成: 打爆开关 -> 摧毁能量墙 ---")
	GameState.reset_campaign(1)

	var layout: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		layout.append(row)
	layout[6][6] = 53 # 蓝色可摧毁开关
	layout[7][6] = 55 # 蓝色能量墙
	GameState.playtest_layout = layout

	var main_inst = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame
	await process_frame

	var bomb_sw: BombSwitch = null
	var energy_wall: EnergyWall = null
	for child in main_inst.actors_container.get_children():
		if child is BombSwitch:
			bomb_sw = child
	for child in main_inst.map_container.get_children():
		if child is EnergyWall:
			energy_wall = child

	if bomb_sw == null or energy_wall == null:
		fail("没能同时找到蓝色可摧毁开关和蓝色能量墙实例——tile_type==53/55 的分派可能没接上")
		main_inst.queue_free()
		await process_frame
		return
	ok("蓝色可摧毁开关与蓝色能量墙均已通过真实地块分派生成")

	bomb_sw.take_damage(99)
	# queue_free() 在 await process_frame 之后已经真正释放节点 (不只是标记
	# 待删), 这里必须用 is_instance_valid() 而不是在可能已被释放的实例上调
	# is_queued_for_deletion()——那样会撞 "Cannot call method on a
	# previously freed instance" 报错, 而且这个报错不会被计进 fail(), 会让
	# 一个已经崩掉的检查悄悄读成 PASSED。
	await process_frame

	if is_instance_valid(energy_wall):
		fail("打爆蓝色开关之后, 蓝色能量墙应该被摧毁, 但它还在场上")
	else:
		ok("打爆蓝色开关后, 蓝色能量墙正确被摧毁——完整接线验证通过")

	main_inst.queue_free()
	await process_frame
	await process_frame


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
	for child in main_inst.map_container.get_children():
		if child is ElectricWall:
			gated_wall = child
			break
	if gated_wall == null:
		fail("没有在 map_container 里找到蓝色受控电墙实例——tile_type==49 的分派可能没接上")
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
