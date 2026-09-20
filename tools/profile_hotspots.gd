extends SceneTree

const VFXParticles = preload("res://scripts/vfx_particles.gd")

## 热点微基准 —— 按"每次调用多少微秒"量单个函数, 而不是量整帧。
##
## 为什么不用 profile_frame_cost.gd 的消融法: 那个测的是一整帧, 而战斗场景
## 每一帧的内容都在变 (敌人在死、特效在生灭), 于是"关掉 A 之后便宜了"和
## "过了两秒场面自然冷下来了"分不开 —— 实测第一版消融表里每一趟都比上一趟
## 便宜, 不管关的是什么, 那是时间在当自变量, 不是被消融的子系统。
## 微基准没有这个问题: 同一个调用重复 N 次, 除以 N。

var _lines: Array[String] = []

func _init() -> void:
	call_deferred("_run")

## 从 res://assets/sprites 底下收集 limit 张还没进缓存的图, 用来量冷加载。
func _collect_sprite_paths(limit: int) -> Array[String]:
	var out: Array[String] = []
	var dirs: Array[String] = ["res://assets/sprites"]
	while not dirs.is_empty() and out.size() < limit:
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "" and out.size() < limit:
			if da.current_is_dir():
				if not f.begins_with("."):
					dirs.append(d + "/" + f)
			elif f.ends_with(".png") and not f.ends_with("_n.png"):
				out.append(d + "/" + f)
			f = da.get_next()
		da.list_dir_end()
	return out

func _bench(label: String, iterations: int, fn: Callable) -> float:
	# 先跑几次热身: 第一次调用要装载脚本、建常量表, 摊进平均值里会虚高。
	for _w in range(mini(3, iterations)):
		fn.call()
	var t0 := Time.get_ticks_usec()
	for _i in range(iterations):
		fn.call()
	var us := float(Time.get_ticks_usec() - t0) / float(iterations)
	_lines.append("%-34s %9.1f us/次   %7.2f ms/60次" % [label, us, us * 60.0 / 1000.0])
	return us

func _run() -> void:
	print("==================================================")
	print(">>> HOTSPOT MICRO-BENCHMARK <<<")
	print("==================================================")

	# --- 1. 音效合成 (每个音效都是逐采样的 GDScript 循环) ---
	print("\n--- 音效合成 ---")
	_bench("SoundManager.play_shot", 40, func(): SoundManager.play_shot(self))
	_bench("SoundManager.play_hit_brick", 40, func(): SoundManager.play_hit_brick(self))
	_bench("SoundManager.play_hit_steel", 40, func(): SoundManager.play_hit_steel(self))
	_bench("SoundManager.play_explosion", 20, func(): SoundManager.play_explosion(self))
	_bench("SoundManager.play_laser", 20, func(): SoundManager.play_laser(self))
	_bench("SoundManager.play_pickup", 20, func(): SoundManager.play_pickup(self))
	_bench("SoundManager.play_level_up", 10, func(): SoundManager.play_level_up(self))
	_bench("SoundManager.play_victory", 10, func(): SoundManager.play_victory(self))
	for l in _lines:
		print("  " + l)
	_lines.clear()

	# --- 2. 特效节点 ---
	print("\n--- 特效 (VFXAnimator) ---")
	var holder := Node2D.new()
	root.add_child(holder)
	_bench("spawn_muzzle_flash", 60, func(): VFXAnimator.spawn_muzzle_flash(holder, Vector2(100, 100), 0.0))
	_bench("spawn_clay_debris", 40, func(): VFXAnimator.spawn_clay_debris(holder, Vector2(100, 100)))
	_bench("spawn_shockwave", 40, func(): VFXAnimator.spawn_shockwave(holder, Vector2(100, 100)))
	_bench("spawn_dust_puff", 40, func(): VFXAnimator.spawn_dust_puff(holder, Vector2(100, 100)))
	for l in _lines:
		print("  " + l)
	_lines.clear()

	# --- 2b. 运行时粒子层 ---
	print("\n--- 粒子 (VFXParticles) ---")
	var phost := Node2D.new()
	root.add_child(phost)
	_bench("emit(impact_spark)", 60, func(): VFXParticles.emit("impact_spark", phost, Vector2(100, 100), Vector2.RIGHT))
	_bench("emit(debris)", 60, func(): VFXParticles.emit("debris", phost, Vector2(100, 100), Vector2.UP))
	for l in _lines:
		print("  " + l)
	_lines.clear()
	# 稳态成本: 场上挂满粒子时每帧多花多少。
	#
	# **必须先量一个 0 颗的控制组再减。** headless 的空闲帧本底约 6.7ms/帧
	# (引擎自身的开销), 直接报"900 颗时 6.3ms/帧"会把本底当成粒子成本 ——
	# 第一版就是这么写的, 得出"粒子吃掉 38% 帧预算"的错误结论, 而真实净增
	# 只有 0.17ms。没有控制组的绝对值在这里毫无意义。
	var t_base := Time.get_ticks_usec()
	for _f in range(30):
		await process_frame
	var base_frame := float(Time.get_ticks_usec() - t_base) / 30.0

	for _i in range(90):
		VFXParticles.emit("debris", phost, Vector2(100, 100), Vector2.UP)
	var live: int = VFXParticles._live_particles
	var t_start := Time.get_ticks_usec()
	for _f in range(30):
		await process_frame
	var per_frame := float(Time.get_ticks_usec() - t_start) / 30.0
	print("  %-32s 本底 %.1f us/帧 -> %.1f us/帧, 净增 %.1f us (场上 %d 颗)" % [
		"满场粒子稳态", base_frame, per_frame, per_frame - base_frame, live])
	print("    注意: headless 不渲染, 所以这里只含积分开销, **不含 _draw 的绘制成本**。")
	phost.queue_free()
	await process_frame

	# --- 3. 贴图缓存命中 ---
	print("\n--- 贴图 ---")
	_bench("TextureHelper.get_tex (缓存命中)", 2000,
		func(): TextureHelper.get_tex("res://assets/sprites/tiles/tile_brick.png"))
	for l in _lines:
		print("  " + l)
	_lines.clear()

	# --- 3b. 贴图冷加载 (每张图第一次出现在战场上时才发生) ---
	print("\n--- 贴图冷加载 ---")
	var cold_paths := _collect_sprite_paths(160)
	var t0 := Time.get_ticks_usec()
	for p in cold_paths:
		TextureHelper.get_tex(p)
	var cold_us := float(Time.get_ticks_usec() - t0) / float(maxi(1, cold_paths.size()))
	print("  %-32s %9.1f us/张  (%d 张共 %.1f ms)" % [
		"TextureHelper.get_tex 冷加载", cold_us, cold_paths.size(), cold_us * cold_paths.size() / 1000.0])

	# --- 4. 目标检索 (敌人 AI 每帧都要用) ---
	print("\n--- 目标检索 ---")
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.enemy_type = 0
	root.add_child(enemy)
	var fake_players: Array = []
	for i in range(2):
		var p := Node2D.new()
		p.add_to_group("player")
		root.add_child(p)
		p.global_position = Vector2(200 + i * 50, 200)
		fake_players.append(p)
	await process_frame
	_bench("enemy._find_target()", 2000, func(): enemy._find_target())
	_bench("get_nodes_in_group('player')", 2000, func(): get_nodes_in_group("player"))
	for l in _lines:
		print("  " + l)
	_lines.clear()

	print("\n提示: 右列换算成 每帧发生 60 次 时的整帧开销, 用来判断值不值得优化。")
	quit(0)
