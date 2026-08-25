extends SceneTree

const PipeConduitScript = preload("res://scripts/buildings/pipe_conduit.gd")
const BulletScript = preload("res://scripts/bullet.gd")
const ShopDialogScript = preload("res://scripts/shop_dialog.gd")
const BuilderControllerScript = preload("res://scripts/builder_controller.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING CONDUIT PIPE (导流管道) TESTS <<<")
	print("==================================================")

	_test_bullet_entering_intake_redirects_trajectory()
	_test_all_four_orientation_presets()
	_test_non_entrance_hit_damages_and_destroys_pipe()
	_test_shop_and_builder_integration()

	print("\n>>> ALL CONDUIT PIPE (导流管道) TESTS PASSED! <<<")
	quit(0)

func _test_bullet_entering_intake_redirects_trajectory() -> void:
	print("\n[STEP 1] 子弹从入口打入 -> 改变方向并从出口射出，且管道不扣血...")
	var pipe = PipeConduitScript.new()
	root.add_child(pipe)
	pipe.global_position = Vector2(300, 300)
	pipe.set_orientation(PipeConduitScript.Orientation.LEFT_TO_UP)

	var initial_hp = pipe.current_health

	# 创建一个从左向右飞行的子弹 (direction = Vector2.RIGHT)
	var bullet = Area2D.new()
	bullet.set_script(BulletScript)
	bullet.direction = Vector2.RIGHT
	bullet.damage = 1
	bullet.global_position = Vector2(280, 300)
	root.add_child(bullet)

	# 模拟子弹打中管道
	var absorbed = pipe.handle_bullet_hit(bullet, bullet.global_position, bullet.direction)

	assert(absorbed == true, "子弹顺着入口方向打入，handle_bullet_hit 必须返回 true (吸收重定向)")
	assert(bullet.direction == Vector2.UP, "子弹方向必须被重定向为出口方向 Vector2.UP，实际为 %s" % bullet.direction)
	assert(bullet.global_position.y < 300.0, "子弹必须移动到管道上方出口处 (Y < 300)，实际 Y=%f" % bullet.global_position.y)
	assert(pipe.current_health == initial_hp, "子弹从入口正常导流时，管道不应扣血 (HP 保持 %d)" % initial_hp)
	assert(not bullet.is_queued_for_deletion(), "导流后的子弹不应被销毁")

	bullet.queue_free()
	pipe.queue_free()
	print("  [PASS] 子弹从入口打入成功重定向为出口方向，管道状态完好。")

func _test_all_four_orientation_presets() -> void:
	print("\n[STEP 2] 测试 4 种方向转角预设的导流正确性...")

	var test_cases = [
		{
			"orient": PipeConduitScript.Orientation.LEFT_TO_UP,
			"in_dir": Vector2.RIGHT,
			"expected_out": Vector2.UP,
			"label": "LEFT -> UP"
		},
		{
			"orient": PipeConduitScript.Orientation.UP_TO_RIGHT,
			"in_dir": Vector2.DOWN,
			"expected_out": Vector2.RIGHT,
			"label": "UP -> RIGHT"
		},
		{
			"orient": PipeConduitScript.Orientation.RIGHT_TO_DOWN,
			"in_dir": Vector2.LEFT,
			"expected_out": Vector2.DOWN,
			"label": "RIGHT -> DOWN"
		},
		{
			"orient": PipeConduitScript.Orientation.DOWN_TO_LEFT,
			"in_dir": Vector2.UP,
			"expected_out": Vector2.LEFT,
			"label": "DOWN -> LEFT"
		}
	]

	for tc in test_cases:
		var pipe = PipeConduitScript.new()
		root.add_child(pipe)
		pipe.global_position = Vector2(200, 200)
		pipe.set_orientation(tc["orient"])

		var bullet = Area2D.new()
		bullet.set_script(BulletScript)
		bullet.direction = tc["in_dir"]
		bullet.damage = 1
		bullet.global_position = Vector2(200, 200)
		root.add_child(bullet)

		var handled = pipe.handle_bullet_hit(bullet, bullet.global_position, bullet.direction)
		assert(handled == true, "预设 %s 迎接入射子弹应返回 true" % tc["label"])
		assert(bullet.direction == tc["expected_out"], "预设 %s 射出方向应为 %s，实际为 %s" % [tc["label"], tc["expected_out"], bullet.direction])

		bullet.queue_free()
		pipe.queue_free()

	print("  [PASS] 全部 4 种正交转角预设导流均通过验证。")

