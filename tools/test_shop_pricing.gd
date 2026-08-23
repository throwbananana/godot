extends SceneTree

## 商店经济结构的回归测试 —— 锁住三条"不会报错但会让资源失去意义"的性质。
##
## 1. 一条路线上至少能走到 GameState.MIN_SHOPS_PER_ACT 个商店。商店是
##    GameState.structure_inventory 的**唯一**来源 (add_structure_stock 全项目
##    只被 shop_dialog.gd 调用), 所以商店不够 = 这一幕的建造系统半瘫, 热键栏
##    大半是空的, 而玩家无从分辨这是运气还是功能坏了。
##
##    注意断言的是**路线**而不是整幅图: 最早的版本只查"图里存在 shop 节点",
##    可玩家走的是一条路径, 分散在互不相通的支路上的商店对他毫无意义。实测
##    路线商店数从 1 到 7 都有, 而它几乎单独决定了金币的盈余倍率。
##
## 2. 售价要随楼层缩放。表里的价格是"第 1 层的价格", 而收入侧一路在涨 ——
##    实测一层的期望金币从 91 G 涨到 678 G。价格不动的话, 金币在中后期就
##    不再是需要权衡的资源。
##
## 3. 刷新费用要在同一次进店内递增。货架的设计是"11 种强化里随机上架 6 种",
##    "这次没抽到"本该是真实取舍; 但固定 20 G 且无限刷的话, 中后期一层的
##    收入够刷三十次, 那条约束纯属装饰。

const GameState = preload("res://scripts/game_state.gd")
const BalanceLog = preload("res://scripts/balance_log.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	# 必须 deferred: SceneTree._init() 阶段 root 还没就绪, 这时
	# root.add_child() 的节点不算真正入树, @onready 不会解析 ——
	# 对话框一调 _update_ui() 就会对着 null 的 gold_label 赋值报错。
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> SHOP PRICING / ECONOMY STRUCTURE TEST <<<")
	print("==================================================")
	_check_shop_guaranteed()
	_check_price_scales_with_floor()
	_check_reroll_escalates()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL SHOP PRICING CHECKS PASSED! <<<")
		quit(0)


## 保底管的是"**一条路线上**能走到几个商店", 不是"整幅图里存在几个"。
##
## 玩家走的是一条路径。整幅图有五个商店但分散在互不相通的三条支路上, 对玩家
## 来说和只有一个没区别。实测 (tools/probe_balance_report.gd) 最优路线上的
## 商店数直接决定金币的盈余倍率:
##
##     路线商店数   1     2     3     4     5     6     7
##     盈余倍率   3.82  1.80  1.12  0.75  0.58  0.39  0.29
##
## 保底之前 21.6% 的局最优路线只有 1-2 个商店, 那些局玩家揣着两到四倍花不掉的
## 金币, 而这跟他打得好不好毫无关系。
func _check_shop_guaranteed() -> void:
	print("\n--- 一条路线上至少能走到 %d 个商店 ---" % GameState.MIN_SHOPS_PER_ACT)
	var runs := 400
	var bad := 0
	var min_shops := 999
	var hist := {}
	var rows: Array = []
	for i in range(runs):
		GameState.reset_campaign(1)
		var count := 0
		for nid in GameState.best_shop_route():
			if str(GameState.spire_nodes[nid]["type"]) == "shop":
				count += 1
		if count < GameState.MIN_SHOPS_PER_ACT:
			bad += 1
		min_shops = mini(min_shops, count)
		hist[count] = int(hist.get(count, 0)) + 1
		rows.append({"run_seed": GameState.run_seed, "route_shops": count})

	# 顺手落一份盘, 这样"改了发图逻辑之后商店数分布变了没有"是可以 diff 的
	BalanceLog.emit_batch("route_shops", rows)

	var keys: Array = hist.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%d:%.1f%%" % [k, 100.0 * float(hist[k]) / float(runs)])

	if bad == 0:
		ok("%d 局的最优路线全部 >= %d 个商店 (最少 %d, 分布 %s)"
			% [runs, GameState.MIN_SHOPS_PER_ACT, min_shops, " ".join(parts)])
	else:
		fail("%d/%d 局的最优路线不足 %d 个商店 (最少只有 %d, 分布 %s) —— "
			% [bad, runs, GameState.MIN_SHOPS_PER_ACT, min_shops, " ".join(parts)]
			+ "这些局的金币有一大半没有地方花, 而且建材也拿不够")


func _check_price_scales_with_floor() -> void:
	print("\n--- 售价随楼层上涨 ---")
	var scn: PackedScene = load("res://scenes/shop_dialog.tscn")
	var shop = scn.instantiate()
	root.add_child(shop)

	GameState.reset_campaign(1)
	GameState.current_floor = 0
	var base := int(shop._price_for(100))
	GameState.current_floor = 14
	var late := int(shop._price_for(100))
	shop.free()

	if base == 100:
		ok("floor 0 的价格等于表里写的基准价 (%d)" % base)
	else:
		fail("floor 0 的价格是 %d, 应等于基准价 100" % base)

	if late > base:
		ok("floor 14 的同一件商品是 %d G (基准 %d, x%.2f)" % [late, base, float(late) / float(base)])
	else:
		fail("floor 14 (%d) 没有比 floor 0 (%d) 贵 —— 收入一路在涨而售价不动, "
			% [late, base] + "金币到中后期就不再是需要权衡的资源")


func _check_reroll_escalates() -> void:
	print("\n--- 同一次进店内, 刷新费用递增 ---")
	var scn: PackedScene = load("res://scenes/shop_dialog.tscn")
	var shop = scn.instantiate()
	root.add_child(shop)

	GameState.reset_campaign(1)
	GameState.gold = 100000
	shop.setup_shop()

	var costs: Array[int] = []
	for i in range(4):
		costs.append(int(shop.reroll_cost))
		shop._on_reroll_pressed()

	var strictly_up := true
	for i in range(1, costs.size()):
		if costs[i] <= costs[i - 1]:
			strictly_up = false
	if strictly_up:
		ok("连续四次刷新报价: %s" % str(costs))
	else:
		fail("刷新费用没有递增: %s —— 固定价 + 无限刷会让'随机上架 6 种'完全失效"
			% str(costs))

	# 再次进店必须重置, 涨价不跨商店惩罚
	shop.setup_shop()
	var after := int(shop.reroll_cost)
	shop.free()
	if after == costs[0]:
		ok("重新进店后刷新价重置回 %d" % after)
	else:
		fail("重新进店后刷新价是 %d, 应重置回 %d" % [after, costs[0]])
