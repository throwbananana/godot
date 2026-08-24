extends SceneTree

const EnemyTank = preload("res://scripts/enemy.gd")
const EnemyShieldTower = preload("res://scripts/buildings/enemy_shield_tower.gd")
const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING ENEMY SHIELD TOWER & BUFF TESTS <<<")
	print("==================================================")

	_test_tower_assets_and_initialization()
	_test_shield_protection_and_dispell_mechanic()
	_test_encyclopedia_integration()

	print("\n>>> ALL ENEMY SHIELD TOWER TESTS PASSED! <<<")
	quit(0)

func _test_tower_assets_and_initialization() -> void:
	print("\n[STEP 1] Testing Enemy Shield Tower sprite assets & scene...")

	# Check 4 frames
	for f in range(4):
		var tex = TextureHelper.get_tex("res://assets/sprites/buildings/enemy_shield_tower_f%d.png" % f)
		assert(tex != null, "Tower frame %d must exist" % f)

	var primary = TextureHelper.get_tex("res://assets/sprites/buildings/enemy_shield_tower.png")
	assert(primary != null, "Tower primary texture must exist")

	var tower_scene = load("res://scenes/buildings/enemy_shield_tower.tscn")
	assert(tower_scene != null, "EnemyShieldTower scene must exist")

	var tower = tower_scene.instantiate()
	root.add_child(tower)

	assert(tower.is_in_group("enemy_building"), "Tower must be in enemy_building group")
	assert(tower.max_hp >= 8, "Tower max HP should be >= 8, got %d" % tower.max_hp)
	assert(tower.shield_radius >= 150.0, "Tower shield radius should be >= 150.0")

	print("  [PASS] Enemy Shield Tower loaded with HP=%d, Radius=%.1f" % [tower.max_hp, tower.shield_radius])
	tower.queue_free()

func _test_shield_protection_and_dispell_mechanic() -> void:
	print("\n[STEP 2] Testing Enemy Shield Aura protection & destruction dispell...")

	var arena = Node2D.new()
	root.add_child(arena)

	# 1. Spawn Enemy Shield Tower at (200, 200)
	var tower_scene = load("res://scenes/buildings/enemy_shield_tower.tscn")
	var tower = tower_scene.instantiate()
	tower.position = Vector2(200.0, 200.0)
	arena.add_child(tower)

	# 2. Spawn Enemy Tank inside range at (250, 200) (dist = 50px < 180px)
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	enemy.enemy_type = EnemyTank.EnemyType.BASIC
	enemy.position = Vector2(250.0, 200.0)
	arena.add_child(enemy)

	# Manually trigger area enter to simulate physics overlap in headless mode
	tower._on_shield_area_entered(enemy)

	assert(enemy.is_shielded() == true, "Enemy inside tower radius MUST be shielded!")
	assert(enemy.shield_sources.has(tower), "Enemy must have tower in shield_sources")
	print("  [PASS] Enemy gained shield from tower successfully (is_shielded=true).")

	# 3. Test invulnerability under shield
	var initial_hp = enemy.health
	enemy.take_damage(2)
	assert(enemy.health == initial_hp, "Shielded enemy MUST NOT take damage! HP was %d, expected %d" % [enemy.health, initial_hp])
	print("  [PASS] Shield absorbed 2 damage completely (HP remained %d)." % enemy.health)

	# 4. Move enemy outside range and exit area
	enemy.position = Vector2(500.0, 500.0)
	tower._on_shield_area_exited(enemy)

	assert(enemy.is_shielded() == false, "Enemy outside radius MUST NOT be shielded!")
	print("  [PASS] Enemy exited shield radius (is_shielded=false).")

	# Enemy now takes damage normally
	enemy.take_damage(1)
	assert(enemy.health == initial_hp - 1, "Unshielded enemy MUST take damage normally! HP was %d" % enemy.health)
	print("  [PASS] Unshielded enemy took 1 damage normally (HP reduced to %d)." % enemy.health)

	# 5. Move enemy back in range
	enemy.position = Vector2(240.0, 200.0)
	tower._on_shield_area_entered(enemy)
	assert(enemy.is_shielded() == true, "Enemy back in range MUST regain shield!")

	# 6. Destroy the Enemy Shield Tower -> buff MUST be cancelled immediately!
	var destroyed_signal_fired = false
	tower.tower_destroyed.connect(func(): destroyed_signal_fired = true)
	tower.take_damage(999)

	assert(destroyed_signal_fired == true, "Tower must emit tower_destroyed signal")
	assert(enemy.is_shielded() == false, "Enemy shield MUST be cancelled when tower is destroyed!")
	assert(enemy.shield_sources.is_empty(), "Enemy shield_sources MUST be empty after tower destruction")
	print("  [PASS] Tower destroyed -> all enemy shields instantly dispelled/cancelled!")

	arena.queue_free()

func _test_encyclopedia_integration() -> void:
	print("\n[STEP 3] Testing Compendium entry for Enemy Shield Tower...")

	var blds = EncyclopediaData.get_entries_by_category("BUILDINGS")
	var found_tower = false

	for b in blds:
		if b.get("id") == "bld_enemy_shield_tower":
			found_tower = true
			assert(TextureHelper.get_tex(b.get("icon")) != null, "Tower icon must be loadable")
			assert(not b.get("desc", "").is_empty(), "Tower desc must exist")
			assert(not b.get("tactics", "").is_empty(), "Tower tactics must exist")

	assert(found_tower, "Compendium MUST contain bld_enemy_shield_tower entry")
	print("  [PASS] Enemy Shield Tower verified in Compendium BUILDINGS category.")
