extends SceneTree

## 防御炮塔"无目标时的待机扫描"的回归测试。
##
##     & $godot --headless --path . --script tools/test_turret_idle_scan.gd
##
## === 这个测试要钉住的两件事 ===
##
## 1. **没有敌人时炮管会动。** 改之前 _physics_process 的 else 分支只递减
##    fire_timer, 一行都不碰 gun_sprite.rotation, 于是炮管永远定格在最后一次
##    交战的朝向。炮塔是玩家最常放下的建筑 (商店 80G, 热键第一位), 一排朝向
##    各异、纹丝不动的炮管读起来像是坏了。
##
## 2. **扫描只停在四个基本方向。** 这条比第 1 条更容易被悄悄改坏: 让炮管连续
##    自由旋转看起来"更顺滑", 但这个游戏里所有坦克和子弹都只上下左右
##    (defense_turret.gd 瞄准分支的注释专门写了这件事), 一座会停在斜角的自动
##    炮塔是全场唯一的例外。转场过程路过斜角是允许的 —— 检查的是**停下来的
##    时候**在不在基本方向上。
##
## 按 CLAUDE.md 的约定: _failed 标志 + 末尾唯一一次 quit(), 不用 assert
## (headless 下 assert 是挂起而不是失败, 而且挂起不带任何诊断), 也不在中途
## quit(1) —— quit() 只登记退出码并请求主循环停下, 不打断当前调用栈, 中途那次
## 会被文件末尾的 quit(0) 覆盖掉。

const TURRET_SCENE := "res://scenes/buildings/defense_turret.tscn"

## 允许的停留朝向: 上/右/下/左, 各自 +PI/2 (精灵朝上建模)。
const CARDINAL_EPSILON := 0.12

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true


func _init() -> void:
	call_deferred("_run_tests")


## 转成 [0, TAU) 再看离最近的基本方向有多远。
func _cardinal_error(rot: float) -> float:
	var a := fposmod(rot, TAU)
	var best := TAU
	for k in range(4):
		var want := fposmod(float(k) * PI * 0.5, TAU)
		var d: float = absf(a - want)
		d = minf(d, TAU - d)
		best = minf(best, d)
	return best


func _run_tests() -> void:
	print("=== 防御炮塔待机扫描 ===")

	var scene: PackedScene = load(TURRET_SCENE)
	if scene == null:
		_fail("加载不了 " + TURRET_SCENE)
		_finish()
		return

	# 场景实例化需要一个真实的树; 用一个裸 Node2D 当宿主, 不启动 main.tscn ——
	# 炮塔只在 rpg_mgr 存在时读它, 不存在时走 null 保护, 所以这个测试不需要
	# 整场战斗 (同 test_train_teleport.gd 用 stub 而不是 boot main.tscn)。
	var host := Node2D.new()
	root.add_child(host)
	var turret = scene.instantiate()
	host.add_child(turret)
	await process_frame
	await physics_frame

	var gun: Sprite2D = turret.get_node_or_null("GunSprite")
	if gun == null:
		_fail("炮塔场景里找不到 GunSprite —— 待机扫描是直接写它的 rotation 的")
		host.queue_free()
		_finish()
		return

	# ── 1. 无目标时炮管确实在动 ──
	var start_rot := gun.rotation
	var moved := 0.0
	var frames := 0
	# IDLE_SCAN_INTERVAL 是 1.5s, 物理步 1/60 —— 跑 150 步 (2.5s) 足够跨过
	# 至少一次换向并完成转场。
	while frames < 150:
		await physics_frame
		moved = maxf(moved, absf(angle_difference(gun.rotation, start_rot)))
		frames += 1

	if moved < 0.05:
		_fail("无目标时炮管一直定格在 %.3f rad —— 待机扫描没生效。这正是改动之前的行为: _physics_process 的 else 分支只递减 fire_timer, 不碰 gun_sprite.rotation。"
			% start_rot)
	else:
		print("  无目标时最大转过 %.2f rad (%.0f°) ✓" % [moved, rad_to_deg(moved)])

	# ── 2. 停下来的时候落在基本方向上 ──
	# 再跑满一个完整的停留期, 然后在"刚换向之后的间隔末尾"取样 —— 那时转场
	# 早已完成 (IDLE_TURN_SPEED 2.2 rad/s 转 90° 只要 0.71s, 而间隔是 1.5s)。
	var worst := 0.0
	var samples := 0
	for _cycle in range(3):
		for _f in range(88):        # ~1.47s, 落在换向前夕
			await physics_frame
		var err := _cardinal_error(gun.rotation)
		worst = maxf(worst, err)
		samples += 1

	if worst > CARDINAL_EPSILON:
		_fail("待机扫描停在了非基本方向上: %d 次取样里最差偏离 %.3f rad (%.1f°), 上限 %.3f —— 这个游戏里所有坦克和子弹都只上下左右, 自动炮塔不能是唯一一个停在斜角的东西 (见 defense_turret.gd 瞄准分支的注释)。转场过程路过斜角是允许的, 这里查的是停留朝向。"
			% [samples, worst, rad_to_deg(worst), CARDINAL_EPSILON])
	else:
		print("  %d 次停留取样, 最差偏离基本方向 %.3f rad (%.1f°) ✓"
			% [samples, worst, rad_to_deg(worst)])

	host.queue_free()
	_finish()


func _finish() -> void:
	print("")
	if _failed:
		print("[FAIL] 炮塔待机扫描检查未通过")
		quit(1)
	else:
		print("[OK] 炮塔待机扫描检查通过")
		quit(0)
