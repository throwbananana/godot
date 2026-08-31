extends SceneTree

## 玩家侧的平衡闸门。
##
## 之前所有的平衡测试量的都是敌人 —— 刷什么、多少血、掉多少金。玩家侧一直
## 没量, 而平衡是两边相除出来的: 敌人曲线再准, 只要玩家的 DPS 或有效血量有
## 一处失衡, 结论就全错。tools/probe_player_power.gd 第一次量了之后当场找出
## 四处, 这个文件把那四处钉住, 后来又补了第五处。
##
##   1. **回复不能压过敌方的全部火力。** 纳米自愈原来无条件每秒结算, 24 级
##      1.5 HP/秒, 一场 45 秒回 67.5 血而最大血才 9 —— 有效血量 76, 敌人要
##      83% 的命中率才压得过。后半幕的常规子弹根本打不死人。
##   2. **train 分支不能被自己的成长曲线稀释掉。** 车厢伤害原来写死 1/2,
##      不吃 atk_bonus, 于是主炮涨到 7 伤时车厢只占总输出的 14%, 整条分支
##      比 heavy/speed 低三分之一。
##   3. **不能卖零。** 射击冷却夹在 0.18/0.32 秒, 到底之后所有射速强化零收益,
##      而商店的 autoloader 照卖、升级面板的 rapid_loader 照发。
##   4. **分支之间不能在 tier 0 (从来不会真的发生的合成态) 就分出胜负。**
##      heavy 在 tier 0 白送 +2 伤 +2 血, 1 级 DPS 是 default 的 2.55 倍
##      (speed 只有 1.70) —— 分支选择发生在第一次升级且不能跳过, 等于直接
##      告诉玩家选哪个。
##   5. **分支在 tier 1 (真实会发生的开局状态) 也不能分出胜负。** 4 号那条
##      测的 tier 0 在游戏里从来到不了 —— set_branch() 选完立刻是 tier 1。
##      星级改成不设阈值、每颗必升一级之后, 捡到第一颗星就同时触发分支选择
##      和这份 tier 1 加成, 常常发生在本局最早几个房间; 实测 tier 1 时 heavy
##      是 default 的 3.40 倍、speed 2.10 倍, 比 4 号量到的 1.70 倍严重得多,
##      而 4 号那条因为压根没覆盖这个状态, 一直是绿的。

