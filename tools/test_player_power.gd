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
	_check_six_branch_hp_speed_parity()
	_check_counter_baseline_and_payoff()
	_check_trench_aoe_output()
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
	var floor_v: float = RPGManager.FIRE_CD_FLOOR_SPEED
	if branch == "trench":
		floor_v = RPGManager.FIRE_CD_FLOOR_TRENCH
	elif branch == "counter":
		floor_v = RPGManager.FIRE_CD_FLOOR_COUNTER
	elif branch != "speed":
		floor_v = RPGManager.FIRE_CD_FLOOR_OTHER
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

## RPGManager 后来又加了两个分支 ("counter"/"trench"), 但上面两条 tier0/tier1
## 平价检查从来没把它们收进循环 —— 这正是本文件开头列的那类问题会复发的
## 地方: 新内容上线了, 量它的闸门却还是照着旧名单跑, 于是新分支实际有没有
## "在第一次升级就分出胜负"这件事从来没人测过。
##
## 没有直接把它们塞进上面两条循环, 是因为它们的武器根本不是"伤害/冷却"这种
## 单目标 DPS 能公平比较的形状:
##   - counter 每次开火都会打开一段 0.34 秒的弹反判定窗口, 命中"完美窗口"
##     (窗口内最后 0.14~0.18 秒) 会把弹反的敌弹和玩家下一发都强化数倍, 并把
##     冷却立即清零 —— 真实输出高度依赖弹反时机, 不是一个确定的数。
##   - trench 每次开火是一个小半径 (42-54px) 的范围切割, 命中范围内*所有*
##     敌人, 而不是一发子弹打一个目标, 并且自动切碎飞入判定圈的敌弹 —— 目标
##     数量直接改变它相对单体武器的产出。
## 硬套上面那条"最大倍差 x2.0"的单目标 DPS 断言, 对这两个分支要么量错东西
## (counter 不摸最佳路径的话看着像残废), 要么根本没在测它们真正的强度轴
## (trench 打不打得到多个目标)。所以下面两条改成算清楚的量, 不是硬掰成同一
## 把尺子。

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


# ---------------------------------------------------------------- 6. 六分支 HP/机动 (含 counter/trench)

## HP 和移速不像伤害那样有"必须追上敌人血量"的硬约束, 但沿用同一条 x2.0 的
## 分寸线是有依据的: 当初 heavy 在 tier1 就把 DPS 拉到 default 的 3.40 倍
## 正是靠"这个数字看起来没有伤害那么显眼, 所以没人管"才滑过去的。这里同一把
## 尺子量 HP 和移速, 不是说 2.0 就是唯一正确阈值, 是不想让"不是伤害所以没
## 关系"成为下一次滑过去的理由。
const HP_SPREAD_CEILING := 2.0
const SPEED_SPREAD_CEILING := 2.0
const ALL_BRANCHES := ["default", "speed", "heavy", "train", "counter", "trench"]

func _check_six_branch_hp_speed_parity() -> void:
	print("\n--- 六分支 (含 counter/trench) 的血量与机动倍差 ---")
	for tier in [1, 2]:
		var hp_best := 0.0
		var hp_worst := 1e9
		var spd_best := 0.0
		var spd_worst := 1e9
		var hp_detail := PackedStringArray()
		var spd_detail := PackedStringArray()
		for branch in ALL_BRANCHES:
			var m := _mgr_at(12, branch, tier) # 12 级: 一幕中段, HP 相关加成已经过半解锁
			var hp := float(m.get_player_max_hp(1))
			var spd := m.get_speed_multiplier(1)
			hp_detail.append("%s %.0f" % [branch, hp])
			spd_detail.append("%s %.2f" % [branch, spd])
			hp_best = maxf(hp_best, hp)
			hp_worst = minf(hp_worst, hp)
			spd_best = maxf(spd_best, spd)
			spd_worst = minf(spd_worst, spd)
		var hp_spread := hp_best / maxf(0.001, hp_worst)
		var spd_spread := spd_best / maxf(0.001, spd_worst)
		if hp_spread <= HP_SPREAD_CEILING:
			ok("tier%d 12级 HP: %s (最大倍差 x%.2f)" % [tier, " / ".join(hp_detail), hp_spread])
		else:
			fail("tier%d 12级 HP 倍差 x%.2f 超过 x%.2f (%s)"
				% [tier, hp_spread, HP_SPREAD_CEILING, " / ".join(hp_detail)])
		if spd_spread <= SPEED_SPREAD_CEILING:
			ok("tier%d 12级 移速: %s (最大倍差 x%.2f)" % [tier, " / ".join(spd_detail), spd_spread])
		else:
			fail("tier%d 12级 移速倍差 x%.2f 超过 x%.2f (%s)"
				% [tier, spd_spread, SPEED_SPREAD_CEILING, " / ".join(spd_detail)])


