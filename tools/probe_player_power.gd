extends SceneTree

## 玩家侧的采样探针 —— 和 probe_balance_report.gd 互补。
##
## 那一支量的全是敌人: 刷什么、多少血、掉多少金。整个玩家侧从来没量过, 而
## 平衡是两边相除出来的 —— 敌人血量的曲线再准, 只要玩家的 DPS 或者有效血量
## 有一处失衡, 结论就全错。
##
## 量四件事:
##
##   1. **各分支的 DPS**。伤害和射速分别由 rpg_manager 的两个 getter 决定,
##      而分支加成是加在不同项上的 (heavy 加伤害, speed 加射速), 光看常数
##      比不出来 —— 必须乘出来。
##   2. **射击冷却的地板什么时候咬住**。player.gd 里 cd 被
##      maxf(0.18/0.32, cd) 夹着, 一旦到底, 之后每一点射速强化 (升级自动给的、
##      商店的 autoloader、perk 的 rapid_loader) 全部白给, 而 UI 上照样显示
##      "射速 +10%"。这类"买了没效果"是最难被发现的一种失衡。
##   3. **有效血量** = 最大血 + 回复 x 一场的时长。回复是每秒结算的
##      (player.gd::_physics_process), 一场几十秒的战斗里它可能远超最大血本身。
##   4. **TTK / TTD**: 玩家打死一只平均敌人要多久, 敌人打死玩家要多久。
##      这是唯一能把两边放在同一把尺子上的数。
##
## 用法:
##   godot --headless --path . --script tools/probe_player_power.gd

