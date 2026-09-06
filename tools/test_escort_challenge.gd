extends SceneTree

## "escort" (护送友军) 挑战房的回归测试。
##
## 覆盖: 进房正确生成友军且友军加入 player 组(这样敌人才会把它当合法目标)、
## 友军阵亡触发战败、房间清空时友军正常撤离而不误判战败、非 escort 的挑战房
## 不会误生成友军。
##
## 用失败计数器 + 单次 quit() 收尾, 不用裸 assert() —— 见
## [[assert-on-random-precondition-hangs]]: 裸 assert 在被 _run_tests()
## 顺序调用的子函数里失败只会打一行 SCRIPT ERROR 然后照常跑完 quit(0),
## run_tests.ps1 只看退出码, 会把真失败读成绿色 "ok"。

const GameState = preload("res://scripts/game_state.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const Bullet = preload("res://scripts/bullet.gd")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func ok(msg: String) -> void:
	print("  [ok] %s" % msg)

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> ESCORT CHALLENGE TEST <<<")
	print("==================================================")

	await _test_ally_spawns_in_escort_room()
	await _test_ally_moves_around()
	await _test_ally_fires_at_nearby_enemy()
	_test_ally_does_not_fire_without_target()
	await _test_ally_death_triggers_defeat()
	await _test_room_clear_despawns_ally_without_defeat()
	await _test_non_escort_challenge_does_not_spawn_ally()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL ESCORT CHALLENGE CHECKS PASSED! <<<")
		quit(0)

func _boot_main() -> Node:
	GameState.reset_campaign(1)
	var main_scene = load("res://scenes/main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	current_scene = main_node
	return main_node

## 复刻 tools/test_enemy_balance_curve.gd::_force_room_battle_type() 的手法:
## 直接改当前房间的 type/challenge_mode 再重新走一遍真实的 enter_room(),
## 而不是自己手搭一份房间状态——手搭必然会和真实字段发散。
func _force_challenge_room(main_node: Node, mode: String) -> void:
	var rk: String = GameState.current_room
	GameState.floor_rooms[rk]["type"] = "challenge"
	GameState.floor_rooms[rk]["cleared"] = false
	GameState.floor_rooms[rk]["challenge_mode"] = mode
	main_node.enter_room(rk, -1)

func _test_ally_spawns_in_escort_room() -> void:
	print("\n[STEP 1] 护送挑战房正确生成友军, 且友军加入 player 组...")
	var main_node = _boot_main()
	await process_frame
	_force_challenge_room(main_node, "escort")
	await process_frame

	var ally = main_node.escort_ally_instances[0] if main_node.escort_ally_instances.size() > 0 else null
	if not (ally and is_instance_valid(ally)):
		fail("escort 挑战房应该生成 escort_ally_instances, 但没有")
	else:
		ok("escort_ally_instances 已生成")
		if not ally.is_in_group("player"):
			fail("友军应该加入 player 组, 这样 enemy.gd::_find_target() 才会把它当合法目标, 敌方子弹才打得中它")
		else:
			ok("友军正确加入 player 组")

	main_node.queue_free()
	await process_frame

func _test_ally_moves_around() -> void:
	print("\n[STEP 1b] 友军会自己四处游荡, 不是钉在原地不动...")
	var ally_scene = load("res://scenes/ally_tank.tscn")
	var ally = ally_scene.instantiate()
	root.add_child(ally)
	ally.global_position = Vector2(400.0, 400.0)
	var start_pos: Vector2 = ally.global_position

	# 冻结换向计时器强制它立刻朝一个已知方向走, 不用等随机的 1~2 秒预热窗口。
	ally.change_dir_timer = 0.0
	ally.facing_direction = Vector2.RIGHT

	for i in range(30):
		await physics_frame

	var moved: float = ally.global_position.distance_to(start_pos)
	if moved < 5.0:
		fail("友军 30 个物理帧之后几乎没动 (位移 %.1fpx) —— 应该会自己游荡" % moved)
	else:
		ok("友军确实在移动 (30 帧内位移 %.1fpx)" % moved)

	ally.queue_free()
	await process_frame

func _test_ally_fires_at_nearby_enemy() -> void:
	print("\n[STEP 1c] 射程内有敌人时友军会转向瞄准并开火...")
	var actors = Node2D.new() # Node2D 父容器, 不是裸 root(Window) -- 子弹/VFX 都要挂在 Node2D 下
	root.add_child(actors)

	var ally = load("res://scenes/ally_tank.tscn").instantiate()
	actors.add_child(ally)
	ally.global_position = Vector2(300.0, 300.0)
	ally.facing_direction = Vector2.DOWN # 跟目标方向 (右方) 不同, 用来确认瞄准确实发生了转向

	var enemy = load("res://scenes/enemy.tscn").instantiate()
	actors.add_child(enemy)
	enemy.enemy_type = EnemyScript.EnemyType.BASIC
	enemy._setup_tank_type()
	enemy.global_position = Vector2(300.0 + ally.FIRE_RANGE * 0.5, 300.0) # 射程内, 正右方

	ally.fire_timer = 0.0
	ally._physics_process(0.016)

	if ally.facing_direction != Vector2.RIGHT:
		fail("友军应该转向瞄准正右方的敌人, 实际朝向 %s" % ally.facing_direction)
	else:
		ok("友军正确转向瞄准了射程内的敌人")

	var bullet: Node = null
	for c in actors.get_children():
		if c is Bullet:
			bullet = c
			break
	if bullet == null:
		fail("友军射程内有敌人时应该开火生成子弹, 但没有生成")
	else:
		ok("友军正确开火生成了子弹")
		if bullet.direction != Vector2.RIGHT:
			fail("子弹方向应该朝向敌人 (RIGHT), 实际是 %s" % bullet.direction)
		else:
			ok("子弹方向正确朝向敌人")
		if bullet.shooter_type != "player":
			fail("友军子弹的 shooter_type 应该是 'player' (这样才会伤到敌人、不会伤到真玩家), 实际是 '%s'" % bullet.shooter_type)
		else:
			ok("友军子弹 shooter_type 正确标记为 'player'")

	actors.queue_free()
	# queue_free() 只是登记删除, 不会立刻生效——下一个测试 (STEP 1d) 会在同一棵
	# 场景树里用 get_tree().get_nodes_in_group() 找敌人, 不等一帧的话它会看到
	# 这里刚"删除"但其实还活着的 enemy, 把它当成"射程内有敌人"而误开火。
	# 同一个坑这次会话里已经在 test_kinetic_push_and_squeeze.gd 撞过一次。
	await process_frame

func _test_ally_does_not_fire_without_target() -> void:
	print("\n[STEP 1d] 射程内没有敌人时友军不会瞎打...")
	var actors = Node2D.new()
	root.add_child(actors)

	var ally = load("res://scenes/ally_tank.tscn").instantiate()
	actors.add_child(ally)
	ally.global_position = Vector2(300.0, 300.0)

	ally.fire_timer = 0.0
	ally._physics_process(0.016)

	var bullet_count := 0
	for c in actors.get_children():
		if c is Bullet:
			bullet_count += 1
	if bullet_count > 0:
		fail("射程内没有敌人时友军不该开火, 但生成了 %d 发子弹" % bullet_count)
	else:
		ok("射程内没有敌人时友军正确保持不开火")

	actors.queue_free()

func _test_ally_death_triggers_defeat() -> void:
	print("\n[STEP 2] 友军阵亡触发战败...")
	var main_node = _boot_main()
	await process_frame
	_force_challenge_room(main_node, "escort")
	await process_frame

	var ally = main_node.escort_ally_instances[0] if main_node.escort_ally_instances.size() > 0 else null
	if not (ally and is_instance_valid(ally)):
		fail("友军没有正确生成, 无法继续测试阵亡逻辑")
		main_node.queue_free()
		await process_frame
		return

	ally.take_damage(999)
	await process_frame

	if not main_node.is_game_over:
		fail("友军阵亡后应该触发战败 (is_game_over), 但没有")
	else:
		ok("友军阵亡正确触发战败")

	main_node.queue_free()
	await process_frame

func _test_room_clear_despawns_ally_without_defeat() -> void:
	print("\n[STEP 3] 房间清空(护送成功)时友军正常撤离, 不误判战败...")
	var main_node = _boot_main()
	await process_frame
	_force_challenge_room(main_node, "escort")
	await process_frame

	if main_node.escort_ally_instances.is_empty() or not is_instance_valid(main_node.escort_ally_instances[0]):
		fail("友军没有正确生成, 无法继续测试撤离逻辑")
		main_node.queue_free()
		await process_frame
		return

	main_node._on_room_cleared()
	await process_frame

	if main_node.is_game_over:
		fail("房间清空(护送成功)不该触发战败, 但 is_game_over 变成了 true")
	else:
		ok("房间清空没有误触发战败")
	if not main_node.escort_ally_instances.is_empty():
		fail("房间清空后 escort_ally_instances 应该被清空")
	else:
		ok("escort_ally_instances 正确清空")

	main_node.queue_free()
	await process_frame

func _test_non_escort_challenge_does_not_spawn_ally() -> void:
	print("\n[STEP 4] 非 escort 的挑战房不会误生成友军 (回归门控)...")
	var main_node = _boot_main()
	await process_frame
	_force_challenge_room(main_node, "vault")
	await process_frame

	if not main_node.escort_ally_instances.is_empty():
		fail("vault 挑战房不该生成友军, 但 escort_ally_instances 不是空的")
	else:
		ok("非 escort 挑战房正确没有生成友军")

	main_node.queue_free()
	await process_frame
