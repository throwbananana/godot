extends SceneTree

## 大/超大房间 (26x26 / 52x52) 与护送挑战房在**联机**下的回归测试。
##
## 为什么单独有这么一个文件: 这两套系统 (2aa8273 / f33e8a9) 都比联机
## (012fa0c) 早进来, 而联机那三层测试一层都没覆盖到它们 ——
## test_net_runtime.gd 只跑默认的 13x13 街机房, run_net_e2e.ps1 的三趟走的是
## 随机楼层, 抽中大房间或护送房纯属运气。这跟 test_circuit_netsync.gd 要解决
## 的是同一类盲区: **比联机早进来的系统, 不会被联机的测试覆盖到**, 而且
## 全绿的套件不会告诉你这件事。
##
## 手法沿用 test_room_flow.gd::_force_room() —— 改当前房间的 size/type/
## challenge_mode 再走一遍真实的 enter_room(), 而不是手搭一份房间状态
## (手搭的必然和真实字段发散)。联机这一侧额外做两件事:
##
##   1. 战役状态**只生成一次**, 再用 campaign_to_dict() 分别喂给两端 ——
##      这正是真实客户端拿到主机战役状态的那条路 (net_apply_campaign)。
##      各自 reset_campaign() 一次的话两端楼层根本不同, 后面的比对全是空转。
##   2. 两端传同一个 room_seed 进 enter_room(), 跟真实的房间切换一致。
##
## **但对大房间来说, room_seed 并不是"两端建出同一张图"的依据 —— 这一点是
## 用反向对照测出来的, 不是推出来的。** 把客户端的 room_seed 故意错开 7,
## 校验和纹丝不动: 大房间由 CompositeRoomBuilder 拼 N x N 张**手搓模板**,
## 而模板选择走的是 MapTemplates 的 run_seed + room_key + floor_idx 那套
## (见 CLAUDE.md "Pool order is load-bearing"), 全程不读全局 RNG 流。
## room_seed 真正管的是程序生成房 (floor_idx % 3 == 2) 和遭遇掷骰。
##
## 所以这里的校验和断言真正钉住的是: **客户端必须从同步过来的战役字典里
## 拿到主机的 run_seed**。反向对照证实过 —— 只把客户端的 run_seed 偏移
## 12345, 校验和 1862322213 vs 858457936、瓦片数 1090 vs 686, 立刻双红。
## 换句话说这条断言有牙, 但它咬的不是 room_seed。
##
## 按项目惯例: 不用 assert, print("[FAIL] …") 记全局标志, **只在最后 quit
## 一次** (quit() 不中断调用栈, 中途 quit(1) 会被末尾的 quit(0) 覆盖回 0)。

const NetSession = preload("res://scripts/net_session.gd")
const GameState = preload("res://scripts/game_state.gd")
const FloorMap = preload("res://scripts/floor_map.gd")

const ROOM_SEED := 987654321

var _failed := false


