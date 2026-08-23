extends SceneTree

## 平衡性采样探针 —— 不做断言, 只负责把数据打到 logs/balance/*.jsonl,
## 由 tools/analyze_balance_log.py 出统计 (均值/标准差/分位数/偏度/峰度/正态检验)。
##
## 和 test_enemy_balance_curve.gd 的分工:
##   - 那个是**闸门**: 四条"曾经真实翻车过"的不变量, 失败就 exit 1。
##   - 这个是**尺子**: 不判对错, 只把分布打下来, 让"这次改动把秒杀率从 38%
##     压到 21%"这种话有依据。改数值之前跑一次, 改完再跑一次, 拿 --vs 对比。
##
## 三类记录:
##   enemy_roll  每一只刷出来的敌人一行 (类型/血/金/经验/速度)。样本量最大,
##               分布分析主要吃这张表。
##   floor_econ  每个 (楼层 × 战斗类型) 一行: 遭遇规模、期望金币收入、
##               整个货架买光的价格、秒杀率、廉价兵占比。
##   act_econ    每一局生成的幕一行: 最优路线上的商店数、全幕收入、
##               全幕可花掉的上限、盈余倍率。这张表是"金币到底够不够花"的正主。
##
## 采样成本的取舍: 敌人 roll 表只取决于 (floor, battle_type, act) 加 RNG,
## 与具体哪一局无关 —— 所以真实的 main.tscn 只按 (floor × battle_type) 实例化
## 60 次, 再把这 60 组均值喂给 400 局纯地图生成的幕经济 DP。反过来做 (每局都
## 实例化 15 次战场) 要慢七十倍, 而且一点额外信息都没有。
##
## 用法:
##   godot --headless --path . --script tools/probe_balance_report.gd
##   godot --headless --path . --script tools/probe_balance_report.gd -- --acts 800 --samples 120

const GameState = preload("res://scripts/game_state.gd")
const EnemyTank = preload("res://scripts/enemy.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")
const ShopDialog = preload("res://scripts/shop_dialog.gd")
const BalanceLog = preload("res://scripts/balance_log.gd")

## 每个 (楼层 × 战斗类型) 刷多少只。90 只足够让类型占比稳到 ±5%,
## 也足够让血量直方图有形状。
var samples: int = 90
## 幕经济跑多少局。DP 是纯计算, 400 局不到一秒。
var acts: int = 400

const BATTLE_TYPES := ["battle", "elite", "challenge", "boss"]
## 节点类型 -> 战斗类型。shop/rest/event 不打仗, 不产金。
const NODE_TO_BATTLE := {
	"battle": "battle", "elite": "elite", "challenge": "challenge", "boss": "boss",
}

var _main: Node = null
var _pending: Array = []
var _type_names: Dictionary = {}

## (floor, battle_type) -> 该组的均值汇总, 幕经济复用
var _floor_table: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _on_child(n: Node) -> void:
	if n is EnemyTank:
		_pending.append(n)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--samples":
			samples = maxi(10, int(args[i + 1]))
		elif args[i] == "--acts":
			acts = maxi(10, int(args[i + 1]))


func _run() -> void:
	_parse_args()
	for k in EnemyTank.EnemyType.keys():
		_type_names[int(EnemyTank.EnemyType[k])] = str(k)

	print("==================================================")
	print(">>> BALANCE PROBE  (samples=%d/组, acts=%d 局) <<<" % [samples, acts])
	print("    commit=%s session=%s" % [BalanceLog.commit(), BalanceLog.session_id()])
	print("==================================================")

	if not BalanceLog.is_enabled():
		print("[WARN] BalanceLog 被关闭了 (TANK_BALANCE_LOG=0 或非 debug 构建), 只会打屏不落盘")

	await _sample_all_floors()
	_report_acts()

	print("==================================================")
	print(BalanceLog.summary())
	print("下一步: python tools/analyze_balance_log.py")
	quit(0)


# ---------------------------------------------------------------- 敌人 / 楼层

