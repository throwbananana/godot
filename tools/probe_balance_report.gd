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
	# 以撒式房间图里普通战斗房的 type 是 "normal" (FloorMap._new_room 的默认值),
	# 而它打的是 battle_type == "battle" 的那张遭遇表。
	"normal": "battle",
}

const FloorMap = preload("res://scripts/floor_map.gd")

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


## 一整个货架买光要多少钱 (floor 0 基准价)。
##
## 曾经走 shop_dialog.tscn 的 setup_shop()/current_shop_items —— 但那是"商店是
## 一个房间, 不是菜单"改造 (见 CLAUDE.md) 之前的对话框 UI 路径, 现在已经没有
## 任何场景会显示它。真正玩家看到的货架由 main.gd::_ensure_shop_stock() 决定:
## 从 build_inventory() 的"6 选 11 强化 + 15 种建材全在"里, 再各截取
## SHOP_UPGRADE_SLOTS(3)/SHOP_BUILD_SLOTS(3), 一共 6 件。旧版本在这里量的是
## 21 件的虚拟货架(6 强化 + 15 建材全算), 是量出来的价格的 3.28 倍 ——
## 于是 400 局的盈余倍率被系统性地压低到实际的 ~30%, 不是economy 真的这么紧。
func _shelf_prices() -> float:
	GameState.reset_campaign(1)
	GameState.current_floor = 0
	var tot := 0.0
	var trials := 200
	for i in range(trials):
		var upgrades: Array = []
		var builds: Array = []
		for it in ShopDialog.build_inventory():
			if str(it.get("category", "")) == "BUILD":
				builds.append(it)
			else:
				upgrades.append(it)
		builds.shuffle()
		for j in range(mini(MainGame.SHOP_UPGRADE_SLOTS, upgrades.size())):
			tot += float(upgrades[j]["cost"])
		for j in range(mini(MainGame.SHOP_BUILD_SLOTS, builds.size())):
			tot += float(builds[j]["cost"])
	return tot / float(trials)


## 等到坦克真的都入树了 —— 等增长停下来, 不是睡固定时长。理由见调用处。
func _await_spawns() -> void:
	var stable := 0
	var last := -1
	for _i in range(240):
		await process_frame
		if _pending.size() == last:
			stable += 1
			if stable >= 20 and last > 0:
				return
		else:
			stable = 0
			last = _pending.size()


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

	# main.tscn 一启动进的是**起始房**, 而起始房不是战斗房: enter_room() 会把
	# GameState.battle_type 按房型改写回 "battle", 并把 total_enemies 清零。
	# 不先把当前房间改造成目标房型的话, 下面读到的遭遇规模是 0, 而 roll 表也会
	# 一律采成 battle 表。改完重进一次走的仍然是真实的 enter_room() 路径。
	_force_room_battle_type(bt)
	await process_frame

	# _begin_room_encounter() 已经按 battle_type 定好了真实遭遇规模, 先读下来
	# 再覆盖 —— 这个数字不能在探针里复刻 (改了那边这里就悄悄错了)。
	var encounter := int(_main.total_enemies)

	_pending = []
	_main.actors_container.child_entered_tree.connect(_on_child)
	_main.total_enemies = 100000
	_main.enemies_spawned = 0
	for i in range(samples):
		_main._request_spawn_enemy()
	# 入树瞬间计数, 不能等一会儿数场上剩谁: 自爆卡车 84px 的 AoE 会把周围脆皮
	# 一起带走, 存活样本严重偏向高血量单位 (实测 TRAIN_BOSS 会从 15% 读成 26%)。
	#
	# 而且等的方式必须是"等到不再增长", 不能睡固定时长:
	# _request_spawn_enemy() 先放出生星星, 坦克要等星星动画播完的 finished
	# 回调才入树。固定 sleep 在机器忙的时候会拿到零只坦克, 报出来是"均血 0.00"
	# —— 看着像平衡崩了, 其实是没等够 (test_enemy_balance_curve.gd 上实测约
	# 17% 的运行会这样翻车)。
	await _await_spawns()

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