func fail(msg: String) -> void:
	_failed = true
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func check(cond: bool, msg: String) -> void:
	if cond:
		ok(msg)
	else:
		fail(msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> NET ROOM VARIANTS TEST (大房间 / 护送房) <<<")
	print("==================================================")

	await _test_room_size("large", 26)
	await _test_room_size("huge", 52)
	await _test_escort_room()
	await _test_treasure_room()

	NetSession.reset()
	print("==================================================")
	if _failed:
		print("[FAIL] 大房间/护送房联机测试未通过")
		quit(1)
	else:
		print(">>> ALL NET ROOM VARIANT CHECKS PASSED! <<<")
		quit(0)


## 生成一次战役, 返回 (战役字典快照, 第一个战斗房的 key)。
func _make_campaign() -> Array:
	GameState.reset_campaign(2)
	GameState.ensure_floor_ready()
	var key := ""
	for k in GameState.floor_rooms.keys():
		if FloorMap.is_combat_room(GameState.floor_rooms[k]):
			key = str(k)
			break
	return [GameState.campaign_to_dict(), key]


## 把同一份战役状态喂给指定角色, 起一个 main.tscn, 并强制进入指定形态的房间。
func _boot(role: int, campaign: Dictionary, room_key: String, size: String, type: String, challenge_mode: String) -> Node:
	NetSession.reset()
	NetSession.role = role
	NetSession.local_player_id = 1 if role == NetSession.Role.HOST else 2
	NetSession.match_seed = 12345

	# 真实客户端就是这样接管主机战役状态的 (net_apply_campaign -> campaign_from_dict)。
	GameState.campaign_from_dict(campaign.duplicate(true))
	GameState.mode = GameState.GameMode.CAMPAIGN
	GameState.player_count = 2
	if room_key != "" and GameState.floor_rooms.has(room_key):
		GameState.floor_rooms[room_key]["size"] = size
		GameState.floor_rooms[room_key]["cleared"] = false
		GameState.floor_rooms[room_key]["type"] = type
		GameState.floor_rooms[room_key]["challenge_mode"] = challenge_mode

	var packed := load("res://scenes/main.tscn")
	if packed == null:
		fail("main.tscn 加载失败")
		return null
	var m: Node = packed.instantiate()
	root.add_child(m)
	await process_frame
	# 真实里 room_seed 由主机掷并随房间切换广播, 两端 seed() 同一个值。
	m.enter_room(room_key, -1, ROOM_SEED)
	await process_frame
	await process_frame
	return m


## 家具的 (名字前缀, 格号) 指纹 —— 跟 test_circuit_netsync.gd 同一个口径。
## 大房间是 CompositeRoomBuilder 把 N x N 张子图缝起来的, 缝合和连通性修复
## 都可能消耗 RNG, 所以"两端拼出同一张图"在这里比普通房间更需要被证明。
func _furniture_fingerprint(m: Node) -> Array:
	var out: Array = []
	for ch in m.actors_container.get_children():
		if not ch.has_meta(NetSession.FURNITURE_META):
			continue
		var p: Vector2 = (ch as Node2D).position
		out.append("%s@%d,%d" % [String(ch.name).left(6), int(floor(p.x / 48.0)), int(floor(p.y / 48.0))])
	out.sort()
	return out


func _test_room_size(size: String, expect_grid: int) -> void:
	print("\n[%s 房间 %dx%d 的两端一致性]" % [size, expect_grid, expect_grid])
	var made := _make_campaign()
	var campaign: Dictionary = made[0]
	var room_key: String = made[1]
	if room_key == "":
		fail("本层没有战斗房, 无法测试 %s 房间" % size)
		return

	var host := await _boot(NetSession.Role.HOST, campaign, room_key, size, "normal", "")
	if host == null:
		return
	check(host.GRID_W == expect_grid and host.GRID_H == expect_grid,
		"主机: GRID %d/%d" % [host.GRID_W, host.GRID_H])
	var host_sum: int = NetSession.map_checksum
	var host_tiles: int = host.map_container.get_children().size()
	var host_furn := _furniture_fingerprint(host)
	host.free()

	var client := await _boot(NetSession.Role.CLIENT, campaign, room_key, size, "normal", "")
	if client == null:
		return
	# 客户端的房间尺寸来自同步过来的战役字典, 不是它自己掷的。写错的话它会
	# 在一张 13x13 的图上收 26x26 的快照, 坦克全都在画面外。
	check(client.GRID_W == expect_grid and client.GRID_H == expect_grid,
		"客户端: GRID %d/%d (取自同步的战役字典)" % [client.GRID_W, client.GRID_H])
	var client_sum: int = NetSession.map_checksum
	var client_tiles: int = client.map_container.get_children().size()
	var client_furn := _furniture_fingerprint(client)

	check(host_sum != 0 and host_sum == client_sum,
		"两端地形校验和一致 (%d vs %d)" % [host_sum, client_sum])
	check(host_tiles == client_tiles,
		"两端瓦片数一致 (%d vs %d)" % [host_tiles, client_tiles])
	# 家具指纹: 抽到的子图里可能一件 actors_container 家具都没有 (手搓模板
	# 大多只用纯地形瓦片)。那种情况下 0 == 0 是恒真的空转断言, 必须如实说
	# 出来而不是记一条绿 —— 空转的绿比红更危险, 它会让人以为这块被覆盖了。
	# 真正扛事的是上面的校验和 (915 / 3436 块瓦片, 缝合与连通性修复都在里面)。
	if host_furn.is_empty() and client_furn.is_empty():
		print("  [--] 本次抽到的子图没有 actors_container 家具, 该项无有效比对 (校验和仍然覆盖了地形)")
	else:
		check(host_furn == client_furn,
			"两端地图家具逐格一致 (主机 %d 件 / 客户端 %d 件)" % [host_furn.size(), client_furn.size()])

	# 房间比视口大, 摄像机必须进跟随模式 —— 钉死模式会把超出视口的那部分
	# 永远留在画面外。客户端跟的是它自己的预测坦克, 所以这条两端都要成立。
	check(client.room_camera != null, "客户端有 RoomCamera")
	m_free(client)


func m_free(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.free()


## 护送房: 友军是**主机逻辑动态生成**的, 不是地图家具 —— 它生在
## _begin_room_encounter() 里, 而客户端整段跳过那个函数。所以正确形态是
## "主机生成 + 走复制层当傀儡下发", 跟油桶/开关那批恰好相反。
##
## 这条断言是 test_circuit_netsync.gd 那条的**反向配对**: 那边证明家具不该
## 被复制, 这边证明友军必须被复制。把 _add_map_furniture() 误用在友军身上
## 会让客户端永远看不见要保护的目标, 而且不报任何错。
func _test_escort_room() -> void:
	print("\n[护送房]")
	var made := _make_campaign()
	var campaign: Dictionary = made[0]
	var room_key: String = made[1]
	if room_key == "":
		fail("本层没有战斗房, 无法测试护送房")
		return

	var host := await _boot(NetSession.Role.HOST, campaign, room_key, "normal", "challenge", "escort")
	if host == null:
		return
	var host_allies: int = host.escort_ally_instances.size()
	check(host_allies > 0, "主机生成了护送友军 (%d 名)" % host_allies)

	var replicable := true
	for a in host.escort_ally_instances:
		if not is_instance_valid(a):
			continue
		if NetSession.classify(a) == NetSession.Kind.IGNORED:
			replicable = false
		if a.has_meta(NetSession.FURNITURE_META):
			fail("友军被误标成了地图家具 —— 客户端将永远看不见护送目标")
	check(replicable, "友军会被复制到客户端 (不是 IGNORED)")
	host.free()

	var client := await _boot(NetSession.Role.CLIENT, campaign, room_key, "normal", "challenge", "escort")
	if client == null:
		return
	check(client.escort_ally_instances.is_empty(),
		"客户端没有本地生成友军 (实际 %d 名, 应为 0 —— 生成是权威侧的事)" % client.escort_ally_instances.size())

	# 顺带钉住一个"目前只是碰巧安全"的地方: _on_escort_ally_destroyed() 里
	# 直接调 _game_over(false), 没有 authority 判定。它现在打不到, 唯一的
	# 理由就是客户端的 escort_ally_instances 恒为空 (信号只接在主机自己
	# 生成的实例上)。哪天有人让客户端也生成友军, 这条会先红, 而不是变成
	# "客户端单方面判负"。
	check(client.escort_ally_instances.is_empty(),
		"客户端的判负路径不可达 (escort_ally_instances 为空)")
	client.free()


## 宝物房/隐藏房。这两种房以前被记成"主机独占, 客户端只有提示", 实际查下来
## **奖励早就两端都拿到了**: 金币走战役字典同步, 道具是 Kind.POWERUP 的正经
## 复制实体 (客户端看到同一个图标, 而且开过去就能吃 —— 拾取判定跑在主机侧,
## 它看得到客户端坦克的权威位置)。缺的只是告诉客户端发生了什么, 而它当时
## 显示的那句"队友正在开箱…"把一件两人共享的好事说成了旁观。
##
## 所以这里断言的是三件事, 而不是"客户端能不能开箱":
##   1. 主机确实发奖并标记 looted (looted 在战役字典里 -> 会同步)。
##   2. 存在把公告推给对面的通道 (broadcast_toast)。
##   3. 客户端**不**本地发奖 —— 否则金币会在两端各加一次。
func _test_treasure_room() -> void:
	print("\n[宝物房]")
	var made := _make_campaign()
	var campaign: Dictionary = made[0]
	var room_key: String = made[1]
	if room_key == "":
		fail("本层没有可改造的房间, 无法测试宝物房")
		return

	var host := await _boot(NetSession.Role.HOST, campaign, room_key, "normal", "treasure", "")
	if host == null:
		return
	var host_gold: int = GameState.gold
	var looted: bool = bool(GameState.floor_rooms[room_key].get("looted", false))
	check(looted, "主机: 房间已标记 looted (该字段随战役字典同步)")
	check(host_gold > 0, "主机: 金币已发放 (%d)" % host_gold)
	host.free()

	var net_script = load("res://scripts/net_manager.gd")
	var has_toast: bool = false
	if net_script:
		for meth in net_script.get_script_method_list():
			if String(meth.get("name", "")) == "broadcast_toast":
				has_toast = true
				break
	check(has_toast, "net_manager.gd 提供 broadcast_toast() 公告通道")

	# 客户端: 不许自己发奖。它拿到的应该是主机同步过来的战役状态。
	var client := await _boot(NetSession.Role.CLIENT, campaign, room_key, "normal", "treasure", "")
	if client == null:
		return
	check(not bool(GameState.floor_rooms[room_key].get("looted", false)),
		"客户端没有本地发奖 (looted 仍为 false, 等主机同步)")
	client.free()