const RPGManager = preload("res://scripts/rpg_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const BalanceLog = preload("res://scripts/balance_log.gd")
const PlayerTank = preload("res://scripts/player.gd")

const BRANCHES := ["default", "speed", "heavy", "train"]

## player.gd::_fire() 里的基准冷却与地板值。这两个数在那边是 @export /
## 字面量, 没有常量可 import —— 这里注明来源, 改那边要同步改这里。
const BASE_FIRE_COOLDOWN := 0.65
const CD_FLOOR_SPEED := 0.18
const CD_FLOOR_OTHER := 0.32

## 一场常规战大概多久。用来把"每秒回复"折算成"这一场能回多少血"。
## 12 辆车 / 同屏上限 4 / 出车间隔 2.5 秒 -> 30 秒起步, 取 45 秒。
const BATTLE_SECONDS := 45.0

var rows: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> PLAYER POWER PROBE <<<")
	print("    commit=%s session=%s" % [BalanceLog.commit(), BalanceLog.session_id()])
	print("==================================================")
	_dps_by_branch()
	_cooldown_floor()
	_perk_inertness()
	_effective_hp()
	_regen_vs_incoming()
	print("==================================================")
	BalanceLog.emit_batch("player_power", rows)
	print(BalanceLog.summary())
	quit(0)


## 按真实的升级路径推到 lvl 级, 而不是直接给属性点 —— 属性点的分配节奏
## (_auto_level_bonus 里的 %2/%3/%4) 本身就是平衡的一部分。
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
	var cd := BASE_FIRE_COOLDOWN * m.get_fire_cooldown_mult(1)
	return maxf(CD_FLOOR_SPEED if branch == "speed" else CD_FLOOR_OTHER, cd)


func _dps_by_branch() -> void:
	print("\n--- 各分支 DPS (伤害 / 冷却) ---")
	print("等级  分支      阶  伤害   冷却   DPS   相对default")
	for lvl in [1, 6, 12, 18, 24]:
		var base_dps := 0.0
		for branch in BRANCHES:
			# 分支阶级随等级走: 大约 8 级一阶 (upgrade_selection_dialog 的节奏)
			var tier: int = clampi((lvl - 2) / 8, 0, 2)
			if branch == "default":
				tier = 0
			var m := _mgr_at(lvl, branch, tier)
			var dmg: int = m.get_atk_damage(1)
			var cd := _cd_for(m, branch)
			var dps := float(dmg) / cd
			if branch == "default":
				base_dps = dps
			rows.append({
				"metric": "dps", "level": lvl, "branch": branch, "tier": tier,
				"damage": dmg, "cooldown": cd, "dps": dps,
				"vs_default": dps / maxf(0.001, base_dps),
			})
			var line := "%4d  %-8s %2d  %4d  %5.3f  %5.2f   x%.2f" \
				% [lvl, branch, tier, dmg, cd, dps, dps / maxf(0.001, base_dps)]
			if branch == "train" and tier >= 2:
				# 车厢是 train 分支的全部特色, 但伤害写死不吃 atk_bonus
				var share := _train_carriage_share(dps)
				line += "   (+车厢 %.2f DPS, 占比 %.0f%%)" % [(1.0 + 2.0) / 0.85, 100.0 * share]
			print(line)
		print("")


## 冷却地板一旦咬住, 之后所有射速强化都是白买的。找出各分支从哪一级开始白买。
func _cooldown_floor() -> void:
	print("--- 射速强化从哪一级起完全无效 (冷却撞地板) ---")
	for branch in BRANCHES:
		var tier: int = 2
		var hit := -1
		for lvl in range(1, 41):
			var m := _mgr_at(lvl, branch, tier)
			var raw := BASE_FIRE_COOLDOWN * m.get_fire_cooldown_mult(1)
			var floor_v := CD_FLOOR_SPEED if branch == "speed" else CD_FLOOR_OTHER
			if raw <= floor_v:
				hit = lvl
				break
		rows.append({"metric": "cd_floor", "branch": branch, "level": hit})
		if hit < 0:
			print("  %-8s 一幕之内不会撞地板" % branch)
		else:
			print("  %-8s 从 %d 级起, 后续所有射速强化 (升级自动给的 / 商店 autoloader / perk rapid_loader) 完全无效"
				% [branch, hit])
	print("")


## rapid_loader (perk, 每层 +0.30 射速, 可叠 3 层) 和商店的 autoloader
## (+10% 射速) 都是玩家花代价换来的。冷却一旦撞地板, 它们就是纯白给, 而 UI
## 上照样写着 "+10% 装填速度"。这是最难被发现的一类失衡: 没有报错, 没有异常,
## 只是玩家的钱和 perk 位白花了。
func _perk_inertness() -> void:
	print("--- 叠了 rapid_loader 之后, 冷却从哪一级起撞地板 ---")
	for stacks in range(0, 4):
		for branch in ["default", "speed"]:
			var floor_v := CD_FLOOR_SPEED if branch == "speed" else CD_FLOOR_OTHER
			var hit := -1
			for lvl in range(1, 41):
				var m := _mgr_at(lvl, branch, 2)
				if stacks > 0:
					m.unlocked_perks["rapid_loader"] = stacks
				if BASE_FIRE_COOLDOWN * m.get_fire_cooldown_mult(1) <= floor_v:
					hit = lvl
					break
			rows.append({
				"metric": "cd_floor_perk", "branch": branch,
				"rapid_loader_stacks": stacks, "level": hit,
			})
			print("  %-8s rapid_loader x%d -> %s"
				% [branch, stacks,
				   "一幕内不撞地板" if hit < 0 else "%d 级起射速强化全部无效" % hit])
	print("")


## 车厢的伤害是写死的 1 / 2 (train_carriage.gd::_fire_bullet), **不吃
## atk_bonus**。所以随着主炮伤害一路涨到 7-13, 车厢的贡献占比会一路稀释。
func _train_carriage_share(main_dps: float) -> float:
	# tier2: 炮塔车厢 (伤害1) + 火箭车厢 (伤害2), 两者 fire_interval 都是 0.85
	var carriage_dps := (1.0 + 2.0) / 0.85
	return carriage_dps / (main_dps + carriage_dps)


func _effective_hp() -> void:
	print("--- 有效血量 = 最大血 + 每秒回复 x 一场 %.0f 秒 ---" % BATTLE_SECONDS)
	print("等级  分支      最大血  回复/秒  一场能回  有效血量  相当于挨几发(1伤)")
	for lvl in [6, 12, 18, 24]:
		for branch in BRANCHES:
			var tier: int = clampi((lvl - 2) / 8, 0, 2)
			if branch == "default":
				tier = 0
			var m := _mgr_at(lvl, branch, tier)
			var hp: int = m.get_player_max_hp(1)
			var regen: float = m.get_regen_rate(1)
			var healed := regen * BATTLE_SECONDS
			var eff := float(hp) + healed
			rows.append({
				"metric": "ehp", "level": lvl, "branch": branch, "tier": tier,
				"max_hp": hp, "regen": regen, "effective_hp": eff,
			})
			print("%4d  %-8s %6d  %7.2f  %8.1f  %8.1f  %d"
				% [lvl, branch, hp, regen, healed, eff, int(eff)])
		print("")


## 回复是每秒结算的, 所以真正要问的不是"回复多不多", 而是**敌人每秒要打中
## 几发才能压过它**。这个数不需要假设命中率, 是纯比值。
##
## 场上同时最多 main.gd::MAX_ALIVE_BASE 辆车, 常规兵的 fire_interval 在
## 1.6-2.8 之间, 子弹伤害 1 (少数 2-3)。
func _regen_vs_incoming() -> void:
	print("--- 回复 vs 敌方火力 ---")
	print("等级  回复/秒  敌人需要的命中率(4辆同屏, 平均2.2秒一发, 1伤)")
	var shots_per_sec := 4.0 / 2.2 # 同屏 4 辆, 平均 2.2 秒一发
	for lvl in [6, 12, 18, 24]:
		var m := _mgr_at(lvl, "default", 0)
		var regen: float = m.get_regen_rate(1)
		var need := regen / shots_per_sec
		rows.append({
			"metric": "regen_vs_fire", "level": lvl,
			"regen": regen, "needed_hit_rate": need,
		})
		var note := ""
		if need >= 1.0:
			note = "  <== 全中都压不过回复"
		elif need >= 0.6:
			note = "  <== 需要极高命中率"
		print("%4d  %7.2f  %5.0f%%%s" % [lvl, regen, 100.0 * need, note])
	print("")
	print("  注: 命中率算的是「敌人射出的子弹里有多大比例打中玩家」。坦克大战里")
	print("  玩家一直在动、地形挡弹, 真实命中率远低于 50%。")
	print("")
