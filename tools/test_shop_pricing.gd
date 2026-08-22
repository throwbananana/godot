extends SceneTree

## 商店经济结构的回归测试 —— 锁住三条"不会报错但会让资源失去意义"的性质。
##
## 1. 一幕之内必须至少有一个商店。商店是 GameState.structure_inventory 的
##    **唯一**来源 (add_structure_stock 全项目只被 shop_dialog.gd 调用),
##    所以一幅没有商店的图 = 这一幕整个建造系统不存在, 热键栏空着, 而玩家
##    无从分辨这是运气还是功能坏了。实测保底逻辑加入前, 300 局里有 0.3%
##    的图整幅无商店, 另有 4% 只有一个。
##
## 2. 售价要随楼层缩放。表里的价格是"第 1 层的价格", 而收入侧一路在涨 ——
##    实测一层的期望金币从 91 G 涨到 678 G。价格不动的话, 金币在中后期就
##    不再是需要权衡的资源。
##
## 3. 刷新费用要在同一次进店内递增。货架的设计是"11 种强化里随机上架 6 种",
##    "这次没抽到"本该是真实取舍; 但固定 20 G 且无限刷的话, 中后期一层的
##    收入够刷三十次, 那条约束纯属装饰。

const GameState = preload("res://scripts/game_state.gd")

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


func _check_shop_guaranteed() -> void:
	print("\n--- 每一幕都必须至少有一个商店 ---")
	var runs := 400
	var shopless := 0
	var min_shops := 999
	for i in range(runs):
		GameState.reset_campaign(1)
		var count := 0
		for nid in GameState.spire_nodes:
			if str(GameState.spire_nodes[nid]["type"]) == "shop":
				count += 1
		if count == 0:
			shopless += 1
		min_shops = mini(min_shops, count)
	if shopless == 0:
		ok("%d 局全部至少有一个商店 (最少的一局有 %d 个)" % [runs, min_shops])
	else:
		fail("%d/%d 局整幅图没有任何商店 —— 那一幕买不到也造不出任何建材"
			% [shopless, runs])


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
