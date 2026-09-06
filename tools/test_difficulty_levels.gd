extends SceneTree

## 三档难度 (简单/普通/困难, GameState.difficulty) 的回归测试。
##
## 覆盖两条独立的加压轴, 对应用户要求的"从 AI 智能、敌人数量方面入手":
##   1. 数量轴 -- main.gd::encounter_size()/max_alive_for()/spawn_interval_for()
##      按 DIFFICULTY_* 三张表整数缩放, easy < normal < hard (spawn_interval
##      则反过来, 越难间隔越短)。
##   2. AI 轴 -- 只在 GameState.difficulty == "hard" 时生效: 普通敌人开火前会
##      转向瞄准最近的玩家或基地 (而不是继续朝巡逻方向打空气), 并会横向躲开
##      迎面而来的玩家子弹; 粉碎者/推土机的"正面莽穿"身份不受影响。
##
## 沿用 [[assert-on-random-precondition-hangs]] 里验证过的教训, 而且这次连
## 教训本身都得再往前修一步: 光把 assert() 换成 print("[FAIL]...")+quit(1)
## 还不够。quit() 不会立刻掐断执行, 它只是登记"退出码是这个", 真正的进程终止
## 要等到引擎下一次跑到主循环——如果 quit(1) 之后脚本还在同一帧里继续往下跑
## (这个文件里的 8 个子测试全是同步的, 中间没有一次 await), 跑到最后一行的
## quit(0) 会直接把退出码覆盖回 0, 之前那次 [FAIL] 打印等于白打。
## 实测过: 故意弄坏瞄准逻辑, 这里如果还沿用"每处判定各自 quit(1)"的写法,
## 进程退出码仍然是 0。正确做法是全局记一个失败标志, 只在 _run_tests() 末尾
## 判一次、quit 一次。
var _failed := false

const MainGame = preload("res://scripts/main.gd")
const EnemyScript = preload("res://scripts/enemy.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING DIFFICULTY LEVELS TEST <<<")
	print("==================================================")

	_test_difficulty_field_and_cycling()
	_test_encounter_and_alive_scale_with_difficulty()
	_test_spawn_interval_scales_with_difficulty()
	_test_hard_mode_aims_before_firing()
	_test_normal_mode_does_not_force_aim()
	_test_hard_mode_dodges_incoming_bullet()
	_test_normal_mode_does_not_dodge()
	_test_crusher_is_exempt_from_dodge()

	GameState.difficulty = "normal" # 还原, 虽然每个测试进程都是独立启动的
	if _failed:
		print("\n>>> DIFFICULTY LEVELS CHECKS FAILED <<<")
		quit(1)
	else:
		print("\n>>> ALL DIFFICULTY LEVELS CHECKS PASSED! <<<")
		quit(0)

func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true

func _make_enemy(enemy_type: int, pos: Vector2) -> Node2D:
	var scene = load("res://scenes/enemy.tscn")
	var e = scene.instantiate()
	root.add_child(e)
	e.enemy_type = enemy_type
	e._setup_tank_type()
	e.global_position = pos
	e.change_dir_timer = 999.0 # 冻结随机巡逻换向, 不干扰下面对 facing_direction 的断言
	e.fire_timer = 0.0
	return e

func _make_player(pid: int, pos: Vector2) -> Node2D:
	var scene = load("res://scenes/player.tscn")
	var p = scene.instantiate()
	p.player_id = pid
	root.add_child(p)
	p.global_position = pos
	return p

func _make_player_bullet(pos: Vector2, direction: Vector2) -> Node2D:
	var scene = load("res://scenes/bullet.tscn")
	var b = scene.instantiate()
	root.add_child(b)
	b.global_position = pos
	b.direction = direction
	b.shooter_type = "player"
	return b


func _test_difficulty_field_and_cycling() -> void:
	print("\n[STEP] GameState.difficulty 默认值与循环切换...")
	if GameState.difficulty != "normal":
		_fail("GameState.difficulty 的默认值应为 normal, 实际是 %s" % GameState.difficulty)
		return

	GameState.difficulty = "normal"
	GameState.cycle_difficulty()
	if GameState.difficulty != "hard":
		_fail("从 normal 循环应该到 hard, 实际到了 %s" % GameState.difficulty)
		return
	GameState.cycle_difficulty()
	if GameState.difficulty != "easy":
		_fail("从 hard 循环应该绕回 easy, 实际到了 %s" % GameState.difficulty)
		return
	GameState.cycle_difficulty()
	if GameState.difficulty != "normal":
		_fail("从 easy 循环应该到 normal, 实际到了 %s" % GameState.difficulty)
		return

	print("  [PASS] easy -> normal -> hard -> easy 循环正确, 默认值是 normal。")


