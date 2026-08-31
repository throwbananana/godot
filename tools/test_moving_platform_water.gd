extends SceneTree

## 移动平台过河的回归测试。
##
## 水面瓦片自带一个永久阻挡的 StaticBody2D (main.gd::_spawn_tile), 两栖船体
## (Amphibious Hull) 靠 add_collision_exception_with() 绕过它。MovingPlatform
## 载客是直接 global_position += move_delta (moving_platform.gd::_physics_process),
## 这个"搬运"本身不会被挡 —— 但乘客自己下一帧的 move_and_slide() 会立刻把它
## 从任何仍在重叠的实体里挤出去, 相当于过河过到一半被弹回岸上, 平台看起来像
## "载不动"。修复是上下船时临时授予/收回同一份水体碰撞例外。
##
## 用 stub 而不是启动 main.tscn: moving_platform.gd 对"战场控制器"是鸭子类型
## 访问 (current_scene 上的 water_bodies), 同 tools/_train_stub.gd 的思路。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_moving_platform_water.gd

var failures: int = 0


class MainStub extends Node2D:
	var water_bodies: Array[StaticBody2D] = []


class TankStub extends CharacterBody2D:
	var is_on_platform: bool = false
	var amphibious_hull_applied: bool = false


func _fail(msg: String) -> void:
	failures += 1
	print("  [FAIL] %s" % msg)


func _ok(msg: String) -> void:
	print("  [ok]   %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> MOVING PLATFORM / WATER CROSSING TEST <<<")
	print("==================================================")

	var main_stub := MainStub.new()
	root.add_child(main_stub)
	current_scene = main_stub

	var water_body := StaticBody2D.new()
	water_body.add_to_group("water")
	main_stub.add_child(water_body)
	main_stub.water_bodies.append(water_body)

	var platform_scene: PackedScene = load("res://scenes/moving_platform.tscn")
	if not platform_scene:
		_fail("moving_platform.tscn 加载失败")
		_finish()
		return
	var platform = platform_scene.instantiate()
	main_stub.add_child(platform)

	# --- 普通坦克: 上船拿到例外, 下船就该还回去 ---
	var tank := TankStub.new()
	tank.add_to_group("player")
	main_stub.add_child(tank)

	platform._on_body_entered(tank)
	if not tank.is_on_platform:
		_fail("上船后 is_on_platform 没置 true")
	elif tank.get_collision_exceptions().has(water_body):
		_ok("上船拿到了水体碰撞例外, is_on_platform 也置了 true")
	else:
		_fail("上船没拿到水体碰撞例外 —— 过河会被水面 StaticBody2D 弹出去")

	platform._on_body_exited(tank)
	if tank.is_on_platform:
		_fail("下船后 is_on_platform 没清 false")
	elif tank.get_collision_exceptions().has(water_body):
		_fail("下船后水体碰撞例外没收回 —— 上岸以后还能穿水面")
	else:
		_ok("下船后例外和 is_on_platform 都正确清掉")

	# --- 两栖船体: 例外是永久的, 下船不该被顺手收走 ---
	var amphibious_tank := TankStub.new()
	amphibious_tank.add_to_group("player")
	amphibious_tank.amphibious_hull_applied = true
	main_stub.add_child(amphibious_tank)
	amphibious_tank.add_collision_exception_with(water_body) # 模拟 _apply_rpg_stats 已经加过的永久例外

	platform._on_body_entered(amphibious_tank)
	platform._on_body_exited(amphibious_tank)
	if amphibious_tank.get_collision_exceptions().has(water_body):
		_ok("两栖船体下船后仍保留水体例外 (它本来就该永久生效)")
	else:
		_fail("两栖船体下船后例外被误收 —— Amphibious Hull 会失效")

	_finish()


func _finish() -> void:
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL MOVING PLATFORM WATER CHECKS PASSED! <<<")
		quit(0)
