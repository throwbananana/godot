extends SceneTree

const EnemyTank = preload("res://scripts/enemy.gd")
const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING SPLITTER TANK & MINI SPLIT TESTS <<<")
	print("==================================================")

	_test_splitter_frames_and_stats()
	_test_splitter_death_mechanic()
	_test_encyclopedia_integration()

	print("\n>>> ALL SPLITTER TANK TESTS PASSED! <<<")
	quit(0)

func _test_splitter_frames_and_stats() -> void:
	print("\n[STEP 1] Testing Splitter & Mini Tank sprite frames & stats...")

	# Check 6 frames for enemy_splitter
	for f in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/tanks/enemy_splitter_f%d.png" % f)
		assert(tex != null, "Splitter frame %d must exist and be loadable" % f)

	# Check 6 frames for enemy_split_mini
	for f in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/tanks/enemy_split_mini_f%d.png" % f)
		assert(tex != null, "Mini split frame %d must exist and be loadable" % f)

	# Instantiate Splitter Tank
	var enemy_scene = load("res://scenes/enemy.tscn")
	assert(enemy_scene != null, "Enemy scene must exist")

	var splitter = enemy_scene.instantiate()
	splitter.enemy_type = EnemyTank.EnemyType.SPLITTER
	root.add_child(splitter)

	assert(splitter.max_health >= 7, "Splitter base health should be >= 7, got %d" % splitter.max_health)
	assert(splitter.score_value >= 1000, "Splitter score value should be >= 1000")
	assert(splitter.sprite.scale.x >= 0.22, "Splitter sprite scale should be large (>= 0.22)")
	print("  [PASS] Splitter tank initialized with HP=%d, Score=%d, Scale=%s" % [splitter.max_health, splitter.score_value, str(splitter.sprite.scale)])

	# Instantiate Mini Split Tank
	var mini = enemy_scene.instantiate()
	mini.enemy_type = EnemyTank.EnemyType.SPLIT_MINI
	root.add_child(mini)

	assert(mini.max_health == 1, "Mini split health should be 1")
	assert(mini.speed >= 120.0, "Mini split speed should be fast (>= 120.0)")
	assert(mini.sprite.scale.x <= 0.16, "Mini split sprite scale should be compact (<= 0.16)")
	print("  [PASS] Mini split tank initialized with HP=%d, Speed=%f, Scale=%s" % [mini.max_health, mini.speed, str(mini.sprite.scale)])

	splitter.queue_free()
	mini.queue_free()

func _test_splitter_death_mechanic() -> void:
	print("\n[STEP 2] Testing Splitter destruction & 4-unit splitting mechanic...")

	var arena = Node2D.new()
	root.add_child(arena)

	var enemy_scene = load("res://scenes/enemy.tscn")
	var splitter = enemy_scene.instantiate()
	splitter.enemy_type = EnemyTank.EnemyType.SPLITTER
	splitter.global_position = Vector2(300.0, 300.0)
	arena.add_child(splitter)

	# Count initial enemies in arena
	var initial_enemies = 0
	for child in arena.get_children():
		if child is EnemyTank:
			initial_enemies += 1
	assert(initial_enemies == 1, "Arena should have 1 splitter initially")

	# Destroy splitter
	splitter.take_damage(999)

	# Verify 4 mini tanks spawned as children of arena
	var spawned_minis: Array[EnemyTank] = []
	for child in arena.get_children():
		if child is EnemyTank and child.enemy_type == EnemyTank.EnemyType.SPLIT_MINI:
			spawned_minis.append(child)

	assert(spawned_minis.size() == 4, "Splitter must split into exactly 4 mini tanks, got %d" % spawned_minis.size())
	print("  [PASS] Successfully spawned 4 mini tanks on Splitter death:")
	for i in range(spawned_minis.size()):
		var m = spawned_minis[i]
		var dist = m.global_position.distance_to(Vector2(300.0, 300.0))
		print("    - Mini #%d at pos %s (dist=%.1f px from epicenter, dir=%s)" % [i+1, str(m.global_position), dist, str(m.facing_direction)])
		assert(dist > 15.0 and dist < 60.0, "Mini tank must be offset around death epicenter")

	arena.queue_free()

func _test_encyclopedia_integration() -> void:
	print("\n[STEP 3] Testing Compendium entries for Splitter & Mini Split...")

	var tanks = EncyclopediaData.get_entries_by_category("TANKS")
	var found_splitter = false
	var found_mini = false

	for t in tanks:
		if t.get("id") == "enemy_splitter":
			found_splitter = true
			assert(TextureHelper.get_tex(t.get("icon")) != null, "Splitter icon must be valid")
		elif t.get("id") == "enemy_split_mini":
			found_mini = true
			assert(TextureHelper.get_tex(t.get("icon")) != null, "Mini split icon must be valid")

	assert(found_splitter, "Encyclopedia must have enemy_splitter entry")
	assert(found_mini, "Encyclopedia must have enemy_split_mini entry")
	print("  [PASS] Both Splitter and Mini Split Tank verified in Compendium.")
