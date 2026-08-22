extends SceneTree

# Verifies the perk-stacking expansion (GameState.PERK_MAX_STACKS,
# RPGManager.add_perk/get_perk_value) that replaced the old one-shot
# "10 unique perks then nothing but gold_heal" pool -- the pool used to run
# out after ~11 level-ups, well before a (now 15-floor) act finishes.

func _init() -> void:
	print("==================================================")
	print(">>> RUNNING PERK STACKING TEST  <<<")
	print("==================================================")

	_test_stack_cap_and_diminishing_curve()
	_test_stat_getters_scale_with_stacks()
	_test_save_load_roundtrip_dictionary_format()
	_test_save_load_backward_compat_old_array_format()

	print("\n>>> ALL PERK STACKING CHECKS PASSED! <<<")
	quit(0)

func _test_stack_cap_and_diminishing_curve() -> void:
	print("\n[STEP] Stack cap + diminishing curve...")
	var mgr = RPGManager.new()

	# rapid_loader caps at 3 (numeric, stackable)
	assert(mgr.add_perk("rapid_loader", 1) == true, "1st rapid_loader pick should succeed")
	assert(mgr.add_perk("rapid_loader", 1) == true, "2nd rapid_loader pick should succeed")
	assert(mgr.add_perk("rapid_loader", 1) == true, "3rd rapid_loader pick should succeed")
	assert(mgr.add_perk("rapid_loader", 1) == false, "4th rapid_loader pick should be rejected (cap=3)")
	assert(mgr.get_perk_stacks("rapid_loader", 1) == 3, "rapid_loader should be at 3 stacks")

	var val = mgr.get_perk_value("rapid_loader", 0.30, 1)
	var expected = 0.30 * (1.0 + 0.65 + 0.45) # PERK_STACK_CURVE
	assert(absf(val - expected) < 0.001, "get_perk_value should follow the diminishing curve, got %f expected %f" % [val, expected])

	# frost_cleats caps at 1 (binary gate, not stackable)
	assert(mgr.add_perk("frost_cleats", 1) == true, "1st frost_cleats pick should succeed")
	assert(mgr.add_perk("frost_cleats", 1) == false, "2nd frost_cleats pick should be rejected (cap=1)")
	assert(mgr.get_perk_stacks("frost_cleats", 1) == 1, "frost_cleats should be at 1 stack")

	print("  [PASS] Stacks respect per-perk caps; value follows diminishing curve.")

func _test_stat_getters_scale_with_stacks() -> void:
	print("\n[STEP] Stat getters actually reflect stack count...")
	var mgr = RPGManager.new()

	var hp_before = mgr.get_player_max_hp(1)
	mgr.add_perk("titan_plating", 1)
	var hp_after_1 = mgr.get_player_max_hp(1)
	mgr.add_perk("titan_plating", 1)
	var hp_after_2 = mgr.get_player_max_hp(1)
	assert(hp_after_1 > hp_before, "1 stack of titan_plating should raise max HP")
	assert(hp_after_2 > hp_after_1, "2nd stack of titan_plating should raise max HP further")

	var dmg_before = mgr.get_atk_damage(1)
	mgr.add_perk("high_explosive", 1)
	assert(mgr.get_atk_damage(1) > dmg_before, "high_explosive stack should raise atk damage")

	var regen_before = mgr.get_regen_rate(1)
	mgr.add_perk("nano_repair", 1)
	assert(mgr.get_regen_rate(1) > regen_before, "nano_repair stack should raise regen rate")

	# P2 stacks are independent of P1
	mgr.add_perk("titan_plating", 2)
	assert(mgr.get_perk_stacks("titan_plating", 1) == 2, "P1 titan_plating stacks unaffected by P2 pick")
	assert(mgr.get_perk_stacks("titan_plating", 2) == 1, "P2 titan_plating should have its own stack count")

	print("  [PASS] get_player_max_hp/get_atk_damage/get_regen_rate scale with stacks; P1/P2 independent.")

func _test_save_load_roundtrip_dictionary_format() -> void:
	print("\n[STEP] Save/load roundtrip preserves stack counts (new Dictionary format)...")
	GameState.reset_campaign(1)
	GameState.unlocked_perks = {"rapid_loader": 3, "frost_cleats": 1}
	GameState.p2_unlocked_perks = {"nano_repair": 2}
	GameState.save_campaign()

	GameState.unlocked_perks = {}
	GameState.p2_unlocked_perks = {}
	var ok = GameState.load_campaign()
	assert(ok, "load_campaign() should succeed")
	assert(GameState.unlocked_perks.get("rapid_loader", 0) == 3, "rapid_loader stacks should round-trip as 3")
	assert(GameState.unlocked_perks.get("frost_cleats", 0) == 1, "frost_cleats stacks should round-trip as 1")
	assert(GameState.p2_unlocked_perks.get("nano_repair", 0) == 2, "P2 nano_repair stacks should round-trip as 2")

	print("  [PASS] Dictionary-format perk stacks survive a save/load roundtrip.")

func _test_save_load_backward_compat_old_array_format() -> void:
	print("\n[STEP] Loading an old save (Array[String] perk format) doesn't crash...")
	var loaded = GameState._load_perk_dict(["rapid_loader", "frost_cleats", "rapid_loader"])
	assert(loaded.get("rapid_loader", 0) == 1, "old Array format should map each unique id to 1 stack")
	assert(loaded.get("frost_cleats", 0) == 1, "old Array format should map each unique id to 1 stack")
	print("  [PASS] Old Array[String]-format perk saves load as 1-stack-each without crashing.")