# ---------------------------------------------------------------- 7. counter: 基线 + 弹反收益

## counter 的真实产出不是一个确定的数, 取决于弹反时机——这条不装作能裁决
## "平衡不平衡", 只把两个能算清楚的量摆出来:
##   (a) 基线 DPS: 完全不弹反、纯按 1.10 秒地板打空炮的下限。
##   (b) 收支平衡点: 要打平 default 的 DPS, 每次开火需要多大概率命中"完美
##       窗口"。用和回复检查同一种不动点技巧 (窗口开着的时候更可能命中,
##       但命中之后冷却清零又立刻打开新窗口, 两者互相耦合)。
## 这两个数不能证明分支平衡与否——那是设计判断, 需要真人试玩数据 (main.gd
## 的 battle_result 日志) 而不是这条测试来回答。这里只保证"基线不是荒谬地
## 弱到聊胜于无"这一条能被工具钉住, 顺带把经济学摆出来供人工判断。
const COUNTER_BASELINE_DPS_FLOOR_RATIO := 0.30 # 基线不该低于 default 的 3 成

func _check_counter_baseline_and_payoff() -> void:
	print("\n--- counter: 零弹反基线 + 弹反收支平衡点 ---")
	for tier in [1, 2]:
		var mc := _mgr_at(12, "counter", tier)
		var md := _mgr_at(12, "default", 0)
		var counter_dps := float(mc.get_atk_damage(1)) / _cd_for(mc, "counter")
		var default_dps := float(md.get_atk_damage(1)) / _cd_for(md, "default")
		var ratio := counter_dps / maxf(0.001, default_dps)

		# 弹反窗口每次开火占用 0.34 秒 (PlayerTank.parry_total_duration), 冷却
		# 周期是当前 _cd_for() 算出来的实际冷却。命中完美窗口那一刻会把冷却
		# 立即清零并重开一轮窗口, 所以"命中率越高, 窗口开启的时间占比也越高"——
		# 和回复检查里"打得越准, 锁定越频繁"是同一种正反馈结构, 用同一种
		# 不动点去解。
		var cd := _cd_for(mc, "counter")
		var window: float = 0.34 # PlayerTank.parry_total_duration
		var reflect_dmg := maxf(4.0, 2.0 + float(tier)) # 反弹的通常是敌方 1 点弹, 2.2x+2+tier
		var charged_dmg := maxf(4.0, float(mc.get_atk_damage(1)) * 2.0 + 2.0 + float(tier))

		var lo := 0.0
		var hi := 1.0
		for _i in range(40):
			var mid := (lo + hi) * 0.5
			# 命中完美窗口的这一刻: 拿到 reflect_dmg + charged_dmg, 冷却清零。
			# 没命中的周期: 只拿基础一发 counter_dps*cd 的伤害。
			# 每个"周期"长度按 (命中率*窗口 + (1-命中率)*cd) 近似 —— 命中会
			# 立刻重开窗口, 相当于把周期压缩到窗口本身。
			var cycle_len := mid * window + (1.0 - mid) * cd
			var cycle_dmg := mid * (reflect_dmg + charged_dmg) + (1.0 - mid) * (counter_dps * cd)
			var achieved_dps := cycle_dmg / maxf(0.001, cycle_len)
			if achieved_dps < default_dps:
				lo = mid
			else:
				hi = mid
		var breakeven := (lo + hi) * 0.5

		if ratio >= COUNTER_BASELINE_DPS_FLOOR_RATIO:
			ok("tier%d 基线 DPS %.2f (default %.2f 的 %.0f%%) —— 打平 default 需要约 %.0f%% 的完美弹反命中率"
				% [tier, counter_dps, default_dps, ratio * 100.0, breakeven * 100.0])
		else:
			fail("tier%d counter 基线 DPS %.2f 只有 default %.2f 的 %.0f%% (下限 %.0f%%) —— "
				% [tier, counter_dps, default_dps, ratio * 100.0, COUNTER_BASELINE_DPS_FLOOR_RATIO * 100.0]
				+ "完全不弹反的话这个分支形同虚设")


# ---------------------------------------------------------------- 8. trench: 范围产出

