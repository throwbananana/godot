extends SceneTree

## 逐帧开销剖析器 —— 回答"卡在哪", 而不是"我猜卡在哪"。
##
## 它是把尺子, 不是闸门: 没有任何断言, 只把 main.tscn 真正跑起来, 按帧采
## 引擎自己报的 TIME_PROCESS / TIME_PHYSICS_PROCESS, 然后**逐个关掉子系统再测一遍**
## (消融法)。关掉某一项之后掉下来的那部分时间, 就是那一项的实际成本 ——
## 比在源码里手插计时器可靠, 因为不用改被测代码, 也不会漏掉它调用到的东西。
##
## 注意两条读数纪律:
##   1. **headless 没有渲染**, 所以这里量到的是脚本 + 物理, 不含 draw call /
##      材质切换 / PointLight2D。如果消融表显示脚本开销很平, 而游戏里确实卡,
##      那瓶颈在 GPU 侧, 得换别的办法量。
##   2. **卡顿看的是尾部不是均值。** 一帧 30ms 的尖峰, 摊进 600 帧的均值里
##      只有 0.05ms, 完全看不见。所以下面同时报 p50/p95/p99/max。
##
## 用法:
##   godot --headless --path . --script tools/profile_frame_cost.gd
##   godot --headless --path . --script tools/profile_frame_cost.gd -- --size huge
##   godot --headless --path . --script tools/profile_frame_cost.gd -- --frames 900 --enemies 12

const EnemyScript = preload("res://scripts/enemy.gd")

var room_size := "normal"
var frames_per_pass := 420
var extra_enemies := 6
var main_inst: Node = null
var room_key := ""

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--size":
				i += 1
				room_size = args[i]
			"--frames":
				i += 1
				frames_per_pass = int(args[i])
			"--enemies":
				i += 1
				extra_enemies = int(args[i])
		i += 1
	call_deferred("_run")

func _run() -> void:
	print("==================================================")
	print(">>> FRAME COST PROFILE (size=%s frames=%d enemies=+%d) <<<" % [room_size, frames_per_pass, extra_enemies])
	print("==================================================")

	GameState.reset_campaign(1)
	GameState.ensure_floor_ready()

	main_inst = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame
	await process_frame

	room_key = _first_combat_room()
	if room_key == "":
		print("[ABORT] 本层没有战斗房")
		quit(1)
		return

	GameState.floor_rooms[room_key]["size"] = room_size
	GameState.floor_rooms[room_key]["cleared"] = false
	GameState.floor_rooms[room_key]["type"] = "normal"
	GameState.floor_rooms[room_key]["challenge_mode"] = ""
	main_inst.enter_room(room_key, -1)
	await process_frame
	await process_frame

	await _restage()
	_print_scene_census()

	# **消融必须夹在两次 baseline 之间。** 第一版是 baseline 打头、后面一串
	# 消融各测一趟, 结果每一趟都比上一趟便宜 —— 不管关掉的是什么。原因不是
	# 消融生效了, 而是战斗场面本身在冷却: 敌人陆续死光、特效播完、音效不再
	# 触发, 于是"时间"成了真正的自变量, 表里每一行的"节省"全是它的假象。
	# 现在每个消融项都重新读一次 baseline 作参照, 并在最后报告 baseline 自己
	# 的漂移量 —— 漂移比测出来的"节省"还大的话, 这一趟数据就不能用。
	var base_first := await _measure("baseline")
	var rows: Array = []
	rows.append(await _paired("no sound", _ablate_sound))
	rows.append(await _paired("no tree fade", _ablate_trees))
	rows.append(await _paired("no darkness fog", _ablate_fog))
	rows.append(await _paired("no enemy AI", _ablate_enemy_ai))
	rows.append(await _paired("no water anim", _ablate_water))
	rows.append(await _paired("no building _process", _ablate_buildings))
	await _restage()
	var base_last := await _measure("baseline")

	print("\n============ 消融表 ============")
	print("%-24s %9s %9s %9s   %s" % ["pass", "p50", "p95", "max", "相对同段 baseline"])
	print("%-24s %9.3f %9.3f %9.3f   (起始基准)" % ["baseline (首)", base_first["p50"], base_first["p95"], base_first["max"]])
	for r in rows:
		print("%-24s %9.3f %9.3f %9.3f   %+.3f ms (p50)" % [r["name"], r["p50"], r["p95"], r["max"], r["p50"] - r["ref_p50"]])
	print("%-24s %9.3f %9.3f %9.3f   (结束基准)" % ["baseline (末)", base_last["p50"], base_last["p95"], base_last["max"]])

	var drift: float = absf(base_last["p50"] - base_first["p50"])
	print("\nbaseline 漂移 (首 vs 末, p50): %.3f ms" % drift)
	if drift > 0.5:
		print("  [WARN] 漂移偏大 —— 场景在采样期间本身就在变, 上表的差值不可信。")
	print("(单位 ms/帧, 仅脚本+物理, 不含渲染)")
	quit(0)

## 跑一趟"消融" + 紧挨着一趟"还原", 用还原那趟当参照。两趟在时间上相邻,
## 所以场面冷却带来的漂移对二者影响接近, 相减能把它约掉。
func _paired(label: String, ablate: Callable) -> Dictionary:
	await _restage()
	var r: Dictionary = await ablate.call()
	r["name"] = label
	await _restage()
	var ref := await _measure("ref")
	r["ref_p50"] = ref["p50"]
	return r

