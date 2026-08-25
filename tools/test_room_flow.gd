extends SceneTree

## 房间流程的运行时验收: 门闩、切房、基地生命周期。
##
## test_floor_map.gd 验的是**生成出来的图**对不对; 这里验的是**走在图上**对不对。
## 两者分开是因为它们的失败方式完全不同 —— 图可以完美无缺, 而门照样打不开,
## 或者玩家一过门就掉血、火车掉尾巴。
##
## 全程驱动真实的 main.gd::enter_room() / _on_room_cleared(), 不复刻任何逻辑。

const GameState = preload("res://scripts/game_state.gd")
const FloorMap = preload("res://scripts/floor_map.gd")
const RoomDoor = preload("res://scripts/room_door.gd")
const ShopDialogRules = preload("res://scripts/shop_dialog.gd")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func ok(msg: String) -> void:
	print("  [ok] %s" % msg)

func _init() -> void:
	call_deferred("_run")


func _first_combat_room() -> String:
	for k in GameState.floor_rooms.keys():
		if FloorMap.is_combat_room(GameState.floor_rooms[k]):
			return str(k)
	return ""


func _run() -> void:
	print("==================================================")
	print(">>> ROOM FLOW (doors / transition / base) TEST <<<")
	print("==================================================")

	GameState.reset_campaign(1)
	var main_inst = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame

	await _test_start_room(main_inst)
	await _test_combat_room_locks_doors(main_inst)
	await _test_clear_opens_doors_and_removes_base(main_inst)
	await _test_transition_keeps_player_hp(main_inst)
	_test_cleared_room_stays_cleared(main_inst)
	await _test_walking_into_door(main_inst)
	await _test_shop_room_is_physical(main_inst)
	await _test_shop_stock_persists(main_inst)
	await _test_sold_out_persists(main_inst)
	await _test_cannot_afford(main_inst)

	main_inst.queue_free()
	await process_frame

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL ROOM FLOW CHECKS PASSED! <<<")
		quit(0)


## 起始房: 没有敌人, 没有鹰巢, 门全开 —— 玩家一进游戏就该能随便走。
func _test_start_room(main_inst) -> void:
	print("\n--- 起始房 ---")
	if GameState.current_room != GameState.floor_start_room:
		fail("开局不在起始房 (在 %s, 起始房是 %s)" % [GameState.current_room, GameState.floor_start_room])
		return
	if main_inst.base_instance != null:
		fail("起始房不该有鹰巢 —— 它不是战斗房")
	if main_inst.enemies_alive != 0:
		fail("起始房不该有敌人, 实际 %d" % main_inst.enemies_alive)

	var closed := 0
	for d in main_inst.doors.keys():
		var door = main_inst.doors[d]
		if door.state == RoomDoor.State.LOCKED:
			closed += 1
	if closed > 0:
		fail("起始房有 %d 扇门锁着 —— 玩家会被关在开局房里" % closed)
	else:
		ok("起始房: 无敌人无鹰巢, %d 扇门全部可通行" % main_inst.doors.size())


## 走进没打完的战斗房: 鹰巢出现, 门全部落闩。
func _test_combat_room_locks_doors(main_inst) -> void:
	print("\n--- 战斗房门闩 ---")
	var target := _first_combat_room()
	if target == "":
		fail("本层没有战斗房")
		return
	main_inst.enter_room(target, -1)
	await process_frame

	if main_inst.base_instance == null or not is_instance_valid(main_inst.base_instance):
		fail("战斗房里没有生成鹰巢")
	else:
		# 鹰巢必须落在经典位置 (底边中央), 而不是门位上。
		var expected := Vector2(6.5 * 48.0, 12.5 * 48.0)
		if main_inst.base_instance.position.distance_to(expected) > 0.1:
			fail("鹰巢应在 %s, 实际 %s" % [str(expected), str(main_inst.base_instance.position)])

	var open_doors := 0
	for d in main_inst.doors.keys():
		if main_inst.doors[d].state == RoomDoor.State.OPEN:
			open_doors += 1
	if open_doors > 0:
		fail("战斗房还没打完就有 %d 扇门开着 —— 门闩没生效" % open_doors)
	else:
		ok("战斗房: 鹰巢在 %s, %d 扇门全部落闩"
			% [str(main_inst.base_instance.position), main_inst.doors.size()])

	# 门必须和基地那一坨错开。这是硬要求: 门开在边中点 (col 6) 的话, 南门正好
	# 顶在鹰巢脸上, 玩家出不去也进不来。
	if RoomDoor.DOOR_COL >= 5 and RoomDoor.DOOR_COL <= 7:
		fail("DOOR_COL=%d 落在鹰巢区 (col 5-7) 上 —— 南门会被基地堵死" % RoomDoor.DOOR_COL)
	elif RoomDoor.DOOR_COL == 4 or RoomDoor.DOOR_COL == 8:
		fail("DOOR_COL=%d 落在玩家出生点上" % RoomDoor.DOOR_COL)
	else:
		ok("DOOR_COL=%d 避开了鹰巢区(5-7)与出生点(4,8)" % RoomDoor.DOOR_COL)