## trench 每次开火是命中半径内*所有*敌人的范围切割, 不是单发子弹。这里算的是
## "打平 default 单体 DPS 需要命中几个目标", 以及自动切弹的正常运行时间占比
## (这个是确定的, 不吃时机技巧, 因为切割拦截判定每帧都在跑, 不需要玩家
## 主动瞄准)。
## 单体 DPS 相对 default 的上限。trench 的范围伤害 + 自动切弹本来就该比单体
## 武器"值钱"一些, 但不该连*单体*都比专精单体输出的分支更能打——那样范围/
## 切弹就成了纯赠品, 不是拿什么去换的。x1.5 留了实打实的余量 (default 自己
## 在 tier1 时 speed/heavy 就已经站到 x1.70), 只用来卡住这次实测到的
## x1.52~x2.29 这种量级, 不是想把 trench 削成和 default 完全打平。
const TRENCH_SINGLE_TARGET_RATIO_CEILING := 1.5

## 真开一炮去问 LaserRingCutter 拿到的伤害/半径, 不在测试里复刻
## maxi(dmg+N, M) 那条公式——复刻的必然发散, 这个文件开头train那条检查
## 已经因为同样的理由改成"真实例化一节车厢"了, 这里踩过一次坑才补上同一
## 处理: 第一版试图手抄公式, 后来 player.gd 把 +1/+2 去掉之后这条测试却还在
## 用旧公式算基线, 数字没跟着代码变, 看着像"没测出改动"。
func _check_trench_aoe_output() -> void:
	print("\n--- trench: 范围切割产出 + 切弹正常运行时间 ---")
	var host := Node.new()
	host.set_script(load("res://tools/_player_power_host.gd"))
	root.add_child(host)
	var prev_scene = current_scene
	current_scene = host

	for tier in [1, 2]:
		var mt := _mgr_at(12, "trench", tier)
		var md := _mgr_at(12, "default", 0)
		host.rpg_mgr = mt

		var p = load("res://scenes/player.tscn").instantiate()
		root.add_child(p)
		p.facing_direction = Vector2.UP
		p.global_position = Vector2(200, 200)
		p._shoot()

		var cutter: Node2D = null
		for c in root.get_children():
			if c.is_in_group("laser_ring_cutter"):
				cutter = c
		var found := cutter != null
		var cut_dmg: int = cutter.damage if found else 0
		p.queue_free()
		if found:
			# 立即 free 而不是 queue_free: 下一轮 tier 循环马上又要按
			# "laser_ring_cutter" 组搜一遍 root 的子节点, deferred 释放会让
			# 上一轮那个还没真正消失的节点被当成这一轮的结果。
			#
			# 注意 free() 之后不能再用 `cutter == null` 判断"找没找到"——
			# Godot 对已 free 的 Object 引用做了特殊处理, 让它在这类比较里
			# 表现得和 null 一样, 所以 found 必须在 free() *之前*就存好。
			cutter.free()

		if not found:
			fail("tier%d trench 开火之后场上找不到 LaserRingCutter —— 武器分支没有真的触发" % tier)
			continue

		var cd := _cd_for(mt, "trench")
		var single_target_dps := float(cut_dmg) / cd
		var default_dps := float(md.get_atk_damage(1)) / _cd_for(md, "default")
		var ratio := single_target_dps / maxf(0.001, default_dps)
		var targets_to_match := default_dps / maxf(0.001, single_target_dps)

		# LaserRingCutter.duration=0.26s, 每次开火的冷却是 cd —— 切弹判定只在
		# 这 0.26 秒的窗口内跑, 且不需要玩家做任何操作 (自动生效), 所以是
		# 确定的正常运行时间占比, 不是像 counter 那样要解不动点。
		var cutter_duration := 0.26
		var uptime := minf(1.0, cutter_duration / cd)

		if ratio <= TRENCH_SINGLE_TARGET_RATIO_CEILING:
			ok("tier%d 单体 DPS %.2f (default %.2f 的 %.0f%%, 上限 %.0f%%), 命中 %.1f 个目标即可打平; 自动切弹运行时间占比 %.0f%%"
				% [tier, single_target_dps, default_dps, ratio * 100.0, TRENCH_SINGLE_TARGET_RATIO_CEILING * 100.0,
				   targets_to_match, uptime * 100.0])
		else:
			fail("tier%d trench 单体 DPS %.2f 是 default %.2f 的 %.0f%% (上限 %.0f%%) —— "
				% [tier, single_target_dps, default_dps, ratio * 100.0, TRENCH_SINGLE_TARGET_RATIO_CEILING * 100.0]
				+ "范围伤害和自动切弹在这个比例下成了纯赠品, 不是拿单体输出去换的")

	current_scene = prev_scene
	host.free()
