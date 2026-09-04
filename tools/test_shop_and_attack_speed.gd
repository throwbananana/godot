extends SceneTree

const PlayerTank = preload("res://scripts/player.gd")
const EnemyTank = preload("res://scripts/enemy.gd")
const ShopDialog = preload("res://scripts/shop_dialog.gd")
const GameState = preload("res://scripts/game_state.gd")

func _init() -> void:
	print("=== Running Shop System and Tank Attack Speed Rebalance Test ===")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var root_node = Node2D.new()
	root.add_child(root_node)

	# 1. Test Player Attack Speed
	print(">>> 1. Testing Player Attack Speed & Cooldown...")
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	root_node.add_child(player)
	assert(player.fire_cooldown >= 0.50, "Player base cooldown should be comfortably rhythmic (>= 0.50s)")
	print("✓ Player base fire cooldown verified: %s s" % player.fire_cooldown)

	# 2. Test Enemy Attack Speeds for All Types
	print(">>> 2. Testing Enemy Attack Speeds...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var expected_intervals = {
		EnemyTank.EnemyType.BASIC: 2.8,
		EnemyTank.EnemyType.FAST: 2.2,
		EnemyTank.EnemyType.POWER: 1.6,
		EnemyTank.EnemyType.ARMOR: 2.2,
		EnemyTank.EnemyType.MISSILE: 3.2,
		EnemyTank.EnemyType.LASER: 3.8,
		EnemyTank.EnemyType.BOSS: 2.0,
	}

	for e_type in expected_intervals.keys():
		var enemy = enemy_scene.instantiate()
		enemy.enemy_type = e_type
		root_node.add_child(enemy)
		var expected = expected_intervals[e_type]
		assert(enemy.fire_interval == expected, "Enemy type %s fire_interval should be %s, got %s" % [e_type, expected, enemy.fire_interval])
		print("✓ Enemy %s fire_interval: %s s" % [e_type, enemy.fire_interval])

	# 3. Test Shop System (Generation, Purchase, Gold, Reroll)
	print(">>> 3. Testing Black Market Shop System...")
	var shop_scene = load("res://scenes/shop_dialog.tscn")
	var shop_inst = shop_scene.instantiate()
	root.add_child(shop_inst)

	GameState.gold = 300
	GameState.player_tier = 0
	GameState.max_hp_lvl = 0

	shop_inst.setup_shop()
	assert(shop_inst.visible == true, "ShopDialog should be visible")
	assert(shop_inst.current_shop_items.size() >= 4, "Shop should generate at least 4 items")
	print("✓ Shop generated %d items." % shop_inst.current_shop_items.size())

	# Test purchase
	var first_item = shop_inst.current_shop_items[0]
	var initial_gold = GameState.gold
	var cost = first_item["cost"]
	shop_inst._on_buy_item(first_item)
	assert(GameState.gold == initial_gold - cost, "Gold should be deducted after purchase")
	assert(first_item["sold_out"] == true, "Item should be marked as sold out")
	print("✓ Item purchase and gold deduction verified.")

	# Test Reroll
	#
	# **刷新前必须显式把金币补足。** 这一段测的是"刷新会扣费、而且同一次进店内
	# 逐次涨价", 不是"钱够不够"。原来它直接沿用买完东西剩下的余额, 而货架是随机
	# 抽的 —— 抽到贵的 items[0] 之后余额就可能低于刷新费, 于是
	# _on_reroll_pressed() 走"金币不足"那条分支**直接 return 且不扣钱**,
	# 下面的断言必然不成立。
	#
	# 而它的表现不是一条 [FAIL], 是**整个进程挂住**: GDScript 的 assert 在
	# headless debug 构建里失败会停下来等调试器, 而这里没有调试器。实测 12 次
	# 独立运行挂 1 次 (约 8%), 在 run_tests.ps1 里就是一条 TIMEOUT ——
	# 这个文件正是 CLAUDE.md 里"断言坏了被误读成超时"那段说的那个文件, 而它
	# 自己又踩了同一个坑一次。
	GameState.gold = shop_inst.reroll_cost + 500

	# 报价必须在**调用之前**读下来: 刷新费用现在会在同一次进店内递增
	# (REROLL_BASE + REROLL_STEP * n, 见 shop_dialog.gd), 所以调用之后的
	# shop_inst.reroll_cost 已经是下一次的价, 不是刚扣掉的那一笔。
	var old_gold = GameState.gold
	var paid = shop_inst.reroll_cost
	shop_inst._on_reroll_pressed()

	# 这两条**故意不用 assert**。它们守的是一段依赖商店随机内容的行为, 一旦
	# 再出问题, 显式 quit(1) 会给出一条带数字的 [FAIL]; 用 assert 的话只会得到
	# 一个没有任何信息的挂起, 而"挂起"这个信号在批量跑里最容易被当成机器慢。
	# 本文件其余的 assert 守的都是确定性的数值表, 失败即必然, 不在此列。
	if GameState.gold != old_gold - paid:
		print("[FAIL] 刷新没有扣费: 刷新前 %d, 报价 %d, 刷新后 %d" % [old_gold, paid, GameState.gold])
		quit(1)
		return
	if shop_inst.reroll_cost <= paid:
		print("[FAIL] 刷新费用没有在同一次进店内递增: 这次 %d, 下次 %d" % [paid, shop_inst.reroll_cost])
		quit(1)
		return
	print("✓ Shop inventory reroll verified (paid %d, next %d)." % [paid, shop_inst.reroll_cost])

	print("\n🎉 ALL SHOP SYSTEM & ATTACK SPEED TESTS PASSED SUCCESSFULLY! 🎉\n")
	quit(0)
