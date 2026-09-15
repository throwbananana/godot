extends SceneTree

const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")
const EncyclopediaDialog = preload("res://scripts/encyclopedia_dialog.gd")
const TitleScreen = preload("res://scripts/title_screen.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING ENCYCLOPEDIA & COMPENDIUM TESTS <<<")
	print("==================================================")

	_test_encyclopedia_data_integrity()
	_test_encyclopedia_dialog_ui()
	_test_title_screen_integration()

	print("\n>>> ALL ENCYCLOPEDIA & COMPENDIUM CHECKS PASSED! <<<")
	quit(0)

func _test_encyclopedia_data_integrity() -> void:
	print("\n[STEP 1] Testing EncyclopediaData integrity...")

	var categories = ["UPGRADES", "TANKS", "ITEMS", "BUILDINGS", "TERRAIN"]
	for cat in categories:
		var entries = EncyclopediaData.get_entries_by_category(cat)
		assert(entries.size() > 0, "Category %s must have entries!" % cat)
		print("  [PASS] Category %s has %d registered entries." % [cat, entries.size()])

	var all_entries = EncyclopediaData.ENTRIES
	assert(all_entries.size() >= 50, "Total entries should be >= 50, got %d" % all_entries.size())

	for entry in all_entries:
		var id = entry.get("id", "")
		var name = entry.get("name", "")
		var icon = entry.get("icon", "")
		var desc = entry.get("desc", "")
		var tactics = entry.get("tactics", "")
		var stats: Dictionary = entry.get("stats", {})

		assert(not id.is_empty(), "Entry must have id")
		assert(not name.is_empty(), "Entry %s must have name" % id)
		assert(not desc.is_empty(), "Entry %s must have desc" % id)
		assert(not tactics.is_empty(), "Entry %s must have tactics" % id)
		assert(stats.size() > 0, "Entry %s must have stats" % id)

		if not icon.is_empty():
			var tex = TextureHelper.get_tex(icon)
			assert(tex != null, "Icon %s for entry %s must be loadable" % [icon, id])

	print("  [PASS] All %d encyclopedia entries validated with valid assets & descriptions." % all_entries.size())

func _test_encyclopedia_dialog_ui() -> void:
	print("\n[STEP 2] Testing EncyclopediaDialog UI component...")

	var dialog_scene = load("res://scenes/encyclopedia_dialog.tscn")
	assert(dialog_scene != null, "EncyclopediaDialog scene must exist")

	var dialog = dialog_scene.instantiate()
	root.add_child(dialog)

	# Test opening dialog
	dialog.open_dialog()
	assert(dialog.visible == true, "Dialog must be visible on open")

	# Test switching tabs
	var tabs = ["UPGRADES", "ITEMS", "BUILDINGS", "TERRAIN", "TANKS"]
	for cat in tabs:
		dialog.switch_category(cat)
		assert(dialog.current_category == cat, "Current category should be %s" % cat)
		assert(dialog.active_item_buttons.size() > 0, "Active item buttons should exist for %s" % cat)
		assert(not dialog.detail_name.text.is_empty(), "Detail name must be populated for %s" % cat)
		assert(not dialog.desc_text.text.is_empty(), "Desc text must be populated for %s" % cat)
		assert(not dialog.tactics_text.text.is_empty(), "Tactics text must be populated for %s" % cat)
		print("  [PASS] Tab switch to %s verified." % cat)

	# Test close signal
	var closed_emitted = false
	dialog.closed.connect(func(): closed_emitted = true)
	dialog.close_dialog()
	assert(dialog.visible == false, "Dialog must be hidden on close")
	assert(closed_emitted == true, "Closed signal must be emitted")

	dialog.queue_free()
	print("  [PASS] EncyclopediaDialog lifecycle, tabs, and detail rendering verified.")

func _test_title_screen_integration() -> void:
	print("\n[STEP 3] Testing TitleScreen integration...")

	var title_scene = load("res://scenes/title_screen.tscn")
	assert(title_scene != null, "TitleScreen scene must exist")

	var title = title_scene.instantiate()
	root.add_child(title)

	assert(title.btn_encyclopedia != null, "TitleScreen must have btn_encyclopedia")
	assert(title.encyclopedia_dialog != null, "TitleScreen must have encyclopedia_dialog instance")

	# Test pressing compendium button opens dialog
	title._on_encyclopedia_pressed()
	assert(title.encyclopedia_dialog.visible == true, "Encyclopedia dialog must open when button is clicked")

	# Test closing dialog
	title.encyclopedia_dialog.close_dialog()
	assert(title.encyclopedia_dialog.visible == false, "Encyclopedia dialog must close cleanly")

	title.queue_free()
	print("  [PASS] TitleScreen encyclopedia button integration verified.")