## 清空房间: 门开、鹰巢连同围墙一起撤掉。
##
## 撤鹰巢不是表现问题: 鹰巢那一坨占着 [11][5..7] 和 [12][5,6,7], 正压在底边
## 中段。留着的话已经打完的房间里还杵着一块必须绕开的死障碍。
func _test_clear_opens_doors_and_removes_base(main_inst) -> void:
	print("\n--- 清房 -> 开门 + 撤基地 ---")
	# 直接把遭遇打完: 模拟"最后一只被打死"。
	main_inst.enemies_spawned = main_inst.total_enemies
	main_inst.enemies_alive = 0
	main_inst._on_room_cleared()
	await process_frame
	await process_frame

	if main_inst.base_instance != null and is_instance_valid(main_inst.base_instance):
		fail("清房后鹰巢还在 —— 它会永久堵住底边中段")
	var wall_left: int = main_inst.base_wall_container.get_child_count()
	var alive_walls := 0
	for c in main_inst.base_wall_container.get_children():
		if not c.is_queued_for_deletion():
			alive_walls += 1
	if alive_walls > 0:
		fail("清房后鹰巢围墙还剩 %d 块 (共 %d 个子节点)" % [alive_walls, wall_left])

	var locked := 0
	var secret := 0
	for d in main_inst.doors.keys():
		var st = main_inst.doors[d].state
		if st == RoomDoor.State.LOCKED:
			locked += 1
		elif st == RoomDoor.State.SECRET:
			secret += 1
	if locked > 0:
		fail("清房后还有 %d 扇门锁着" % locked)
	else:
		ok("清房后: 鹰巢与围墙已撤, %d 扇普通门全开 (%d 扇暗门保持隐藏)"
			% [main_inst.doors.size() - secret, secret])

	if not bool(GameState.current_room_data().get("cleared", false)):
		fail("房间没有被标记为 cleared")

	# 铲子在清房之后不能把基地变回来 —— 那会在已经打完的房间里凭空长出一座
	# 基地和五块钢墙, 重新堵上南门。
	main_inst.trigger_shovel()
	await process_frame
	if main_inst.base_instance != null and is_instance_valid(main_inst.base_instance):
		fail("清房后吃铲子把鹰巢重建出来了 —— 南门会被重新堵上")
	else:
		ok("清房后铲子不再重建鹰巢")


## 过门: 玩家实例要**活着跨过去**, 血量原样保留。
##
## 这是房间制和原来"一层一场、换场景"最大的行为差别。玩家节点如果在
## _clear_all() 里被删掉重建, 血量会回满, 于是每过一道门就是一次免费全恢复。
func _test_transition_keeps_player_hp(main_inst) -> void:
	print("\n--- 过门保留玩家状态 ---")
	var p = main_inst.p1_instance
	if p == null or not is_instance_valid(p):
		fail("找不到 P1 实例")
		return

	# 先受点伤, 否则满血过门看不出区别。
	p.set_invulnerable(0.0)
	var before_max: int = p.max_health
	p.current_health = maxi(1, before_max - 1)
	var before_hp: int = p.current_health
	var before_id: int = p.get_instance_id()

	# 找一扇能走的门。
	var dir := -1
	for d in range(4):
		if GameState.can_exit(GameState.current_room, d):
			dir = d
			break
	if dir < 0:
		fail("清空后的房间一扇能走的门都没有")
		return

	var from_room := GameState.current_room
	var to_room := GameState.neighbor_key(from_room, dir)
	main_inst.enter_room(to_room, FloorMap.opposite(dir))
	await process_frame

	if GameState.current_room != to_room:
		fail("过门后 current_room 没更新 (还在 %s)" % GameState.current_room)

	var p2 = main_inst.p1_instance
	if p2 == null or not is_instance_valid(p2):
		fail("过门后玩家实例没了")
		return
	if p2.get_instance_id() != before_id:
		fail("过门后玩家被重建了 (instance id 变了) —— 血量/状态会被重置")
	elif p2.current_health != before_hp:
		fail("过门后血量变了: %d -> %d" % [before_hp, p2.current_health])
	else:
		ok("过门后玩家是同一个实例, 血量保持 %d/%d" % [p2.current_health, p2.max_health])

	# 落点必须在门内侧那一格, 不能还站在上一个房间的位置上。
	var expect := RoomDoor.entry_position_for(FloorMap.opposite(dir), 13, 13)
	if p2.position.distance_to(expect) > 60.0:
		fail("过门后玩家落点 %s 离入口 %s 太远" % [str(p2.position), str(expect)])
	else:
		ok("玩家从 %s 门入场, 落点 %s" % [FloorMap.DIR_NAMES[FloorMap.opposite(dir)], str(p2.position)])