func _sample_all_floors() -> void:
	# 沿着一幕推进, 边走边按真实奖励升级, 这样"玩家伤害"是挣出来的而不是拍的
	# —— 秒杀率只有在真实成长曲线下才有意义。
	var mgr = RPGManager.new()
	mgr.reset()
	var level := 1
	var xp_pool := 0
	var xp_to_next := 100

	_shelf_base = await _shelf_prices()
	var basket := _shelf_base

	print("\nfloor  bt         规模  均HP   总HP  均金  层收入  货架价  伤害  STK  秒杀%  廉价%")
	print("--------------------------------------------------------------------------------")

	for f in range(GameState.max_floors):
		for bt in BATTLE_TYPES:
			# boss 只在最后一层, 其余层跑 boss 表没有意义
			if bt == "boss" and f != GameState.max_floors - 1:
				continue
			var r = await _sample_floor(bt, f)
			if r.is_empty():
				continue

			var dmg: int = mgr.get_atk_damage(1)
			var one_shot := 0
			var stk_tot := 0.0
			for hp in r["hp_list"]:
				if int(hp) <= dmg:
					one_shot += 1
				stk_tot += ceil(float(hp) / float(maxi(1, dmg)))
			var nhp := maxf(1.0, float(r["hp_list"].size()))
			var one_shot_pct := 100.0 * float(one_shot) / nhp
			# 平均需要打几发才死。比"一发秒杀率"稳得多: 伤害是整数, 均血在 8-10
			# 一带时 dmg 每跳 1 就会把一大片样本从"两发"翻到"一发", 秒杀率因此
			# 上下抖十几个点; STK 是连续量, 才看得出趋势。
			var stk := stk_tot / nhp

			var enc := int(r["encounter"])
			# 金币只有一条来源: enemy.gd::_die() 里 40% 概率掉一枚 gold_value 的币,
			# 而且要真的开过去捡。这里算的是"全捡到"的上限。
			var income := float(r["avg_gold"]) * 0.4 * float(enc)

			r["floor"] = f
			r["bt"] = bt
			r["dmg"] = dmg
			r["one_shot_pct"] = one_shot_pct
			r["stk"] = stk
			r["income"] = income
			r["basket"] = int(round(float(basket) * (1.0 + float(f) * _price_slope())))
			r.erase("hp_list")
			r.erase("rolls")
			BalanceLog.emit("floor_econ", r)

			_floor_table["%d|%s" % [f, bt]] = {
				"income": income, "enc": enc,
				"avg_hp": float(r["avg_hp"]), "avg_xp": float(r["avg_xp"]),
			}

			print("%5d  %-9s %4d %6.2f %6.0f %5.1f %7.0f %8d %5d %4.2f %6.0f %6.0f"
				% [f, bt, enc, float(r["avg_hp"]), float(r["total_hp"]),
				   float(r["avg_gold"]), income, int(r["basket"]),
				   dmg, stk, one_shot_pct, float(r["cheap_pct"])])

		# 打完这一层的常规战之后按真实经验升级, 供下一层算秒杀率
		var key := "%d|battle" % f
		if _floor_table.has(key):
			var t = _floor_table[key]
			xp_pool += int(float(t["avg_xp"]) * float(t["enc"]))
			while xp_pool >= xp_to_next:
				xp_pool -= xp_to_next
				level += 1
				xp_to_next = int(100.0 * pow(1.22, level - 1))
				mgr.level = level
				mgr._auto_level_bonus()


## 价格斜率要从 ShopDialog 反推, 不能在这里再写一遍常数 —— 复刻必然漂移。
func _price_slope() -> float:
	var prev := GameState.current_floor
	GameState.current_floor = 0
	var a := float(ShopDialog._price_for(1000))
	GameState.current_floor = 10
	var b := float(ShopDialog._price_for(1000))
	GameState.current_floor = prev
	return (b / maxf(1.0, a) - 1.0) / 10.0


## 一整个货架买光要多少钱 (floor 0 基准价)。走真实的 setup_shop(), 所以
## "6 选 11 的强化 + 11 种建材全上架"这个结构变了这里自动跟着变。
func _shelf_prices() -> float:
	GameState.reset_campaign(1)
	GameState.current_floor = 0
	var scn: PackedScene = load("res://scenes/shop_dialog.tscn")
	var shop = scn.instantiate()
	root.add_child(shop)
	await process_frame
	var tot := 0.0
	var trials := 40
	for i in range(trials):
		shop.setup_shop()
		for it in shop.current_shop_items:
			tot += float(it["cost"])
	shop.free()
	return tot / float(trials)


