extends SceneTree

## 商店经济结构的回归测试 —— 锁住三条"不会报错但会让资源失去意义"的性质。
##
## 1. 每一层楼至少有 FloorMap.MIN_SHOPS_PER_FLOOR 个**可达的**商店房。商店是
##    GameState.structure_inventory 的**唯一**来源 (add_structure_stock 全项目
##    只被 shop_dialog.gd 调用), 所以商店不够 = 这一幕的建造系统半瘫, 热键栏
##    大半是空的, 而玩家无从分辨这是运气还是功能坏了。
##
##    尖塔时代这条断言的是"**一条路线上**能走到几个商店" —— 那张图是有向无环
##    的, 玩家单向向上爬, 分散在互不相通的支路上的商店等于不存在。以撒式房间图
##    是**无向连通图**, 玩家可以回头, "一条路线"这个概念不再成立: 只要商店房
##    在图上且连通, 玩家就走得到。所以断言换成"这一层有商店房"+"它从起始房可达"。
##    可达性单独查是因为商店是分给死胡同的, 而死胡同由门的邻接关系算出 —— 门
##    的生成一旦出错, 商店房会"存在"但四面无门, 只数数量的话这种图能蒙混过关。
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
const FloorMap = preload("res://scripts/floor_map.gd")

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


## 每一层楼都要有商店房, 而且它得能从起始房走到。
##
## 数量和可达性分开查是有意的: 商店是分给**死胡同**的 (FloorMap._assign_types),
## 而死胡同是从门的邻接关系算出来的 —— 门的生成一旦出错, 商店房会"存在"但四面
## 无门, 只数数量的话这种图能完美蒙混过关。
func _check_shop_guaranteed() -> void:
	print("\n--- 每层至少 %d 个可达的商店房 ---" % FloorMap.MIN_SHOPS_PER_FLOOR)
	var runs := 400
	var bad := 0
	var unreachable := 0
	var min_shops := 999
	var hist := {}
	var rows: Array = []
	for i in range(runs):
		GameState.reset_campaign(1)
		var count := 0
		var reachable := _reachable_room_keys()
		for k in GameState.floor_rooms.keys():
			if str(GameState.floor_rooms[k]["type"]) != "shop":
				continue
			count += 1
			if not reachable.has(str(k)):
				unreachable += 1
		if count < FloorMap.MIN_SHOPS_PER_FLOOR:
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

	if unreachable > 0:
		fail("%d 个商店房从起始房走不到 —— 门的生成有问题" % unreachable)

	if bad == 0:
		ok("%d 层全部 >= %d 个商店房且均可达 (最少 %d, 分布 %s)"
			% [runs, FloorMap.MIN_SHOPS_PER_FLOOR, min_shops, " ".join(parts)])
	else:
		fail("%d/%d 层不足 %d 个商店房 (最少只有 %d, 分布 %s) —— "
			% [bad, runs, FloorMap.MIN_SHOPS_PER_FLOOR, min_shops, " ".join(parts)]
			+ "这些局的金币有一大半没有地方花, 而且建材也拿不够")


## 从起始房沿**门**做无向 BFS。走门而不是走格子邻接 —— 要验收的正是门。
func _reachable_room_keys() -> Dictionary:
	var seen := {}
	var start := str(GameState.floor_start_room)
	if not GameState.floor_rooms.has(start):
		return seen
	seen[start] = true
	var queue: Array = [start]
	while not queue.is_empty():
		var k: String = queue.pop_front()
		var c := FloorMap.parse_key(k)
		var doors: Array = GameState.floor_rooms[k]["doors"]
		for d in range(4):
			if not bool(doors[d]):
				continue
			var nk := FloorMap.key(c + FloorMap.DIR_VECTORS[d])
			if GameState.floor_rooms.has(nk) and not seen.has(nk):
				seen[nk] = true
				queue.append(nk)
	return seen


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