const RPGManager = preload("res://scripts/rpg_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const PlayerTank = preload("res://scripts/player.gd")
const ShopDialog = preload("res://scripts/shop_dialog.gd")
const BalanceLog = preload("res://scripts/balance_log.gd")

const TrainStub = preload("res://tools/_train_stub.gd")

const BATTLE_SECONDS := 45.0
## 同屏 4 辆 (main.gd::MAX_ALIVE_BASE), 常规兵平均 2.2 秒一发
const ENEMY_SHOTS_PER_SEC := 4.0 / 2.2

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> PLAYER POWER TEST <<<")
	print("==================================================")
	_check_regen_beatable()
	await _check_regen_lockout_wired()
	_check_train_scales()
	_check_no_selling_zero()
	_check_branch_opening_parity()
	_check_branch_tier1_parity()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL PLAYER POWER CHECKS PASSED! <<<")
		quit(0)


## 按真实升级路径推到 lvl 级 —— 属性点的分配节奏 (_auto_level_bonus 里的
## %2/%3/%4) 本身就是平衡的一部分, 不能直接塞属性点。
func _mgr_at(lvl: int, branch: String, tier: int) -> RPGManager:
	var m := RPGManager.new()
	m.reset()
	for l in range(2, lvl + 1):
		m.level = l
		m._auto_level_bonus()
	m.tank_branch = branch
	m.branch_tier = tier
	return m


func _cd_for(m: RPGManager, branch: String) -> float:
	var floor_v: float = RPGManager.FIRE_CD_FLOOR_SPEED if branch == "speed" \
		else RPGManager.FIRE_CD_FLOOR_OTHER
	return maxf(floor_v, RPGManager.BASE_FIRE_COOLDOWN * m.get_fire_cooldown_mult(1))


# ---------------------------------------------------------------- 1. 回复

## 回复在跑的时间占比。挨打后 REGEN_COMBAT_LOCKOUT 秒内不回血, 把挨打当成
## 速率 λ 的泊松过程, "最近 L 秒没挨过打"的概率 e^(-λL) 就是这个占比。
func _regen_uptime(hit_rate: float) -> float:
	var lam := ENEMY_SHOTS_PER_SEC * hit_rate
	return exp(-lam * PlayerTank.REGEN_COMBAT_LOCKOUT)


## 敌人需要多高的命中率才能压过回复。命中率和回复占比互相依赖 (打得越准 ->
## 锁定越频繁 -> 回复越少), 所以解不动点而不是直接相除。
func _needed_hit_rate(regen: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for _i in range(40):
		var mid := (lo + hi) * 0.5
		if regen * _regen_uptime(mid) > ENEMY_SHOTS_PER_SEC * mid:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## 阈值 45%: 坦克大战里玩家一直在动、地形还挡弹, 实际命中率大致在 15-30%。
## 要求"敌人拿到 45% 命中率就能压过回复"= 回复是个可观的缓冲但不是免死金牌。
## 改之前这个数是 83%, 现在 23%。
const NEEDED_HIT_RATE_CEILING := 0.45

func _check_regen_beatable() -> void:
	print("\n--- 回复必须是可以被打穿的 ---")
	if PlayerTank.REGEN_COMBAT_LOCKOUT <= 0.0:
		fail("REGEN_COMBAT_LOCKOUT 是 %.1f —— 回复又变回无条件每秒结算了"
			% PlayerTank.REGEN_COMBAT_LOCKOUT)
		return
	var worst := 0.0
	var worst_lvl := 0
	var rows: Array = []
	for lvl in [6, 12, 18, 24, 30]:
		var m := _mgr_at(lvl, "default", 0)
		var regen: float = m.get_regen_rate(1)
		var need := _needed_hit_rate(regen)
		rows.append({
			"metric": "regen_gate", "level": lvl,
			"regen": regen, "needed_hit_rate": need,
		})
		if need > worst:
			worst = need
			worst_lvl = lvl
	BalanceLog.emit_batch("player_gate", rows)
	if worst <= NEEDED_HIT_RATE_CEILING:
		ok("最难打穿的一档是 %d 级: 敌人命中率到 %.0f%% 就能压过回复 (上限 %.0f%%)"
			% [worst_lvl, 100.0 * worst, 100.0 * NEEDED_HIT_RATE_CEILING])
	else:
		fail("%d 级时敌人要 %.0f%% 命中率才压得过回复 (上限 %.0f%%) —— "
			% [worst_lvl, 100.0 * worst, 100.0 * NEEDED_HIT_RATE_CEILING]
			+ "坦克大战里玩家一直在动、地形还挡弹, 真实命中率远达不到; "
			+ "等于后半幕常规子弹打不死人, 只有自爆/轰炸那种爆发伤害才致命")


## 上面那条只查了常数, 而常数留着、锁定逻辑被删掉的话它照样过 —— 这种
## "看着有其实没接上"正是这个项目反复踩到的那类问题 (装甲板那边也专门为此
## 加了一条实机检查)。所以这里查行为: 真的挨一发, 看回复的读条有没有被打断。
func _check_regen_lockout_wired() -> void:
	print("\n--- 挨打之后回复真的被打断了 (查行为, 不查常数) ---")
	var host := Node.new()
	host.set_script(load("res://tools/_player_power_host.gd"))
	root.add_child(host)
	var prev_scene = current_scene
	current_scene = host

	var m := _mgr_at(24, "default", 0)
	host.rpg_mgr = m

	var p = load("res://scenes/player.tscn").instantiate()
	root.add_child(p)
	# _ready() 里有 set_invulnerable(3.5) —— 出生保护期内 take_damage() 会在
	# 开头直接 return, 什么都不做。不关掉的话这条测的其实是"无敌时不掉血",
	# 而不是"挨打会打断回复"。
	p.is_invulnerable = false
	p.invulnerable_timer = 0.0
	p.max_health = 9
	p.current_health = 3
	p.regen_lockout = 0.0
	p.regen_accumulator = 0.9 # 已经快攒满一格了
	p.take_damage(1)

	var lockout_set: bool = p.regen_lockout > 0.0
	var acc_left: float = p.regen_accumulator
	var acc_cleared: bool = acc_left <= 0.0001
	var hp_after: int = p.current_health
	# queue_free 而不是 free: 受击动画起了 Tween, 立刻 free 会在退出时报
	# "ObjectDB instances leaked"。
	p.queue_free()
	await process_frame
	current_scene = prev_scene
	host.free()

	if not lockout_set:
		fail("take_damage() 之后 regen_lockout 还是 0 —— 常数留着但没接上, "
			+ "回复实际上仍然是无条件每秒结算")
	elif not acc_cleared:
		fail("take_damage() 没有清空 regen_accumulator (还剩 %.2f) —— "
			% acc_left
			+ "连续挨打会在锁定结束的瞬间'攒'出一格血来")
	else:
		ok("挨一发之后: 锁定 %.1f 秒, 回复进度清零, 血量 3 -> %d"
			% [PlayerTank.REGEN_COMBAT_LOCKOUT, hp_after])


# ---------------------------------------------------------------- 2. train

## 车厢占 train 总输出的比例。低于这个值就说明车厢被主炮的成长稀释掉了,
## 分支特色名存实亡。改之前 24 级时是 14%, 现在 33%。
const CARRIAGE_SHARE_FLOOR := 0.22

func _check_train_scales() -> void:
	print("\n--- train 的车厢必须跟着成长, 不能被主炮稀释 ---")
	# 真的实例化一节车厢去问它的伤害, 不在测试里复刻公式 —— 复刻的必然发散。
	var host := Node.new()
	host.set_script(load("res://tools/_player_power_host.gd"))
	root.add_child(host)
	var prev_scene = current_scene
	current_scene = host

	var head := TrainStub.new()
	head.player_id = 1
	root.add_child(head)

	# 走场景而不是 TrainCarriage.new(): 脚本里的 @onready var sprite = $Sprite2D
	# 只有从 .tscn 实例化才解析得到, 裸 new 会刷一屏 "Node not found"。
	var carriage_scene: PackedScene = load("res://scenes/train_carriage.tscn")

	var bad: Array[String] = []
	var detail := PackedStringArray()
	for lvl in [12, 18, 24]:
		var m := _mgr_at(lvl, "train", 2)
		host.rpg_mgr = m

		var car = carriage_scene.instantiate()
		car.leader_node = head
		root.add_child(car)
		var turret: int = car._carriage_damage(false)
		var rocket: int = car._carriage_damage(true)
		car.free()

		var main_dps := float(m.get_atk_damage(1)) / _cd_for(m, "train")
		# 两节车厢 fire_interval 都是 0.85 (train_carriage.gd::_ready)
		var car_dps := (float(turret) + float(rocket)) / 0.85
		var share := car_dps / (main_dps + car_dps)
		detail.append("%d级 %.0f%%" % [lvl, 100.0 * share])
		if share < CARRIAGE_SHARE_FLOOR:
			bad.append("%d 级只占 %.0f%%" % [lvl, 100.0 * share])

	head.free()
	current_scene = prev_scene
	host.free()

	if bad.is_empty():
		ok("车厢占 train 总输出 %s (下限 %.0f%%)"
			% [" / ".join(detail), 100.0 * CARRIAGE_SHARE_FLOOR])
	else:
		fail("车厢占比过低: %s —— 车厢伤害是不是又写死了不吃 atk_bonus? "
			% ", ".join(bad)
			+ "主炮一路涨到 7-13 伤的时候, 写死 1/2 的车厢会被稀释成个位数占比, "
			+ "train 的分支特色就名存实亡了")


# ---------------------------------------------------------------- 3. 不卖零

func _check_no_selling_zero() -> void:
	print("\n--- 射速强化在没有效果的时候不能卖 / 不能发 ---")

	# can_buy_item 是 ShopDialog 上的 static 方法 (纯读 GameState, 不需要实例),
	# 走真实的对话框逻辑, 不复刻判断。

	# (a) 没到底的时候必须照常可买 —— 别把闸门写成"永远不卖"
	GameState.reset_campaign(1)
	GameState.tank_branch = "default"
	GameState.fire_rate_lvl = 0
	if ShopDialog.can_buy_item("autoloader"):
		ok("新档 (射速 0 级) 时 autoloader 正常可买")
	else:
		fail("新档时 autoloader 就买不了了 —— 闸门写反了, 这是把有效的强化也挡掉")

	# (b) 撞到地板之后必须挡掉。用 rapid_loader x3 制造这个状态:
	#     实测叠满之后 10 级就到底, 而一幕会涨到 24 级左右。
	GameState.reset_campaign(1)
	GameState.tank_branch = "default"
	GameState.fire_rate_lvl = 14
	GameState.unlocked_perks = {"rapid_loader": 3}
	var m := RPGManager.new()
	m.sync_from_game_state()
	var capped: bool = m.is_fire_rate_capped(1, 0.10)
	if not capped:
		fail("射速 14 级 + rapid_loader x3 居然没撞到冷却地板 —— "
			+ "is_fire_rate_capped() 的算法和 player.gd::_fire() 的 clamp 对不上了")
	elif ShopDialog.can_buy_item("autoloader"):
		fail("冷却已经贴在地板上, autoloader 却还能买 —— 玩家花 90G 买到的是零, "
			+ "而卡片上写着 '+10% 装填速度'")
	else:
		ok("冷却贴地板时 autoloader 不可购买 (和上限检查同一条原则: 不卖零)")

	GameState.reset_campaign(1)


# ---------------------------------------------------------------- 4. 开局

## 1 级时各分支 DPS 的最大倍差。分支选择发生在第一次升级而且没有跳过选项,
## 所以开局的倍差就是"最优解"的强度。改之前 heavy 是 2.55 倍 (speed 1.70)。
const OPENING_DPS_SPREAD_CEILING := 2.0

func _check_branch_opening_parity() -> void:
	print("\n--- 分支不能在 tier 0 就分出胜负 ---")
	var best := 0.0
	var worst := 1e9
	var detail := PackedStringArray()
	for branch in ["default", "speed", "heavy", "train"]:
		var m := _mgr_at(1, branch, 0)
		var dps := float(m.get_atk_damage(1)) / _cd_for(m, branch)
		detail.append("%s %.2f" % [branch, dps])
		best = maxf(best, dps)
		worst = minf(worst, dps)
	var spread := best / maxf(0.001, worst)
	if spread <= OPENING_DPS_SPREAD_CEILING:
		ok("1 级 DPS: %s (最大倍差 x%.2f, 上限 x%.2f)"
			% [" / ".join(detail), spread, OPENING_DPS_SPREAD_CEILING])
	else:
		fail("1 级 DPS 倍差 x%.2f 超过上限 x%.2f (%s) —— "
			% [spread, OPENING_DPS_SPREAD_CEILING, " / ".join(detail)]
			+ "分支在第一次升级时选, 而且没有跳过选项, 开局就白送这么多等于"
			+ "直接告诉玩家选哪个; 差距应该长在 tier 上, 不是送在 tier 0")


# ---------------------------------------------------------------- 5. tier1 开局

## 上面那条测的是 tier=0 —— 一个游戏里从来不会真的发生的状态 (set_branch()
## 选完分支 tier 立刻变成 1)。真正决定"开局强度"的是 tier=1, 而且星级不设
## 阈值以后, 捡到第一颗星就同时触发分支选择 (第一次升级、不能跳过) 和这份
## tier=1 加成, 常常发生在本局最早的几个房间。改之前在这里测: heavy 3.40x
## default, speed 2.10x default —— 比 tier0 那条测到的 1.70x 严重得多, 而
## tier0 那条一直是绿的, 因为它压根没覆盖这个真实会发生的状态。
const OPENING_TIER1_DPS_SPREAD_CEILING := 2.0

func _check_branch_tier1_parity() -> void:
	print("\n--- 分支一旦选定 (tier 1, 真实会发生的状态) 也不能立刻分出胜负 ---")
	var best := 0.0
	var worst := 1e9
	var detail := PackedStringArray()
	for branch in ["default", "speed", "heavy", "train"]:
		var m := _mgr_at(1, branch, 1)
		var dps := float(m.get_atk_damage(1)) / _cd_for(m, branch)
		detail.append("%s %.2f" % [branch, dps])
		best = maxf(best, dps)
		worst = minf(worst, dps)
	var spread := best / maxf(0.001, worst)
	if spread <= OPENING_TIER1_DPS_SPREAD_CEILING:
		ok("tier1 DPS: %s (最大倍差 x%.2f, 上限 x%.2f)"
			% [" / ".join(detail), spread, OPENING_TIER1_DPS_SPREAD_CEILING])
	else:
		fail("tier1 DPS 倍差 x%.2f 超过上限 x%.2f (%s) —— "
			% [spread, OPENING_TIER1_DPS_SPREAD_CEILING, " / ".join(detail)]
			+ "分支一选定 tier 就立刻是 1, 这才是真实会发生的开局强度")