func _sample_floor(bt: String, floor_idx: int) -> Dictionary:
	GameState.reset_campaign(1)
	GameState.mode = GameState.GameMode.CAMPAIGN
	GameState.current_act = 1
	GameState.current_floor = floor_idx
	GameState.battle_type = bt

	var scn = load("res://scenes/main.tscn")
	_main = scn.instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame

	# start_game() 已经按 battle_type 定好了真实遭遇规模, 先读下来再覆盖 ——
	# 这个数字不能在探针里复刻 (main.gd::start_game 改了这里就悄悄错了)。
	var encounter := int(_main.total_enemies)

	_pending = []
	_main.actors_container.child_entered_tree.connect(_on_child)
	_main.total_enemies = 100000
	_main.enemies_spawned = 0
	for i in range(samples):
		_main._request_spawn_enemy()
	# 入树瞬间计数, 不能等一会儿数场上剩谁: 自爆卡车 84px 的 AoE 会把周围脆皮
	# 一起带走, 存活样本严重偏向高血量单位 (实测 TRAIN_BOSS 会从 15% 读成 26%)。
	await create_timer(1.0).timeout

	var hp_tot := 0.0
	var gold_tot := 0.0
	var xp_tot := 0.0
	var n := 0
	var cheap := 0
	var hp_list: Array = []
	var rows: Array = []
	for node in _pending:
		if not is_instance_valid(node):
			continue
		var tname: String = str(_type_names.get(int(node.enemy_type), "?"))
		hp_tot += float(node.max_health)
		gold_tot += float(node.gold_value)
		xp_tot += float(node.xp_value)
		hp_list.append(int(node.max_health))
		if node.enemy_type == EnemyTank.EnemyType.BASIC or node.enemy_type == EnemyTank.EnemyType.FAST:
			cheap += 1
		n += 1
		rows.append({
			"floor": floor_idx, "bt": bt, "type": tname,
			"hp": int(node.max_health), "gold": int(node.gold_value),
			"xp": int(node.xp_value), "speed": float(node.speed),
			"fire_interval": float(node.fire_interval),
		})

	var m := _main
	_main = null
	current_scene = null
	# queue_free + 让一帧过去, 不能直接 free(): 场上还有敌人在跑 Tween, 而
	# Tween 的回调是捕获了节点的 lambda —— 立刻 free 会让它们在下一次触发时
	# 打出一串 "Lambda capture at index 0 was freed"。那是探针自己制造的噪音,
	# 不是游戏的问题, 但混在输出里会让人误以为查到了 bug (以前就误判过一次)。
	m.queue_free()
	await process_frame

	if n == 0:
		return {}

	BalanceLog.emit_batch("enemy_roll", rows)

	var fn := float(n)
	return {
		"encounter": encounter,
		"n": n,
		"avg_hp": hp_tot / fn,
		"total_hp": (hp_tot / fn) * float(encounter),
		"avg_gold": gold_tot / fn,
		"avg_xp": xp_tot / fn,
		"cheap_pct": 100.0 * float(cheap) / fn,
		"hp_list": hp_list,
	}


# ---------------------------------------------------------------- 幕经济