## 每一局: 生成真实的楼层房间图, 沿 BFS 序走完整层, 累加收入与可花上限。
##
## 尖塔时代这里是一个 DP ("找商店最多的那条路线"), 因为那张图是有向无环、
## 玩家单向向上爬, "走哪条路"是一个会漏掉大半张图的真实选择。房间图是
## 无向连通的, 玩家可以回头把整层逛完 —— "最优路线"不再存在, 上限就是全图。
##
## ⚠️ 这一改使得旧的盈余倍率基准线 (均值 0.68 / p90 1.01) **不再可比** ——
##    收入侧从"一条路线上的十几场"变成"整层十几个房间", 支出侧从"路线上
##    保底 3 个商店"变成"整层 1-2 个商店"。需要重新采样定基准。
##
## GameState.reset_campaign() 内部硬编码 current_act = 1, 单独调用永远只采样
## 第 1 幕 (target_room_count(1) = 8 间房, 摸不到 SHOP_SECOND_ROOMS)。之前
## 400 局跑下来"商店数分布 1商店:100.0%"看着像是保底逻辑坏了, 其实是这个
## 探针从没生成过 act >= 4 的楼层 (target_room_count 在 act 4 起封顶 11 间房)
## —— reset 之后手动把 current_act 摊到 1..max_acts 再重新 generate_floor(),
## 才是"整局跑下来"该有的样本分布, 而不是把 400 次都花在幕 1 上。
func _report_acts() -> void:
	print("\n--- 幕经济 (%d 局, 覆盖 act 1..%d, 走整层) ---" % [acts, GameState.max_acts])
	var rows: Array = []
	var shops_hist := {}
	var inc_sum := 0.0
	var spend_sum := 0.0
	var ratio_sum := 0.0

	for i in range(acts):
		GameState.reset_campaign(1)
		GameState.current_act = 1 + (i % GameState.max_acts)
		GameState.generate_floor()
		var res := _floor_econ()
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
			"act": GameState.current_act,
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


## 走一遍整层楼, 累加收入与可花上限。
##
## 这里原本是"在 DAG 上求商店最多的那条路线"的 DP —— 尖塔图是有向无环、玩家
## 单向向上爬, 所以"走哪条路"是一个真实的、会漏掉大半张图的选择, 必须 DP。
##
## 以撒式房间图是**无向连通图**: 玩家清完一间房走出来还能回头, 没有任何东西
## 阻止他把整层楼逛完。所以"最优路线"这个概念消失了 —— 上限就是**全图**。
## DP 换成一次 BFS 遍历。
##
## 保留 BFS **顺序**而不是直接对全图求和, 是因为收入和售价都随 current_floor
## 缩放, 而 current_floor 的新语义是"已清房间数" (见 game_state.gd)。也就是
## 说同一间房, 早打和晚打的收益不一样, 顺序有影响。BFS 序是对"由近及远清图"
## 这个真实走法的近似。
func _floor_econ() -> Dictionary:
	var start := str(GameState.floor_start_room)
	if not GameState.floor_rooms.has(start):
		return {"shops": 0, "income": 0.0, "spend": 1.0, "battles": 0}

	# 沿门做无向 BFS, 得到一个"由近及远"的房间序。
	var order: Array = []
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var k: String = queue.pop_front()
		order.append(k)
		var c := FloorMap.parse_key(k)
		var doors: Array = GameState.floor_rooms[k]["doors"]
		for d in range(4):
			if not bool(doors[d]):
				continue
			var nk := FloorMap.key(c + FloorMap.DIR_VECTORS[d])
			if GameState.floor_rooms.has(nk) and not seen.has(nk):
				seen[nk] = true
				queue.append(nk)

	var shops := 0
	var income := 0.0
	var spend := 0.0
	var battles := 0
	var cleared := 0

	for k in order:
		var room: Dictionary = GameState.floor_rooms[k]
		var rtype := str(room["type"])
		if rtype == "start":
			continue
		# 秘密房要炸墙, 不能算进"必然拿得到"的收入上限里。
		if bool(room.get("secret", false)):
			continue

		var fl: int = mini(cleared, GameState.max_floors - 1)

		if rtype == "shop":
			shops += 1
			spend += _shelf_at(fl)
		elif NODE_TO_BATTLE.has(rtype):
			var key := "%d|%s" % [fl, NODE_TO_BATTLE[rtype]]
			if _floor_table.has(key):
				income += float(_floor_table[key]["income"])
			battles += 1
			cleared += 1

	return {"shops": shops, "income": income, "spend": maxf(1.0, spend), "battles": battles}


## floor 0 的整货架价, 由 _shelf_prices() 在采样阶段填好
var _shelf_base: float = 0.0

func _shelf_at(fl: int) -> float:
	return _shelf_base * (1.0 + float(fl) * _price_slope())


## 把当前房间改造成能产出指定 battle_type 的房型, 再重进一次。
## 反向表对应 GameState.battle_type_for_room()。理由见 _sample_floor() 里的注释。
const BT_TO_ROOM_TYPE := {
	"battle": "normal", "elite": "elite", "challenge": "challenge", "boss": "boss",
}

func _force_room_battle_type(bt: String) -> void:
	var rk: String = GameState.current_room
	if not GameState.floor_rooms.has(rk):
		return
	GameState.floor_rooms[rk]["type"] = str(BT_TO_ROOM_TYPE.get(bt, "normal"))
	GameState.floor_rooms[rk]["cleared"] = false
	GameState.floor_rooms[rk]["challenge_mode"] = "vault" if bt == "challenge" else ""
	_main.enter_room(rk, -1)