## 把场面恢复到同一个起点: 重进房间 (清掉残留的特效/尸体/子弹) 再补满敌人,
## 然后空跑一段让建图和贴图缓存的一次性开销过去。
##
## 每一趟采样前都做一次, 是因为战斗场面自己会冷却 —— 不重置的话"关掉某项之后
## 便宜了"和"过了几秒敌人死光了"根本分不开, 这正是第一版消融表的毛病。
func _restage() -> void:
	# **cleared 必须重新压回 false。** 只调 enter_room() 的话, 打完一遍的房间
	# 是"已清空"状态: 不再刷怪、门也开着, 于是第二趟之后测的全是一间空房 ——
	# 第二版消融表里除首行外全部落到 0.8ms, 就是这么来的, 看着像"优化生效了"。
	GameState.floor_rooms[room_key]["cleared"] = false
	GameState.floor_rooms[room_key]["size"] = room_size
	GameState.floor_rooms[room_key]["type"] = "normal"
	main_inst.enter_room(room_key, -1)
	await process_frame
	_spawn_extra_enemies(extra_enemies)
	for _w in range(90):
		await process_frame

## 直接掐掉发声 —— _spawn_player() 在 _prewarming 为真时早退, 波形照算 (其实
## 已经在缓存里), 但不建 AudioStreamPlayer 节点、不播放。
func _ablate_sound() -> Dictionary:
	SoundManager._prewarming = true
	var r := await _measure("no sound")
	SoundManager._prewarming = false
	return r

func _first_combat_room() -> String:
	for key in GameState.floor_rooms:
		var r = GameState.floor_rooms[key]
		if r.get("type", "") == "normal" and r.get("size", "normal") == "normal":
			return key
	return ""

func _spawn_extra_enemies(n: int) -> void:
	if n <= 0:
		return
	var scene := load("res://scenes/enemy.tscn")
	var types := [
		EnemyScript.EnemyType.BASIC, EnemyScript.EnemyType.FAST,
		EnemyScript.EnemyType.POWER, EnemyScript.EnemyType.ARMOR,
		EnemyScript.EnemyType.SUICIDE, EnemyScript.EnemyType.SNIPER,
	]
	for i in range(n):
		var e = scene.instantiate()
		e.enemy_type = types[i % types.size()]
		main_inst.actors_container.add_child(e)
		e.position = Vector2(
			(2 + (i * 3) % maxi(1, main_inst.GRID_W - 4) + 0.5) * 48.0,
			(2 + (i * 2) % maxi(1, main_inst.GRID_H - 6) + 0.5) * 48.0)

func _print_scene_census() -> void:
	var tiles: int = main_inst.map_container.get_child_count()
	var actors: int = main_inst.actors_container.get_child_count()
	var enemies := get_nodes_in_group("enemies").size()
	print("\n--- 场景规模 ---")
	print("  GRID           %d x %d" % [main_inst.GRID_W, main_inst.GRID_H])
	print("  MapContainer   %d 个子节点" % tiles)
	print("  ActorsContainer %d 个子节点 (敌人 %d)" % [actors, enemies])
	print("  tree_sprites   %d" % main_inst.tree_sprites.size())
	print("  water_sprites  %d" % main_inst.water_sprites.size())
	print("  节点总数       %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

## 采 frames_per_pass 帧, 返回 {name, p50, p95, p99, max}。
##
## 用 Performance 的 TIME_PROCESS / TIME_PHYSICS_PROCESS 而不是自己掐
## Time.get_ticks_usec(): headless 不限帧, 空闲帧和物理帧的比例跟真实运行
## 完全不一样, 自己掐的"每帧墙钟"会把两者混在一起, 没法解释。
func _measure(name: String) -> Dictionary:
	var samples: Array[float] = []
	for _f in range(frames_per_pass):
		await process_frame
		var t := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		samples.append(t)
	samples.sort()
	return {
		"name": name,
		"p50": samples[int(samples.size() * 0.50)],
		"p95": samples[int(samples.size() * 0.95)],
		"p99": samples[int(samples.size() * 0.99)],
		"max": samples[samples.size() - 1],
	}

func _ablate_trees() -> Dictionary:
	var saved: Dictionary = main_inst.tree_sprites.duplicate()
	main_inst.tree_sprites.clear() # _update_tree_transparency() 在空字典上直接早退
	var r := await _measure("no tree fade")
	main_inst.tree_sprites = saved
	return r

func _ablate_fog() -> Dictionary:
	var fogs: Array = []
	for n in get_nodes_in_group("darkness_fog"):
		fogs.append(n)
	if fogs.is_empty():
		for n in main_inst.get_children():
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("darkness_fog.gd"):
				fogs.append(n)
	for n in fogs:
		n.set_process(false)
	var r := await _measure("no darkness fog" if not fogs.is_empty() else "no fog (无雾节点)")
	for n in fogs:
		n.set_process(true)
	return r

func _ablate_enemy_ai() -> Dictionary:
	var list := get_nodes_in_group("enemies")
	for n in list:
		n.set_physics_process(false)
	var r := await _measure("no enemy AI")
	for n in list:
		if is_instance_valid(n):
			n.set_physics_process(true)
	return r

func _ablate_water() -> Dictionary:
	var saved: Array = main_inst.water_sprites.duplicate()
	main_inst.water_sprites.clear()
	var r := await _measure("no water anim")
	main_inst.water_sprites = saved
	return r

func _ablate_buildings() -> Dictionary:
	var touched: Array = []
	for n in main_inst.actors_container.get_children():
		if n.is_in_group("buildings") or n.is_in_group("building"):
			touched.append(n)
			n.set_process(false)
			n.set_physics_process(false)
	var r := await _measure("no building _process")
	for n in touched:
		if is_instance_valid(n):
			n.set_process(true)
			n.set_physics_process(true)
	return r