## 每一局: 生成真实的 spire 图, 用 DP 找"商店最多"的那条路线, 沿路累加收入。
##
## 为什么必须 DP 而不是随机漫步: 真实玩家是**冲着商店走**的。早先用随机漫步
## 测出"8% 的局整幕无商店", 换成 DP 之后真实值是 0.3% —— 差了一个数量级,
## 而且方向是把问题夸大, 会引出错误的补救。
func _report_acts() -> void:
	print("\n--- 幕经济 (%d 局, 最优路线) ---" % acts)
	var rows: Array = []
	var shops_hist := {}
	var inc_sum := 0.0
	var spend_sum := 0.0
	var ratio_sum := 0.0

	for i in range(acts):
		GameState.reset_campaign(1)
		var res := _best_route()
		var shops := int(res["shops"])
		var income := float(res["income"])
		# 能花掉的上限 = 每到一个商店把货架买光 (含该层价格缩放)
		var spend := float(res["spend"])
		var ratio := income / maxf(1.0, spend)

		shops_hist[shops] = int(shops_hist.get(shops, 0)) + 1
		inc_sum += income
		spend_sum += spend
		ratio_sum += ratio
		rows.append({
			"run_seed": GameState.run_seed,
			"shops": shops,
			"income": int(round(income)),
			"spend_cap": int(round(spend)),
			"surplus_ratio": ratio,
			"battles": int(res["battles"]),
		})

	BalanceLog.emit_batch("act_econ", rows)

	var keys := shops_hist.keys()
	keys.sort()
	var hist := PackedStringArray()
	for k in keys:
		hist.append("%d商店:%.1f%%" % [k, 100.0 * float(shops_hist[k]) / float(acts)])
	print("  商店数分布  %s" % "  ".join(hist))
	print("  全幕收入均值 %.0f G   可花上限均值 %.0f G   盈余倍率均值 %.2fx"
		% [inc_sum / float(acts), spend_sum / float(acts), ratio_sum / float(acts)])
	if ratio_sum / float(acts) > 1.35:
		print("  [注意] 盈余倍率 > 1.35 —— 金币在中后期没有东西可买, 不再是需要权衡的资源")


## 在 DAG 上求"商店最多"的路线, 同时带出这条路线上的收入与可花上限。
func _best_route() -> Dictionary:
	var succ := {}
	for c in GameState.spire_connections:
		var f := str(c["from"])
		if not succ.has(f):
			succ[f] = []
		succ[f].append(str(c["to"]))

	# 按楼层从后往前推
	var best := {}   # node_id -> {shops, income, spend, battles}
	var by_floor := {}
	for nid in GameState.spire_nodes:
		var fl := int(GameState.spire_nodes[nid]["floor"])
		if not by_floor.has(fl):
			by_floor[fl] = []
		by_floor[fl].append(str(nid))

	var floors := by_floor.keys()
	floors.sort()
	floors.reverse()

	for fl in floors:
		for nid in by_floor[fl]:
			var node = GameState.spire_nodes[nid]
			var ntype := str(node["type"])
			var self_shop := 1 if ntype == "shop" else 0
			var self_income := 0.0
			var self_battle := 0
			if NODE_TO_BATTLE.has(ntype):
				var key := "%d|%s" % [fl, NODE_TO_BATTLE[ntype]]
				if _floor_table.has(key):
					self_income = float(_floor_table[key]["income"])
					self_battle = 1
			# 在这一层的商店里能花掉多少 (价格随层缩放)
			var self_spend := 0.0
			if self_shop == 1:
				self_spend = _shelf_at(fl)

			var b := {"shops": self_shop, "income": self_income, "spend": self_spend, "battles": self_battle}
			if succ.has(nid):
				var pick = null
				for nxt in succ[nid]:
					if not best.has(nxt):
						continue
					var cand = best[nxt]
					# 先比商店数, 再比收入 —— 玩家优先保证有地方花钱
					if pick == null or int(cand["shops"]) > int(pick["shops"]) \
							or (int(cand["shops"]) == int(pick["shops"]) and float(cand["income"]) > float(pick["income"])):
						pick = cand
				if pick != null:
					b["shops"] += int(pick["shops"])
					b["income"] += float(pick["income"])
					b["spend"] += float(pick["spend"])
					b["battles"] += int(pick["battles"])
			best[nid] = b

	var top = null
	for nid in by_floor.get(0, []):
		if not best.has(nid):
			continue
		var cand = best[nid]
		if top == null or int(cand["shops"]) > int(top["shops"]) \
				or (int(cand["shops"]) == int(top["shops"]) and float(cand["income"]) > float(top["income"])):
			top = cand
	if top == null:
		return {"shops": 0, "income": 0.0, "spend": 1.0, "battles": 0}
	return top


## floor 0 的整货架价, 由 _shelf_prices() 在采样阶段填好
var _shelf_base: float = 0.0

func _shelf_at(fl: int) -> float:
	return _shelf_base * (1.0 + float(fl) * _price_slope())
