extends SceneTree

const BaseEagleScene = preload("res://scenes/base_eagle.tscn")
const BulletScene = preload("res://scenes/bullet.tscn")
const PowerUpScene = preload("res://scenes/power_up.tscn")
const TimedBombScene = preload("res://scenes/timed_bomb.tscn")
const GameState = preload("res://scripts/game_state.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print("TESTING FRIENDLY IFF FLAG AUTOMATED TESTS")
	print("==================================================")

	var root_node = root
	var test_host = Node2D.new()
	root_node.add_child(test_host)

	# ----------------------------------------------------
	# Test 1: BaseEagle IFF Visuals and Flag Banner Setup
	# ----------------------------------------------------
	print("\n[Test 1] Testing BaseEagle IFF state and visual banner...")
	var base: BaseEagle = BaseEagleScene.instantiate()
	test_host.add_child(base)
	base.global_position = Vector2(200, 200)

	assert(base.is_iff_active == false, "Initial IFF state should be false")
	assert(base.iff_flag_sprite == null or not base.iff_flag_sprite.visible, "Flag sprite should not be visible initially")

	base.set_iff_active(true)
	assert(base.is_iff_active == true, "IFF state should now be true")
	assert(base.iff_flag_sprite != null and base.iff_flag_sprite.visible == true, "Flag sprite should be visible")
	assert(base.iff_flag_sprite.texture != null, "Flag sprite should have a texture")
	assert(base.aura_light != null, "Aura light should be present")
	assert(base.aura_light.color.g > 0.9, "Aura light should be emerald green when IFF active")

	base.set_iff_active(false)
	assert(base.is_iff_active == false, "IFF state should be false after reset")
	assert(base.iff_flag_sprite.visible == false, "Flag sprite should be hidden")
	print("OK Test 1 Passed: BaseEagle IFF visuals toggled successfully.")

	# ----------------------------------------------------
	# Test 2: Friendly fire without IFF flag damages base
	# ----------------------------------------------------
	print("\n[Test 2] Testing friendly fire without IFF flag...")
	GameState.has_iff_flag = false
	var player_bullet: Bullet = BulletScene.instantiate()
	player_bullet.shooter_type = "player"
	player_bullet.direction = Vector2.DOWN
	test_host.add_child(player_bullet)
	player_bullet.global_position = base.global_position

	player_bullet._on_area_entered(base)
	assert(base.is_destroyed == true, "Base should be destroyed by friendly fire when IFF flag is not active")
	print("OK Test 2 Passed: Friendly fire damages base when IFF flag is inactive.")
	base.queue_free()
	player_bullet.queue_free()

	# ----------------------------------------------------
	# Test 3: Friendly fire WITH IFF flag does NOT damage base
	# ----------------------------------------------------
	print("\n[Test 3] Testing friendly fire WITH IFF flag...")
	var base_protected: BaseEagle = BaseEagleScene.instantiate()
	test_host.add_child(base_protected)
	base_protected.global_position = Vector2(300, 300)
	base_protected.set_iff_active(true)

	var friendly_bullet: Bullet = BulletScene.instantiate()
	friendly_bullet.shooter_type = "player"
	friendly_bullet.direction = Vector2.DOWN
	test_host.add_child(friendly_bullet)
	friendly_bullet.global_position = base_protected.global_position

	friendly_bullet._on_area_entered(base_protected)
	assert(base_protected.is_destroyed == false, "Base should NOT be destroyed when IFF is active!")
	assert(friendly_bullet.is_destroyed == false, "Friendly bullet should continue flying unharmed through base!")
	print("OK Test 3 Passed: Player bullet safely passes through base when IFF flag is active.")
	friendly_bullet.queue_free()

	# ----------------------------------------------------
	# Test 4: Enemy fire STILL damages base even if IFF flag is active
	# ----------------------------------------------------
	print("\n[Test 4] Testing enemy fire WITH IFF flag active...")
	var enemy_bullet: Bullet = BulletScene.instantiate()
	enemy_bullet.shooter_type = "enemy"
	enemy_bullet.direction = Vector2.DOWN
	test_host.add_child(enemy_bullet)
	enemy_bullet.global_position = base_protected.global_position

	enemy_bullet._on_area_entered(base_protected)
	assert(base_protected.is_destroyed == true, "Enemy bullet must destroy base regardless of friendly IFF flag!")
	print("OK Test 4 Passed: Enemy fire damages base properly.")
	base_protected.queue_free()
	enemy_bullet.queue_free()

	# ----------------------------------------------------
	# Test 5: Timed Bomb Friendly IFF Protection
	# ----------------------------------------------------
	print("\n[Test 5] Testing Timed Bomb friendly fire protection...")
	var base_bomb_test: BaseEagle = BaseEagleScene.instantiate()
	test_host.add_child(base_bomb_test)
	base_bomb_test.global_position = Vector2(400, 400)
	base_bomb_test.set_iff_active(true)

	var friendly_bomb: TimedBomb = TimedBombScene.instantiate()
	friendly_bomb.team = "player"
	friendly_bomb.countdown = 0.0
	friendly_bomb.blast_range = 3
	friendly_bomb.damage = 5
	test_host.add_child(friendly_bomb)
	friendly_bomb.global_position = Vector2(400, 416)

	friendly_bomb.detonate()
	assert(base_bomb_test.is_destroyed == false, "Player timed bomb must NOT harm base when IFF is active!")
	print("OK Test 5 Passed: Friendly timed bomb explosion spared base.")
	base_bomb_test.queue_free()
	friendly_bomb.queue_free()

	# ----------------------------------------------------
	# Test 6: PowerUp Item setup and texture
	# ----------------------------------------------------
	print("\n[Test 6] Testing PowerUp IFF_FLAG item setup...")
	var powerup: PowerUp = PowerUpScene.instantiate()
	test_host.add_child(powerup)
	powerup.setup(PowerUp.Type.IFF_FLAG)
	assert(powerup.power_up_type == PowerUp.Type.IFF_FLAG, "PowerUp type should be IFF_FLAG")
	assert(powerup.sprite != null and powerup.sprite.texture != null, "PowerUp sprite should have texture")
	assert(powerup.sprite.texture.get_width() > 0, "PowerUp texture should be valid and loaded")
	print("OK Test 6 Passed: PowerUp IFF_FLAG item instantiated and loaded texture successfully.")
	powerup.queue_free()

	# ----------------------------------------------------
	# Test 7: Main trigger_iff_flag and timer expiration
	# ----------------------------------------------------
	print("\n[Test 7] Testing Main trigger_iff_flag and timer...")
	var MainScene = load("res://scenes/main.tscn")
	var main_instance = MainScene.instantiate()
	root_node.add_child(main_instance)
	assert(main_instance.is_iff_flag_active() == false, "Main initial iff_flag should be false")

	main_instance.trigger_iff_flag(10.0)
	assert(main_instance.is_iff_flag_active() == true, "Main iff_flag should be active after trigger")
	assert(main_instance.iff_flag_timer == 10.0, "Main timer should be 10.0")

	# Advance time past expiration
	main_instance._process(12.0)
	assert(main_instance.is_iff_flag_active() == false, "Main iff_flag should expire after timer runs out")
	print("OK Test 7 Passed: Main trigger_iff_flag and countdown work properly.")
	main_instance.queue_free()

	test_host.queue_free()
	print("\n==================================================")
	print("🎉 ALL 7 FRIENDLY IFF FLAG TESTS PASSED CLEANLY! 🎉")
	print("==================================================")
	quit(0)