## 回头走进已经清空的房间: 不该再刷怪, 也不该再有鹰巢。
func _test_cleared_room_stays_cleared(main_inst) -> void:
	print("\n--- 回头进已清空的房间 ---")
	var cleared_key := ""
	for k in GameState.floor_rooms.keys():
		var r: Dictionary = GameState.floor_rooms[k]
		if bool(r.get("cleared", false)) and str(r.get("type", "")) != "start":
			cleared_key = str(k)
			break
	if cleared_key == "":
		print("  [skip] 本层还没有已清空的非起始房")
		return

	main_inst.enter_room(cleared_key, -1)
	if main_inst.enemies_alive != 0 or main_inst.enemies_spawned != 0:
		fail("重进已清空的房间又刷怪了 (alive=%d spawned=%d)"
			% [main_inst.enemies_alive, main_inst.enemies_spawned])
	elif main_inst.base_instance != null and is_instance_valid(main_inst.base_instance):
		fail("重进已清空的房间又生成了鹰巢")
	else:
		ok("已清空的房间重进后无敌人无鹰巢")


## 真的"走进门"这一步。
##
## 上面那些用例是直接调 enter_room() 的, 绕过了门本身 —— 门可以完全坏掉
## (触发区没开、blocker 没让路、类型判断把玩家挡在外面) 而它们照样全绿。
## 这里补上从 Area2D 回调到换房间的那一段。
func _test_walking_into_door(main_inst) -> void:
	print("\n--- 走进门触发切房 ---")
	var open_dir := -1
	for d in main_inst.doors.keys():
		if main_inst.doors[d].state == RoomDoor.State.OPEN:
			open_dir = int(d)
			break
	if open_dir < 0:
		print("  [skip] 当前房间没有开着的门")
		return

	var door = main_inst.doors[open_dir]

	# 开着的门必须在**监听**, 而且挡路的碰撞体要让开。这两条只要有一条不成立,
	# 玩家就会站在门口原地不动 —— 而门画出来是开的, 看上去像卡死。
	if not door.monitoring:
		fail("开着的门没有开启 monitoring, 走上去不会触发")
	if door._blocker.collision_layer != 0:
		fail("开着的门还留着碰撞体, 玩家会被挡在门口")

	var before_room := GameState.current_room
	var expected := GameState.neighbor_key(before_room, open_dir)
	if expected == "":
		print("  [skip] 这扇门通向的房间不存在")
		return

	# 直接喂给回调, 而不是把玩家挪到门上等物理帧: 传送之后同一帧的物理查询看到
	# 的还是旧位置 (CLAUDE.md 里 broadphase 那一条), 靠等帧会变成一个偶发的测试。
	door._on_body_entered(main_inst.p1_instance)
	# _transition_to_room() 是淡出 -> 建房 -> 淡入, 中间有两段 await tween。
	# 所以要等到**整个过程结束**(is_transitioning 落回 false), 而不是一看到
	# current_room 变了就收工 —— 换房间发生在两段淡入淡出的中间。
	var settled := false
	for _i in range(240):
		await process_frame
		if GameState.current_room == expected and not main_inst.is_transitioning:
			settled = true
			break

	if GameState.current_room != expected:
		fail("走进 %s 门之后没有换到 %s (还在 %s)"
			% [FloorMap.DIR_NAMES[open_dir], expected, GameState.current_room])
	elif not settled:
		# is_transitioning 卡在 true 是会让**之后每一扇门都失效**的那种故障:
		# _on_door_entered() 第一行就是 if is_transitioning: return。
		fail("切房已换房但 is_transitioning 没落回 false —— 之后所有门都会失效")
	else:
		ok("走进 %s 门 -> 换到房间 %s, 转场状态已复位"
			% [FloorMap.DIR_NAMES[open_dir], expected])


