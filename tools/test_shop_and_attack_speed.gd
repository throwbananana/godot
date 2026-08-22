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
	# 报价必须在**调用之前**读下来: 刷新费用现在会在同一次进店内递增
	# (REROLL_BASE + REROLL_STEP * n, 见 shop_dialog.gd), 所以调用之后的
	# shop_inst.reroll_cost 已经是下一次的价, 不是刚扣掉的那一笔。
	var old_gold = GameState.gold
	var paid = shop_inst.reroll_cost
	shop_inst._on_reroll_pressed()
	assert(GameState.gold == old_gold - paid, "Reroll cost should be deducted")
	assert(shop_inst.reroll_cost > paid, "Reroll cost should escalate within a visit")
	print("✓ Shop inventory reroll verified (paid %d, next %d)." % [paid, shop_inst.reroll_cost])

	print("\n🎉 ALL SHOP SYSTEM & ATTACK SPEED TESTS PASSED SUCCESSFULLY! 🎉\n")
	quit(0)
