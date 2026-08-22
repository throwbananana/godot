extends SceneTree

## 敌人平衡曲线的回归测试。
##
## 这里锁的每一条都对应一个真实存在过、而且**完全不会报错**的缺陷 —— 数值
## 失衡既不会 crash 也过不了编译检查, 只会让游戏变得没意思, 所以必须有断言。
##
##   1. 一发秒杀率。get_atk_damage() 是 1 + atk_bonus, 而 _auto_level_bonus()
##      曾经每级 +1, 等于**伤害 == 等级**, 线性无上限; 配上"血量不吃楼层缩放",
##      实测 floor 4 到全幕结束玩家一发秒掉场上 100% 的敌人, 包括 14 血的
##      TRAIN_BOSS 和 10 血的 BOSS。整个血量分层维度报废。
##   2. 幕内强度爬升。floor_mult 当初只乘 xp/gold/score 不乘 max_health,
##      于是 floor 5 到 14 的遭遇总血量一直在 58-69 打转 —— 后十层只有奖励在
##      涨, 强度纹丝不动。
##   3. TRAIN_BOSS 不当常规杂兵。它会点亮 HUD boss 血条并占用
##      active_boss_instance; 实测常规战里它占 17-21%, 是 floor 5 之后出现
##      最多的单一类型, 而精英/boss 战的填充位反而 0% —— boss 单位在常规层
##      比在 boss 层常见三到四倍。
##   4. 门禁不得把 roll 表砸成 FAST 沼泽。_gate_enemy_type() 曾经一律降级成
##      FAST, 于是 floor 3 的表列了 8 个条目却有 62% 是 FAST, 比 floor 2 还
##      单调 —— 读代码像花样最多的一层, 玩起来是全局最单调的一层。
##
## 测法: 不复刻 roll 表 (复刻必然漂移), 直接驱动真实的
## main.gd::_request_spawn_enemy(), 并在 child_entered_tree 的**入树瞬间**
## 计数 —— 不能等一会儿再数场上剩谁, 因为自爆卡车 (84px AoE) 会把周围脆皮
## 一起带走, 存活样本严重偏向高血量单位。

const GameState = preload("res://scripts/game_state.gd")
const EnemyTank = preload("res://scripts/enemy.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")

const SAMPLES := 140

var failures: int = 0
var _main: Node = null
var _pending: Array = []


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _on_child(n: Node) -> void:
	if n is EnemyTank:
		_pending.append(n)


func _run() -> void:
	print("==================================================")
	print(">>> ENEMY BALANCE CURVE TEST <<<")
	print("==================================================")

	# 沿着一幕推进, 边走边按真实奖励升级, 这样"玩家伤害"是挣出来的而不是拍的
	var mgr = RPGManager.new()
	mgr.reset()
	var level := 1
	var xp_pool := 0
	var xp_to_next := 100
	var stats := {}

	for f in range(15):
		var bt := "battle"
		var enc := 12
		if f == 14:
			bt = "boss"; enc = 24
		elif f == 7:
			bt = "elite"; enc = 18

		var r = await _sample(bt, f)
		xp_pool += int(float(r["avg_xp"]) * float(enc))
		while xp_pool >= xp_to_next:
			xp_pool -= xp_to_next
			level += 1
			xp_to_next = int(100.0 * pow(1.22, level - 1))
			mgr.level = level
			mgr._auto_level_bonus()

		var dmg: int = mgr.get_atk_damage(1)
		var one_shot := 0
		for hp in r["hp_list"]:
			if int(hp) <= dmg:
				one_shot += 1
		r["one_shot"] = 100.0 * float(one_shot) / maxf(1.0, float(r["hp_list"].size()))
		r["dmg"] = dmg
		r["bt"] = bt
		stats[f] = r
		print("  floor %2d (%-4s): 均HP %5.2f  伤害 %2d  秒杀 %3.0f%%  廉价兵 %3.0f%%  TRAIN_BOSS %2.0f%%"
			% [f, bt, float(r["avg_hp"]), dmg, float(r["one_shot"]),
			   float(r["cheap_pct"]), float(r["train_pct"])])

	print("")
	_check_one_shot(stats)
	_check_ramp(stats)
	_check_no_train_filler(stats)
	_check_gate_variety(stats)

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL BALANCE CHECKS PASSED! <<<")
		quit(0)