## 商店房 = 地板上的物理货位，不是对话框。
##
## 这一组盯三件事, 每一件都对应一个"不报错但玩起来是坏的"的失败:
##   1. 货位真的摆出来了, 而且数量/配比对 (3 强化 + 3 建材)。
##   2. 货位不压在门廊上 —— 压上去就是"进门被扣钱"。
##   3. 货架**存进房间**了。房间可以自由回头, 每次进门重洗的话, 走出去再
##      进来就是一次免费刷新, 换货机的递增计费彻底失效。
func _test_shop_room_is_physical(main_inst) -> void:
	print("\n--- 商店房: 物理货位 ---")
	var shop_key := ""
	for k in GameState.floor_rooms.keys():
		if str(GameState.floor_rooms[k]["type"]) == "shop":
			shop_key = str(k)
			break
	if shop_key == "":
		fail("本层没有商店房 —— FloorMap.MIN_SHOPS_PER_FLOOR 的保底没生效")
		return

	main_inst.enter_room(shop_key, -1)
	await process_frame

	var stands: Array = []
	var rollers: Array = []
	for c in main_inst.map_container.get_children():
		if c.is_in_group("shop_stand"):
			stands.append(c)
		elif c.is_in_group("shop_rerolder"):
			rollers.append(c)

	if stands.size() != main_inst.SHOP_UPGRADE_SLOTS + main_inst.SHOP_BUILD_SLOTS:
		fail("货位应有 %d 个, 实际 %d 个"
			% [main_inst.SHOP_UPGRADE_SLOTS + main_inst.SHOP_BUILD_SLOTS, stands.size()])
	if rollers.size() != 1:
		fail("换货机应有 1 台, 实际 %d 台" % rollers.size())

	# 配比: 建材必须**保底有货**。它是 structure_inventory 的唯一来源, 混进
	# 同一个随机池的话, 抽不到建材的那一层建造系统直接断粮。
	var build_count := 0
	for st in stands:
		var d = ShopDialogRules.item_by_id(st.item_id)
		if str(d.get("category", "")) == "BUILD":
			build_count += 1
	if build_count != main_inst.SHOP_BUILD_SLOTS:
		fail("建材货位应有 %d 个, 实际 %d 个 —— 建材保底配比坏了"
			% [main_inst.SHOP_BUILD_SLOTS, build_count])
	else:
		ok("%d 个货位 (%d 建材 + %d 强化) + %d 台换货机"
			% [stands.size(), build_count, stands.size() - build_count, rollers.size()])

	# 门廊不能被占。玩家从门进来会沿门廊直走, 货位压在上面就是进门被扣钱。
	var blocked: Array[String] = []
	for st in stands + rollers:
		var col := int(st.position.x / 48.0)
		var row := int(st.position.y / 48.0)
		if col == RoomDoor.DOOR_COL or row == RoomDoor.DOOR_ROW:
			blocked.append("(%d,%d)" % [col, row])
	if not blocked.is_empty():
		fail("这些货位压在门廊上 (第 %d 列 / 第 %d 行): %s —— 玩家一进门就会被扣钱"
			% [RoomDoor.DOOR_COL, RoomDoor.DOOR_ROW, ", ".join(blocked)])
	else:
		ok("所有货位避开了门廊 (第 %d 列 / 第 %d 行)" % [RoomDoor.DOOR_COL, RoomDoor.DOOR_ROW])

	# 货位和换货机都不能压在**入场点**上。
	#
	# 这条是照着一个真实踩过的坑写的: 换货机本来在 (6,10), 而
	# _place_players_at_entry() 的默认落点正好是 (6.5, 10.5) —— 首次走进商店房
	# 就站在换货机上, 当场被扣一笔换货费; 而换货会在物理回调里重建全部
	# 货位, 又直接报 "Can't change this state while flushing queries"。
	var entry_points: Array[Vector2] = [
		Vector2((13 / 2.0) * 48.0, (13 - 2.5) * 48.0),  # 首次入场的默认落点
	]
	for d in range(4):
		entry_points.append(RoomDoor.entry_position_for(d, 13, 13))

	var on_entry: Array[String] = []
	for obj in stands + rollers:
		for ep in entry_points:
			if obj.position.distance_to(ep) < 30.0:
				on_entry.append("%s@%s" % [obj.get_class(), str(obj.position)])
				break
	if not on_entry.is_empty():
		fail("这些商店物体压在入场点上: %s —— 玩家一进门就会被动触发"
			% ", ".join(on_entry))
	else:
		ok("货位与换货机避开了全部 %d 个入场点" % entry_points.size())

	if main_inst.base_instance != null and is_instance_valid(main_inst.base_instance):
		fail("商店房不该有鹰巢")
	if main_inst.enemies_spawned != 0:
		fail("商店房不该刷怪 (spawned=%d)" % main_inst.enemies_spawned)


