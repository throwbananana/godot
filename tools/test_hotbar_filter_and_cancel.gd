extends SceneTree

# Verifies:
#   1. The hotbar only shows slots for structures actually in stock (not all
#      11 regardless of ownership), and a slot appears/disappears live as
#      stock crosses 0.
#   2. Q/E cycling only steps through in-stock structures, and refuses to
#      select (or silently no-ops toward) a zero-stock type.
#   3. select_structure() rejects picking a zero-stock structure directly
#      (covers the quick number-key shortcuts).
#   4. The ESC/pause conflict is gone: builder_controller.gd's cancel
#      binding no longer references KEY_ESCAPE at all (R is now the sole
#      dedicated cancel key), so pressing ESC can't both cancel a selection
#      AND toggle the pause menu on the same keypress.

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING HOTBAR FILTER & CANCEL KEY TEST  <<<")
	print("==================================================")

	_test_hotbar_only_shows_owned_structures()
	_test_hotbar_slot_appears_and_disappears_with_stock()
	_test_cycle_only_visits_in_stock_structures()
	_test_select_structure_rejects_zero_stock()
	_test_builder_script_no_longer_binds_escape()

	print("\n>>> ALL HOTBAR FILTER & CANCEL KEY CHECKS PASSED! <<<")
	quit(0)

func _boot_main():
	GameState.reset_campaign(1)
	var main_scene = load("res://scenes/main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	current_scene = main_node
	return main_node

func _test_hotbar_only_shows_owned_structures() -> void:
	print("\n[STEP] Hotbar only renders slots for structures with stock > 0...")
	var main_node = _boot_main()
	GameState.add_structure_stock("turret", 1)
	GameState.add_structure_stock("landmine", 3)
	# main.gd's _ready() already built hud_hotbar before this stock was
	# granted -- rebuild explicitly, same call builder_controller.gd makes
	# after a purchase/placement changes stock.
	UIThemeHelper.update_hotbar_stock(main_node.hud_hotbar)

	var hbox = main_node.hud_hotbar.get_node("SlotContainer")
	var shown_ids = []
	for slot in hbox.get_children():
		if slot.has_meta("structure_id"):
			shown_ids.append(slot.get_meta("structure_id"))

	assert(shown_ids.size() == 2, "expected exactly 2 owned structures shown, got %d (%s)" % [shown_ids.size(), shown_ids])
	assert("turret" in shown_ids and "landmine" in shown_ids, "expected turret and landmine slots, got %s" % [shown_ids])
	assert(not ("wind_blower" in shown_ids), "wind_blower has 0 stock, should not appear")

	main_node.queue_free()
	print("  [PASS] Only owned structures (turret, landmine) appear in the hotbar.")

func _test_hotbar_slot_appears_and_disappears_with_stock() -> void:
	print("\n[STEP] A slot disappears when its stock hits 0, appears when stock is granted...")
	var main_node = _boot_main()
	var hbox = main_node.hud_hotbar.get_node("SlotContainer")

	# Fresh campaign: nothing owned, hotbar should already be empty.
	assert(hbox.get_child_count() == 0, "fresh campaign should render an empty hotbar, got %d slots" % hbox.get_child_count())

	GameState.add_structure_stock("oil_barrel", 1)
	UIThemeHelper.update_hotbar_stock(main_node.hud_hotbar)
	assert(hbox.get_child_count() == 1, "granting 1 oil_barrel should add exactly 1 slot")

	GameState.consume_structure_stock("oil_barrel")
	UIThemeHelper.update_hotbar_stock(main_node.hud_hotbar)
	assert(hbox.get_child_count() == 0, "consuming the last oil_barrel should remove its slot")

	main_node.queue_free()
	print("  [PASS] Hotbar slots track stock live: appear at 1, vanish at 0.")

func _test_cycle_only_visits_in_stock_structures() -> void:
	print("\n[STEP] cycle_next()/cycle_prev() only step through in-stock structures...")
	var main_node = _boot_main()
	GameState.add_structure_stock("turret", 1)
	GameState.add_structure_stock("landmine", 1)
	var builder = main_node.builder_ctrl

	builder.select_structure(BuilderController.StructureType.NONE, 1)
	builder.cycle_next(1)
	var first = builder.selection_by_pid[1]
	assert(first == BuilderController.StructureType.TURRET or first == BuilderController.StructureType.LANDMINE, "first cycle should land on an owned structure, got %s" % first)

	builder.cycle_next(1)
	var second = builder.selection_by_pid[1]
	assert(second != first, "second cycle_next() should move to the other owned structure")
	assert(second == BuilderController.StructureType.TURRET or second == BuilderController.StructureType.LANDMINE, "second cycle should still be an owned structure, got %s" % second)

	builder.cycle_next(1) # should wrap back to `first`
	assert(builder.selection_by_pid[1] == first, "cycling past the last owned item should wrap back to the first, not visit an unowned one")

	main_node.queue_free()
	print("  [PASS] Cycling only ever visits owned structures and wraps correctly.")

func _test_select_structure_rejects_zero_stock() -> void:
	print("\n[STEP] select_structure() refuses to select a structure with 0 stock...")
	var main_node = _boot_main() # nothing owned
	var builder = main_node.builder_ctrl

	builder.select_structure(BuilderController.StructureType.TURRET, 1)
	assert(builder.selection_by_pid[1] == BuilderController.StructureType.NONE, "selecting a zero-stock structure should be rejected, stayed at %s" % builder.selection_by_pid[1])

	main_node.queue_free()
	print("  [PASS] Zero-stock structures can't be selected (covers the quick number-key shortcuts too).")

func _test_builder_script_no_longer_binds_escape() -> void:
	print("\n[STEP] builder_controller.gd's cancel binding no longer touches KEY_ESCAPE...")
	# Static source check: main.gd's pause toggle already reacts to
	# "ui_cancel" (Godot's default ESC binding). builder_controller.gd used
	# to ALSO bind KEY_ESCAPE to cancel the current selection, so a single
	# ESC press fired both handlers -- cancelling the selection AND opening
	# the pause menu at once. Confirm the source no longer references
	# KEY_ESCAPE anywhere.
	var src = FileAccess.get_file_as_string("res://scripts/builder_controller.gd")
	assert(not src.contains("KEY_ESCAPE"), "builder_controller.gd should no longer bind KEY_ESCAPE (conflicts with main.gd's pause toggle on the same keypress)")
	assert(src.contains("KEY_R"), "KEY_R should remain as the dedicated P1 cancel key")
	print("  [PASS] KEY_ESCAPE is gone from builder_controller.gd; R remains the sole P1 cancel key.")