func _test_non_entrance_hit_damages_and_destroys_pipe() -> void:
	print("\n[STEP 3] 在非入口方向受击 -> 管道受到伤害，可被彻底破坏...")
	var pipe = PipeConduitScript.new()
	root.add_child(pipe)
	pipe.global_position = Vector2(400, 400)
	# 设为仅接受从左向右 (Vector2.RIGHT) 打入
	pipe.set_orientation(PipeConduitScript.Orientation.LEFT_TO_UP)
	pipe.max_health = 3
	pipe.current_health = 3

	# 1. 从上方朝下射击 (Vector2.DOWN，非入口方向)
	var bullet1 = Area2D.new()
	bullet1.set_script(BulletScript)
	bullet1.direction = Vector2.DOWN
	bullet1.damage = 1
	root.add_child(bullet1)

	var absorbed1 = pipe.handle_bullet_hit(bullet1, pipe.global_position, bullet1.direction)
	assert(absorbed1 == false, "非入口方向受击 handle_bullet_hit 必须返回 false")
	assert(pipe.current_health == 2, "管道受击后生命值应减至 2，实际为 %d" % pipe.current_health)

	# 2. 从右侧朝左射击 (Vector2.LEFT，非入口方向)
	var bullet2 = Area2D.new()
	bullet2.set_script(BulletScript)
	bullet2.direction = Vector2.LEFT
	bullet2.damage = 1
	root.add_child(bullet2)

	var absorbed2 = pipe.handle_bullet_hit(bullet2, pipe.global_position, bullet2.direction)
	assert(absorbed2 == false, "非入口方向受击 handle_bullet_hit 必须返回 false")
	assert(pipe.current_health == 1, "管道再次受击后生命值应减至 1，实际为 %d" % pipe.current_health)

	# 3. 致命击破 (伤害 1，触发破坏)
	var bullet3 = Area2D.new()
	bullet3.set_script(BulletScript)
	bullet3.direction = Vector2.LEFT
	bullet3.damage = 1
	root.add_child(bullet3)

	var absorbed3 = pipe.handle_bullet_hit(bullet3, pipe.global_position, bullet3.direction)
	assert(absorbed3 == false, "致命一击应返回 false")
	assert(pipe.is_destroyed == true or pipe.current_health <= 0, "管道生命值耗尽后必须标记为已摧毁")
	assert(pipe.is_queued_for_deletion(), "管道被摧毁后必须进入 queue_free 删除队列")

	bullet1.queue_free()
	bullet2.queue_free()
	bullet3.queue_free()
	print("  [PASS] 侧面/非入口方向受击正确扣除生命值并在耗尽时破坏管道。")

func _test_shop_and_builder_integration() -> void:
	print("\n[STEP 4] 验证商店 (ShopDialog)、建造器 (BuilderController) 与场景完整性...")

	# 1. 验证商店物资清单中包含 pipe_conduit
	var has_pipe_in_shop = false
	for item in ShopDialogScript.BUILDING_ITEMS:
		if item["id"] == "pipe_conduit":
			has_pipe_in_shop = true
			assert(item.has("cost") and item["cost"] > 0, "管道商品必须有有效售价")
			assert(item.has("icon"), "管道商品必须配置图标")
			break
	assert(has_pipe_in_shop, "商店 BUILDING_ITEMS 列表中必须包含 pipe_conduit 建筑")

	# 2. 验证 BuilderController 配置
	var builder = BuilderControllerScript.new()
	assert("PIPE" in BuilderControllerScript.StructureType, "BuilderController.StructureType 必须包含 PIPE 枚举")
	assert(builder.structure_ids.has(BuilderControllerScript.StructureType.PIPE), "structure_ids 必须映射 PIPE 到 pipe_conduit")
	builder.queue_free()

	# 3. 验证场景文件加载并实例化
	var scene = load("res://scenes/buildings/pipe_conduit.tscn")
	assert(scene != null, "scenes/buildings/pipe_conduit.tscn 必须能够成功加载")
	var inst = scene.instantiate()
	assert(inst != null, "pipe_conduit.tscn 必须能成功实例化")
	assert(inst.is_in_group("pipe_conduit"), "实例化对象必须属于 pipe_conduit 组")
	assert(inst.is_in_group("buildings") or inst.is_in_group("building"), "实例化对象必须属于 buildings 组")
	inst.queue_free()

	print("  [PASS] 商店、建造控制器及场景文件集成验证全部通过。")