## 走出商店再走回来, 货架必须一模一样。
##
## 这是房间化引入的一个真实缺陷: 原来 _on_enter_non_combat_room() 每次进门都调
## shop_dialog.setup_shop(), 而它内部会重新洗牌。实测 6 次进出拿到 6 种不同货架
## —— 也就是说不用花一分钱, 走出门再进来就是一次刷新, 换货机那套递增计费
## (20/45/70...) 完全被架空。
func _test_shop_stock_persists(main_inst) -> void:
	print("\n--- 商店房: 走出去再回来货架不变 ---")
	var shop_key := GameState.current_room
	if str(GameState.current_room_data().get("type", "")) != "shop":
		print("  [skip] 当前不在商店房")
		return

	var first: Array[String] = []
	for c in main_inst.map_container.get_children():
		if c.is_in_group("shop_stand"):
			first.append("%s@%d" % [c.item_id, c.cost])
	first.sort()

	# 找个别的房间走出去再回来
	var other := str(GameState.floor_start_room)
	var seen := {}
	for visit in range(5):
		main_inst.enter_room(other, -1)
		await process_frame
		main_inst.enter_room(shop_key, -1)
		await process_frame
		var now: Array[String] = []
		for c in main_inst.map_container.get_children():
			if c.is_in_group("shop_stand"):
				now.append("%s@%d" % [c.item_id, c.cost])
		now.sort()
		seen[",".join(now)] = true

	if seen.size() != 1 or not seen.has(",".join(first)):
		fail("5 次进出看到 %d 种不同货架 —— 走出去再进来 = 免费刷新, 换货机的递增计费被架空"
			% seen.size())
	else:
		ok("5 次进出货架保持一致: %s" % ", ".join(first))


## 买下的东西不能"走出去再回来又长出来"。
func _test_sold_out_persists(main_inst) -> void:
	print("\n--- 商店房: 卖掉的货位不会复活 ---")
	if str(GameState.current_room_data().get("type", "")) != "shop":
		print("  [skip] 当前不在商店房")
		return

	var target = null
	for c in main_inst.map_container.get_children():
		if c.is_in_group("shop_stand") and not c.sold:
			target = c
			break
	if target == null:
		print("  [skip] 没有未售出的货位")
		return

	var bought_id: String = target.item_id
	GameState.gold = target.cost + 500
	var gold_before: int = GameState.gold
	var cost: int = target.cost
	target._on_body_entered(main_inst.p1_instance)
	await process_frame

	if not target.sold:
		fail("开上货位之后没有成交")
		return
	if GameState.gold != gold_before - cost:
		fail("成交后金币应为 %d, 实际 %d" % [gold_before - cost, GameState.gold])

	var shop_key := GameState.current_room
	main_inst.enter_room(str(GameState.floor_start_room), -1)
	await process_frame
	main_inst.enter_room(shop_key, -1)
	await process_frame

	for c in main_inst.map_container.get_children():
		if c.is_in_group("shop_stand") and c.item_id == bought_id and not c.sold:
			fail("买掉的 %s 走一圈回来又能买了" % bought_id)
			return
	ok("买下 %s 花了 %d G, 走出去再回来仍是 SOLD" % [bought_id, cost])


## 钱不够时不能扣钱, 也不能发货。
func _test_cannot_afford(main_inst) -> void:
	print("\n--- 商店房: 买不起时不扣钱不发货 ---")
	if str(GameState.current_room_data().get("type", "")) != "shop":
		print("  [skip] 当前不在商店房")
		return

	var target = null
	for c in main_inst.map_container.get_children():
		if c.is_in_group("shop_stand") and not c.sold:
			target = c
			break
	if target == null:
		print("  [skip] 没有未售出的货位")
		return

	GameState.gold = maxi(0, target.cost - 1)
	var before: int = GameState.gold
	target._on_body_entered(main_inst.p1_instance)
	await process_frame

	if target.sold:
		fail("金币不足却成交了")
	elif GameState.gold != before:
		fail("金币不足却扣了钱 (%d -> %d)" % [before, GameState.gold])
	else:
		ok("金币 %d < 售价 %d: 未成交且未扣钱" % [before, target.cost])
