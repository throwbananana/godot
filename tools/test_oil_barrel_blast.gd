extends SceneTree

## 油桶爆炸的**落点**测试。
##
## 这里查的不是"有没有炸", 而是"炸在不在该炸的地方" —— 两个 bug 都属于
## 渲染本身完全成功、只是画错了位置, 所以既不会报错也不会被编译检查抓到:
##
##  1. oil_barrel.gd::detonate() 生成 explosion.tscn 时, 必须先 add_child
##     再设 global_position。反过来写的话, 节点还没进场景树, 没有父级变换
##     可言, 赋 global_position 退化成赋 position; 随后挂到 ActorsContainer
##     (在 GameArea 下, 偏移 48,48) 上时那份偏移又叠了一次, 火球画到桶的
##     右下方整整一格。同一次爆炸的震波/碎屑走 VFXAnimator (内部就是先入树
##     再设全局坐标) 位置正确, 伤害判定的 query.transform 也用的是真全局
##     坐标 —— 所以错位的只有火球, 玩家看到的爆心和实际杀伤范围对不上。
##
##  2. explosion.gd 给夜战迷雾打的那道闪光, 原本写在 _ready() 里直接读
##     global_position。但 _ready() 是在 add_child() 期间跑的, 比调用方
##     赋坐标早一步, 读到的是默认 (0,0) 经父级变换的结果; 减掉
##     game_area.global_position 正好抵消, 于是**每一次**爆炸都在地图左上角
##     点灯。这条影响的不止油桶, 而是所有生成 explosion.tscn 的地方
##     (地雷/子弹/鹰巢/炮塔/围墙), 只是仅在 night_ops / night_bombs 看得见。
##
## 用 stub 而不是启动 main.tscn: explosion.gd 和 VFXAnimator 对"战场控制器"
## 全是鸭子类型访问 (current_scene 上的 game_area / darkness_fog_instance),
## 所以这两个字段就够了 —— 同 tools/_train_stub.gd 的思路。

const EPS := 1.0

var failures: int = 0


class FogStub extends Node:
	## 只记录 add_flash 的调用, 不做任何着色。
	var flashes: Array = []

	func add_flash(pos: Vector2, radius: float = 160.0, duration: float = 0.35) -> void:
		flashes.append({"pos": pos, "radius": radius, "duration": duration})


class MainStub extends Node2D:
	## main.tscn 的最小替身: 只暴露爆炸链路真正会去摸的两个字段。
	var game_area: Node2D = null
	var darkness_fog_instance: Node = null


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	failures += 1
	print("  [FAIL] %s" % msg)


func _ok(msg: String) -> void:
	print("  [ok]   %s" % msg)


func _run() -> void:
	print("==================================================")
	print(">>> OIL BARREL BLAST PLACEMENT TEST <<<")
	print("==================================================")

	# --- 搭一棵和 main.tscn 同构的最小场景树 ---
	var main_stub := MainStub.new()
	root.add_child(main_stub)
	current_scene = main_stub

	var game_area := Node2D.new()
	game_area.name = "GameArea"
	game_area.position = Vector2(48, 48)   # 和 main.tscn 里一致
	main_stub.add_child(game_area)

	var actors := Node2D.new()
	actors.name = "ActorsContainer"
	game_area.add_child(actors)

	var fog := FogStub.new()
	main_stub.add_child(fog)
	main_stub.game_area = game_area
	main_stub.darkness_fog_instance = fog

	# --- 放一个油桶, 位置取格心 (4.5, 4.5) ---
	var barrel_scene: PackedScene = load("res://scenes/buildings/oil_barrel.tscn")
	if not barrel_scene:
		_fail("oil_barrel.tscn 加载失败")
		_finish()
		return
	var barrel = barrel_scene.instantiate()
	barrel.position = Vector2(216.0, 216.0)
	actors.add_child(barrel)
	await process_frame

	var expect_global: Vector2 = barrel.global_position
	var expect_local: Vector2 = expect_global - game_area.global_position
	print("  桶: local=%s  global=%s" % [str(barrel.position), str(expect_global)])
	if not expect_global.is_equal_approx(Vector2(264.0, 264.0)):
		_fail("测试自身的场景树搭错了: 桶的全局坐标应为 (264,264), 实为 %s" % str(expect_global))

	var before := {}
	for ch in actors.get_children():
		before[ch] = true

	barrel.detonate()
	await process_frame   # 让 call_deferred 的夜战闪光排上

	# --- 1. 火球必须落在桶身上 ---
	var fireball: Node2D = null
	for ch in actors.get_children():
		if before.has(ch):
			continue
		if ch is Node2D and ch.scene_file_path == "res://scenes/explosion.tscn":
			fireball = ch
			break

	if fireball == null:
		_fail("没有找到生成出来的 explosion.tscn 实例")
	else:
		var d: float = fireball.global_position.distance_to(expect_global)
		if d > EPS:
			_fail("火球画偏了 %.1f px (应在 %s, 实在 %s) —— 差 %.2f 格"
				% [d, str(expect_global), str(fireball.global_position), d / 48.0])
		else:
			_ok("火球落点与油桶一致: %s" % str(fireball.global_position))

	# --- 2. 夜战闪光必须打在爆点, 不是地图左上角 ---
	if fog.flashes.is_empty():
		_fail("一次夜战闪光都没记录到 —— stub 没被调用, 这条检查是空的")
	else:
		var bad: Array = []
		for f in fog.flashes:
			if (f["pos"] as Vector2).distance_to(expect_local) > EPS:
				bad.append(str(f["pos"]))
		if bad.is_empty():
			_ok("%d 道夜战闪光全部落在爆点 %s" % [fog.flashes.size(), str(expect_local)])
		else:
			_fail("%d/%d 道夜战闪光偏离爆点 %s: %s"
				% [bad.size(), fog.flashes.size(), str(expect_local), ", ".join(bad)])

	_finish()


func _finish() -> void:
	# 收尾释放, 否则退出时会刷一行 ObjectDB instances leaked
	if current_scene and is_instance_valid(current_scene):
		var s := current_scene
		current_scene = null
		s.free()
	print("--------------------------------------------------")
	if failures == 0:
		print("🎉 爆炸落点全部正确")
		quit(0)
	else:
		print("❌ %d 项失败" % failures)
		quit(1)