func _test_encounter_and_alive_scale_with_difficulty() -> void:
	print("\n[STEP] 遭遇规模与同屏上限随难度递增...")
	var easy_size = MainGame.encounter_size("battle", 0, "easy")
	var normal_size = MainGame.encounter_size("battle", 0, "normal")
	var hard_size = MainGame.encounter_size("battle", 0, "hard")
	if not (easy_size < normal_size and normal_size < hard_size):
		_fail("encounter_size 应满足 easy < normal < hard, 实际 %d / %d / %d" % [easy_size, normal_size, hard_size])
		return

	var easy_alive = MainGame.max_alive_for(0, "easy")
	var normal_alive = MainGame.max_alive_for(0, "normal")
	var hard_alive = MainGame.max_alive_for(0, "hard")
	if not (easy_alive < normal_alive and normal_alive < hard_alive):
		_fail("max_alive_for 应满足 easy < normal < hard, 实际 %d / %d / %d" % [easy_alive, normal_alive, hard_alive])
		return
	if hard_alive > MainGame.MAX_ALIVE_CAP:
		_fail("hard 难度的同屏上限不该突破 MAX_ALIVE_CAP=%d, 实际 %d" % [MainGame.MAX_ALIVE_CAP, hard_alive])
		return

	# 省略 difficulty 参数必须退回 normal 的数值 -- 这是
	# tools/probe_balance_report.gd 和 test_enemy_balance_curve.gd 大量老调用点
	# 继续成立的前提, 不能因为加了这个参数就悄悄改变它们的取值。
	if MainGame.encounter_size("battle", 0) != normal_size:
		_fail("省略 difficulty 参数应该等价于 normal, 但两者不相等")
		return

	print("  [PASS] encounter_size (%d/%d/%d) 与 max_alive_for (%d/%d/%d) 都随难度递增, 省略参数等价 normal。" % [easy_size, normal_size, hard_size, easy_alive, normal_alive, hard_alive])


func _test_spawn_interval_scales_with_difficulty() -> void:
	print("\n[STEP] 出车间隔随难度收紧...")
	var easy_iv = MainGame.spawn_interval_for("battle", 0, "easy")
	var normal_iv = MainGame.spawn_interval_for("battle", 0, "normal")
	var hard_iv = MainGame.spawn_interval_for("battle", 0, "hard")
	if not (easy_iv > normal_iv and normal_iv > hard_iv):
		_fail("spawn_interval_for 应满足 easy > normal > hard (间隔越短越难), 实际 %.3f / %.3f / %.3f" % [easy_iv, normal_iv, hard_iv])
		return
	if hard_iv < MainGame.SPAWN_INTERVAL_FLOOR:
		_fail("hard 难度不该击穿 SPAWN_INTERVAL_FLOOR=%.2f, 实际 %.3f" % [MainGame.SPAWN_INTERVAL_FLOOR, hard_iv])
		return

	print("  [PASS] 出车间隔 (%.3f/%.3f/%.3f) 随难度收紧, 且不击穿地板值。" % [easy_iv, normal_iv, hard_iv])


func _test_hard_mode_aims_before_firing() -> void:
	print("\n[STEP] Hard 难度: 普通敌人开火前会转向瞄准玩家...")
	GameState.difficulty = "hard"

	var enemy = _make_enemy(EnemyScript.EnemyType.BASIC, Vector2(400.0, 400.0))
	enemy.facing_direction = Vector2.DOWN # 巡逻方向跟玩家毫无关系, 用来确认瞄准确实发生了转向
	var player = _make_player(1, Vector2(400.0, 250.0)) # 在敌人正上方

	enemy._physics_process(0.016)

	if enemy.facing_direction != Vector2.UP:
		_fail("hard 难度下, 敌人开火前应转向瞄准正上方的玩家 (facing_direction 应为 UP), 实际是 %s" % enemy.facing_direction)
		enemy.queue_free(); player.queue_free()
		return

	enemy.queue_free()
	player.queue_free()
	print("  [PASS] Hard 难度下敌人开火瞬间转向瞄准了玩家。")


