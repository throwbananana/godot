extends SceneTree

# Verifies the redesigned "shop-gated" builder economy: structures used to
# cost battle gold at the moment you placed them (builder_controller.gd's
# `costs` dict); they're now shop-only stock (GameState.structure_inventory)
# -- buy N in shop_dialog.gd's always-shown Building Supplies section, each
# in-battle placement consumes one unit and does NOT touch gold at all.

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING SHOP-GATED BUILDINGS TEST  <<<")
	print("==================================================")

	_test_gamestate_inventory_primitives()
	_test_save_load_roundtrip()
	_test_shop_purchase_adds_stock_and_spends_gold()
	_test_shop_building_items_always_present()
	_test_builder_consumes_stock_not_gold()
	_test_builder_blocks_placement_with_no_stock()

	print("\n>>> ALL SHOP-GATED BUILDINGS CHECKS PASSED! <<<")
	quit(0)

func _test_gamestate_inventory_primitives() -> void:
	print("\n[STEP] GameState structure_inventory add/consume/get...")
	GameState.reset_campaign(1)
	assert(GameState.get_structure_stock("turret") == 0, "fresh campaign should start with 0 stock")

	GameState.add_structure_stock("turret", 2)
	assert(GameState.get_structure_stock("turret") == 2, "add_structure_stock should accumulate")

	assert(GameState.consume_structure_stock("turret") == true, "consuming with stock available should succeed")
	assert(GameState.get_structure_stock("turret") == 1, "consume should decrement by 1")

	GameState.consume_structure_stock("turret")
	assert(GameState.get_structure_stock("turret") == 0, "should be able to consume down to 0")
	assert(GameState.consume_structure_stock("turret") == false, "consuming with 0 stock should fail, not go negative")
	assert(GameState.get_structure_stock("turret") == 0, "failed consume should not change stock")

	print("  [PASS] add/consume/get_structure_stock behave correctly, including the zero-stock guard.")

func _test_save_load_roundtrip() -> void:
	print("\n[STEP] structure_inventory survives a save/load roundtrip...")
	GameState.reset_campaign(1)
	GameState.add_structure_stock("turret", 3)
	GameState.add_structure_stock("landmine", 1)
	GameState.save_campaign()

	GameState.structure_inventory = {}
	var ok = GameState.load_campaign()
	assert(ok, "load_campaign() should succeed")
	assert(GameState.get_structure_stock("turret") == 3, "turret stock should round-trip as 3")
	assert(GameState.get_structure_stock("landmine") == 1, "landmine stock should round-trip as 1")

	print("  [PASS] structure_inventory round-trips through save/load.")

func _test_shop_purchase_adds_stock_and_spends_gold() -> void:
	print("\n[STEP] Buying a building in the shop adds stock and spends gold...")
	GameState.reset_campaign(1)
	GameState.gold = 500

	var shop_scene = load("res://scenes/shop_dialog.tscn")
	var shop = shop_scene.instantiate()
	root.add_child(shop)

	var gold_before = GameState.gold
	var turret_item = null
	for b in shop.BUILDING_ITEMS:
		if b["id"] == "turret":
			turret_item = b
			break
	assert(turret_item != null, "sanity: turret should be one of BUILDING_ITEMS")

	shop._on_buy_item(turret_item.duplicate())
	assert(GameState.get_structure_stock("turret") == 1, "buying a turret should add 1 to stock")
	assert(GameState.gold == gold_before - int(turret_item["cost"]), "buying should spend the listed cost in gold")

	shop.queue_free()
	print("  [PASS] Shop purchase adds structure stock and spends the correct amount of gold.")

func _test_shop_building_items_always_present() -> void:
	print("\n[STEP] All 11 building items are present every shop visit (not shuffled/limited)...")
	GameState.reset_campaign(1)
	var shop_scene = load("res://scenes/shop_dialog.tscn")
	var shop = shop_scene.instantiate()
	root.add_child(shop)

	shop.setup_shop()
	var build_ids_present = {}
	for item in shop.current_shop_items:
		if item.get("category", "") == "BUILD":
			build_ids_present[item["id"]] = true
	assert(build_ids_present.size() == shop.BUILDING_ITEMS.size(), "expected all %d building items present, got %d" % [shop.BUILDING_ITEMS.size(), build_ids_present.size()])

	shop.queue_free()
	print("  [PASS] All building items appear in current_shop_items regardless of the random-6 stat rotation.")

func _boot_main():
	GameState.reset_campaign(1)
	var main_scene = load("res://scenes/main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	current_scene = main_node
	return main_node

func _test_builder_consumes_stock_not_gold() -> void:
	print("\n[STEP] Placing a structure in battle consumes stock and leaves gold untouched...")
	# _boot_main() calls GameState.reset_campaign(), which clears
	# structure_inventory -- stock must be granted AFTER booting, not before.
	var main_node = _boot_main()
	GameState.add_structure_stock("fortified_wall", 2)
	var builder = main_node.builder_ctrl
	assert(builder != null, "sanity: main.tscn should have a BuilderController")

	var gold_before = main_node.rpg_mgr.gold
	builder.select_structure(BuilderController.StructureType.FORTIFIED_WALL, 1)
	# Placement position is derived from the player's facing position, which
	# should be open ground right after spawn on a fresh battle.
	builder._try_place_current(1)

	assert(GameState.get_structure_stock("fortified_wall") == 1, "placing should consume one unit of stock, got %d" % GameState.get_structure_stock("fortified_wall"))
	assert(main_node.rpg_mgr.gold == gold_before, "placing a structure should NOT touch gold anymore, got delta %d" % (main_node.rpg_mgr.gold - gold_before))

	main_node.queue_free()
	print("  [PASS] Battle placement consumes inventory stock, gold is untouched.")

func _test_builder_blocks_placement_with_no_stock() -> void:
	print("\n[STEP] Placement is blocked (and gold untouched) with zero stock...")
	GameState.reset_campaign(1) # 0 stock of everything
	var main_node = _boot_main()
	var builder = main_node.builder_ctrl

	var gold_before = main_node.rpg_mgr.gold
	builder.select_structure(BuilderController.StructureType.TURRET, 1)
	builder._try_place_current(1)

	assert(GameState.get_structure_stock("turret") == 0, "should remain at 0 stock, nothing to consume")
	assert(main_node.rpg_mgr.gold == gold_before, "a blocked placement must not spend gold either")

	main_node.queue_free()
	print("  [PASS] Zero-stock placement is correctly blocked without side effects.")
