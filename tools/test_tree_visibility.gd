extends SceneTree

## 树林的可见性: 坦克钻进林子以后不能彻底消失。
##
## 树冠画在坦克*上面* (z_index=10) 而且是 100% 不透明的, 所以在加这套机制之前,
## 开进树林的坦克是完全隐形的 —— 玩家既看不到林子里有没有敌人, 也看不到自己
## 在哪。这个测试锁住"有坦克压着的那几格会淡下去、走开会恢复"。
##
## 它也锁住反面: 淡下去*不能*淡到全透。树林的战术价值就是遮蔽, 全透等于这块
## 地形不存在。所以 TREE_REVEAL_ALPHA 必须落在 (0, 1) 之间。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_tree_visibility.gd

const MainGameScript = preload("res://scripts/main.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _tick(n: int) -> void:
	for i in range(n):
		await process_frame


func _init() -> void:
	print("==================================================")
	print(">>> TREE VISIBILITY TEST <<<")
	print("==================================================")

	_check_constants()
	await _check_reveal()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL TREE VISIBILITY CHECKS PASSED! <<<")
		quit(0)


func _check_constants() -> void:
	print("\n--- 常量 ---")
	var a: float = MainGameScript.TREE_REVEAL_ALPHA
	if a <= 0.0:
		fail("TREE_REVEAL_ALPHA=%.2f 是全透 —— 树林失去遮蔽价值, 这块地形就没意义了" % a)
	elif a >= 1.0:
		fail("TREE_REVEAL_ALPHA=%.2f 等于不透明 —— 坦克进林子还是看不见" % a)
	else:
		ok("TREE_REVEAL_ALPHA=%.2f, 既能看出人影又保留遮蔽" % a)


func _check_reveal() -> void:
	print("\n--- 实战场景 ---")
	var scene = load("res://scenes/main.tscn")
	if scene == null:
		fail("main.tscn 加载失败")
		return
	var main = scene.instantiate()
	root.add_child(main)
	await _tick(3)

	if main.tree_sprites.is_empty():
		# 地图是按楼层/battle_type 选的, 未必每张都有树。自己塞一格进去,
		# 测的是机制而不是"这张图恰好长了树"。
		var pos := Vector2(5.5 * main.TILE_SIZE, 5.5 * main.TILE_SIZE)
		main._spawn_tile("trees", pos, main.tex_trees)
		await _tick(1)
	if main.tree_sprites.is_empty():
		fail("树瓦片没能登记进 tree_sprites")
		main.queue_free()
		return
	ok("登记了 %d 格树林" % main.tree_sprites.size())

	var cell = main.tree_sprites.keys()[0]
	var spr = main.tree_sprites[cell]
	if spr.z_index <= 0:
		fail("树冠 z_index=%d, 没有画在坦克上面 —— 那就谈不上遮蔽" % spr.z_index)
	else:
		ok("树冠 z_index=%d, 画在坦克之上" % spr.z_index)

	var p1 = main.p1_instance
	if p1 == null or not is_instance_valid(p1):
		fail("战场里没有 P1")
		main.queue_free()
		return

	# 把玩家挪到别处, 确认树是满不透明的
	p1.global_position = main.map_container.to_global(
		Vector2((cell.x + 6) * main.TILE_SIZE, (cell.y + 6) * main.TILE_SIZE))
	await _tick(30)
	if spr.modulate.a < 0.99:
		fail("附近没有坦克, 树冠却是半透的 (a=%.2f)" % spr.modulate.a)
	else:
		ok("无人时树冠完全不透明 (a=%.2f)" % spr.modulate.a)

	# 开进这一格
	var center := Vector2((cell.x + 0.5) * main.TILE_SIZE, (cell.y + 0.5) * main.TILE_SIZE)
	p1.global_position = main.map_container.to_global(center)
	await _tick(30)
	var a_in: float = spr.modulate.a
	if a_in > 0.9:
		fail("坦克已经在这一格里, 树冠仍然不透明 (a=%.2f) —— 坦克是隐形的" % a_in)
	elif a_in <= 0.02:
		fail("树冠淡到全透 (a=%.2f), 遮蔽价值没了" % a_in)
	else:
		ok("坦克进入后树冠淡到 a=%.2f, 人影可见但仍有遮蔽" % a_in)

	# 骑在两格中间时, 被压住的两格都要淡 —— 只算中心格的话, 探进邻格的半截车
	# 还是隐形的, 而那正是最需要看见的部分
	var right_cell = Vector2i(cell.x + 1, cell.y)
	if not main.tree_sprites.has(right_cell):
		var rpos := Vector2((right_cell.x + 0.5) * main.TILE_SIZE, (right_cell.y + 0.5) * main.TILE_SIZE)
		main._spawn_tile("trees", rpos, main.tex_trees)
		await _tick(1)
	var spr_r = main.tree_sprites.get(right_cell)
	if spr_r == null:
		fail("相邻格的树没能登记")
	else:
		# 压在两格交界线上
		p1.global_position = main.map_container.to_global(
			Vector2((cell.x + 1.0) * main.TILE_SIZE, (cell.y + 0.5) * main.TILE_SIZE))
		await _tick(30)
		if spr.modulate.a > 0.9 or spr_r.modulate.a > 0.9:
			fail("坦克骑在两格之间, 却只有一格淡了 (左 a=%.2f 右 a=%.2f)"
				% [spr.modulate.a, spr_r.modulate.a])
		else:
			ok("跨格时两格都淡了 (左 a=%.2f 右 a=%.2f)" % [spr.modulate.a, spr_r.modulate.a])

	# 开了光学迷彩的 MIRAGE 不该淡树 —— 它正伪装成一棵树, 周围真树淡一圈
	# 等于替它在地图上打了个标记
	p1.global_position = main.map_container.to_global(
		Vector2((cell.x + 6) * main.TILE_SIZE, (cell.y + 6) * main.TILE_SIZE))
	await _tick(40)
	var EnemyTank = load("res://scripts/enemy.gd")
	main._instantiate_enemy(Vector2(200, 200), EnemyTank.EnemyType.MIRAGE, false, 0)
	var mir: Node = null
	for c in main.actors_container.get_children():
		if "enemy_type" in c and c.enemy_type == EnemyTank.EnemyType.MIRAGE:
			mir = c
			break
	if mir == null:
		fail("MIRAGE 没能实例化")
	else:
		mir.global_position = main.map_container.to_global(center)
		# 冻住它的 _physics_process: MIRAGE 的迷彩状态机是"静止 0.45 秒才隐身、
		# 一动就解除", 让 AI 继续跑的话它会自己把 is_camouflaged 翻回 false,
		# 测的就不是这里要测的东西了。游戏里"已隐身"本来就蕴含"没在动"。
		mir.set_physics_process(false)
		mir.is_camouflaged = true
		await _tick(30)
		if spr.modulate.a < 0.9:
			fail("已隐身的 MIRAGE 把树淡掉了 (a=%.2f) —— 等于自曝位置" % spr.modulate.a)
		else:
			ok("已隐身的 MIRAGE 不触发淡出 (a=%.2f), 伪装保住了" % spr.modulate.a)
		# 而一旦解除迷彩就该正常淡出
		mir.is_camouflaged = false
		await _tick(30)
		if spr.modulate.a > 0.9:
			fail("MIRAGE 解除迷彩后树冠仍不透明 (a=%.2f)" % spr.modulate.a)
		else:
			ok("MIRAGE 解除迷彩后正常淡出 (a=%.2f)" % spr.modulate.a)
		mir.free()
		await _tick(1)

	# 走开要恢复
	p1.global_position = main.map_container.to_global(
		Vector2((cell.x + 6) * main.TILE_SIZE, (cell.y + 6) * main.TILE_SIZE))
	await _tick(40)
	if spr.modulate.a < 0.99:
		fail("坦克走开后树冠没恢复 (a=%.2f)" % spr.modulate.a)
	else:
		ok("坦克离开后树冠恢复不透明")

	main.queue_free()
	await _tick(1)