func _test_normal_mode_does_not_force_aim() -> void:
	print("\n[STEP] Normal 难度: 敌人开火不会被强制转向瞄准...")
	GameState.difficulty = "normal"

	var enemy = _make_enemy(EnemyScript.EnemyType.BASIC, Vector2(400.0, 400.0))
	enemy.facing_direction = Vector2.DOWN
	var player = _make_player(1, Vector2(400.0, 250.0)) # 在敌人正上方 (跟上面同一个摆位)

	enemy._physics_process(0.016)

	if enemy.facing_direction == Vector2.UP:
		_fail("normal 难度不该有瞄准转向, 但 facing_direction 变成了朝向玩家的 UP -- 说明瞄准逻辑没有正确被 difficulty 门控")
		enemy.queue_free(); player.queue_free()
		return

	enemy.queue_free()
	player.queue_free()
	print("  [PASS] Normal 难度下没有触发瞄准转向, 门控正确。")


func _test_hard_mode_dodges_incoming_bullet() -> void:
	print("\n[STEP] Hard 难度: 敌人会横向躲开迎面而来的玩家子弹...")
	GameState.difficulty = "hard"

	var enemy = _make_enemy(EnemyScript.EnemyType.BASIC, Vector2(400.0, 400.0))
	enemy.facing_direction = Vector2.RIGHT # 固定一个跟"躲避方向"垂直的初始朝向方便断言
	enemy.fire_timer = 999.0 # 这一步只想单独测躲避, 不想同时触发开火/瞄准分支
	# 子弹在敌人正左方 100px 处向右飞 -- 直冲敌人而来
	var bullet = _make_player_bullet(Vector2(300.0, 400.0), Vector2.RIGHT)

	enemy._physics_process(0.016)

	if enemy.facing_direction == Vector2.LEFT or enemy.facing_direction == Vector2.RIGHT:
		_fail("hard 难度下敌人应该垂直于弹道横向躲避 (UP/DOWN), 但 facing_direction 仍是 %s (跟弹道同轴, 没有躲)" % enemy.facing_direction)
		enemy.queue_free(); bullet.queue_free()
		return
	if enemy.facing_direction != Vector2.UP and enemy.facing_direction != Vector2.DOWN:
		_fail("躲避方向应为 UP 或 DOWN, 实际是 %s" % enemy.facing_direction)
		enemy.queue_free(); bullet.queue_free()
		return

	enemy.queue_free()
	bullet.queue_free()
	print("  [PASS] Hard 难度下敌人正确侧移躲开了迎面子弹 (转向 %s)。" % enemy.facing_direction)


func _test_normal_mode_does_not_dodge() -> void:
	print("\n[STEP] Normal 难度: 面对迎面子弹不会触发躲避...")
	GameState.difficulty = "normal"

	var enemy = _make_enemy(EnemyScript.EnemyType.BASIC, Vector2(400.0, 400.0))
	enemy.facing_direction = Vector2.RIGHT
	enemy.fire_timer = 999.0
	var bullet = _make_player_bullet(Vector2(300.0, 400.0), Vector2.RIGHT)

	enemy._physics_process(0.016)

	if enemy.facing_direction != Vector2.RIGHT:
		_fail("normal 难度不该有躲避反应, facing_direction 应保持 RIGHT 不变, 实际变成了 %s" % enemy.facing_direction)
		enemy.queue_free(); bullet.queue_free()
		return

	enemy.queue_free()
	bullet.queue_free()
	print("  [PASS] Normal 难度下没有触发躲避, 门控正确。")


func _test_crusher_is_exempt_from_dodge() -> void:
	print("\n[STEP] 粉碎者即使在 Hard 难度也不躲子弹 (保留正面莽穿的身份)...")
	GameState.difficulty = "hard"

	var enemy = _make_enemy(EnemyScript.EnemyType.CRUSHER, Vector2(400.0, 400.0))
	enemy.facing_direction = Vector2.RIGHT
	var bullet = _make_player_bullet(Vector2(300.0, 400.0), Vector2.RIGHT)

	enemy._physics_process(0.016)

	if enemy.facing_direction != Vector2.RIGHT:
		_fail("CRUSHER 不该被躲避逻辑改变朝向, facing_direction 应保持 RIGHT, 实际是 %s" % enemy.facing_direction)
		enemy.queue_free(); bullet.queue_free()
		return

	enemy.queue_free()
	bullet.queue_free()
	print("  [PASS] 粉碎者在 hard 难度下依然保持正面冲锋, 没有被躲避逻辑打断。")