## 1. 不允许出现"从某层起一路 100% 秒杀"。floor 0-1 是新手层, 100% 是设计内的。
func _check_one_shot(stats: Dictionary) -> void:
	var bad: Array[String] = []
	for f in range(3, 15):
		if float(stats[f]["one_shot"]) >= 99.5:
			bad.append("f%d" % f)
	if bad.is_empty():
		ok("floor 3+ 没有任何一层是一发全秒 (最高 %.0f%%)" % _max_of(stats, "one_shot", 3))
	else:
		fail("这些层玩家一发秒掉全场: %s —— 敌人血量分层已失效, "
			% ", ".join(bad)
			+ "检查 rpg_manager._auto_level_bonus() 的攻击力节奏与 enemy.gd 的 floor_mult 是否作用于 max_health")


## 2. 幕内强度必须爬升, 不能后十层持平。
func _check_ramp(stats: Dictionary) -> void:
	var early := float(stats[4]["avg_hp"])
	var late := float(stats[12]["avg_hp"])
	if late > early * 1.25:
		ok("幕内强度确实在爬升: floor 4 均HP %.2f -> floor 12 %.2f (x%.2f)"
			% [early, late, late / early])
	else:
		fail("floor 4 (%.2f) 到 floor 12 (%.2f) 敌人几乎没变强 —— 后十层只有奖励在涨"
			% [early, late])


## 3. TRAIN_BOSS 只能是遭遇身份, 不能当常规填充兵。
func _check_no_train_filler(stats: Dictionary) -> void:
	var bad: Array[String] = []
	for f in range(15):
		if stats[f]["bt"] != "battle":
			continue
		if float(stats[f]["train_pct"]) > 0.0:
			bad.append("f%d %.0f%%" % [f, float(stats[f]["train_pct"])])
	if bad.is_empty():
		ok("常规战里没有 TRAIN_BOSS (它会点亮 HUD boss 血条, 属于遭遇身份)")
	else:
		fail("常规战出现了 TRAIN_BOSS: %s" % ", ".join(bad))


## 4. 门禁降级不得把中段楼层砸成 FAST 沼泽。
func _check_gate_variety(stats: Dictionary) -> void:
	var bad: Array[String] = []
	for f in [2, 3, 4, 5]:
		if float(stats[f]["cheap_pct"]) > 45.0:
			bad.append("f%d %.0f%%" % [f, float(stats[f]["cheap_pct"])])
	if bad.is_empty():
		ok("floor 2-5 的廉价兵(BASIC/FAST)占比都在 45%% 以内 (最高 %.0f%%)"
			% maxf(maxf(float(stats[2]["cheap_pct"]), float(stats[3]["cheap_pct"])),
				   maxf(float(stats[4]["cheap_pct"]), float(stats[5]["cheap_pct"]))))
	else:
		fail("这些层过半是 BASIC/FAST: %s —— _gate_enemy_type() 是不是又把没解锁的类型一律砸成 FAST 了"
			% ", ".join(bad))


func _max_of(stats: Dictionary, key: String, from_floor: int) -> float:
	var m := 0.0
	for f in range(from_floor, 15):
		m = maxf(m, float(stats[f][key]))
	return m


func _sample(bt: String, floor_idx: int) -> Dictionary:
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

	_pending = []
	_main.actors_container.child_entered_tree.connect(_on_child)
	_main.total_enemies = 100000
	_main.enemies_spawned = 0
	for i in range(SAMPLES):
		_main._request_spawn_enemy()
	await create_timer(1.3).timeout

	var hp_tot := 0.0
	var xp_tot := 0.0
	var n := 0
	var cheap := 0
	var train := 0
	var hp_list: Array = []
	for node in _pending:
		if not is_instance_valid(node):
			continue
		hp_tot += float(node.max_health)
		xp_tot += float(node.xp_value)
		hp_list.append(int(node.max_health))
		if node.enemy_type == EnemyTank.EnemyType.BASIC or node.enemy_type == EnemyTank.EnemyType.FAST:
			cheap += 1
		if node.enemy_type == EnemyTank.EnemyType.TRAIN_BOSS:
			train += 1
		n += 1

	var m := _main
	_main = null
	current_scene = null
	m.free()

	var fn := maxf(1.0, float(n))
	return {
		"avg_hp": hp_tot / fn,
		"avg_xp": xp_tot / fn,
		"hp_list": hp_list,
		"cheap_pct": 100.0 * float(cheap) / fn,
		"train_pct": 100.0 * float(train) / fn,
	}
