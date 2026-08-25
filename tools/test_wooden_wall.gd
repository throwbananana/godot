extends SceneTree

const WoodenWallScript = preload("res://scripts/buildings/wooden_wall.gd")
const BuilderControllerScript = preload("res://scripts/builder_controller.gd")
const ShopDialogScript = preload("res://scripts/shop_dialog.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING WOODEN WALL (木墙) COMPREHENSIVE TESTS <<<")
	print("==================================================")

	await _test_wooden_wall_directional_push()
	await _test_wooden_wall_physical_contact_push()
	await _test_wooden_wall_crushes_brick_and_damages_enemy()
	await _test_wooden_wall_damage_stages_and_destruction()
	_test_builder_and_shop_and_encyclopedia_integration()

	print("\n>>> ALL WOODEN WALL CHECKS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_wooden_wall_directional_push() -> void:
	print("\n[STEP 1] Wooden Wall responds to directional kinetic impact and shifts 1 cell (48px)...")
	var wall = WoodenWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(240, 240)

	# 1. Hit from left towards right (Vector2.RIGHT)
	var start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.RIGHT)

	var timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	assert(wall.global_position.x == start_pos.x + 48.0, "Wooden Wall should move 48px right, got %f" % wall.global_position.x)
	assert(wall.global_position.y == start_pos.y, "Wooden Wall Y position should remain unchanged")

	# 2. Hit from top towards bottom (Vector2.DOWN)
	start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.DOWN)

	timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	assert(wall.global_position.y == start_pos.y + 48.0, "Wooden Wall should move 48px down, got %f" % wall.global_position.y)
	assert(wall.global_position.x == start_pos.x, "Wooden Wall X position should remain unchanged")

	wall.queue_free()
	print("  [PASS] Wooden Wall correctly executes kinetic slide push.")

func _test_wooden_wall_physical_contact_push() -> void:
	print("\n[STEP 2] Wooden Wall moves upon physical tank contact push (take_push)...")
	var wall = WoodenWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(200, 200)

	var start_pos = wall.global_position
	wall.take_push(Vector2.RIGHT)

	var timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	assert(wall.global_position.x == start_pos.x + 48.0, "Wooden Wall should move 48px right upon contact push")
	wall.queue_free()
	print("  [PASS] Wooden Wall physically slides upon contact push.")

func _test_wooden_wall_crushes_brick_and_damages_enemy() -> void:
	print("\n[STEP 3] Wooden Wall crushes destructible terrain and damages enemies in path...")
	var wall = WoodenWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(240, 240)

	# 1. Create a destructible brick at (288, 240)
	var brick = StaticBody2D.new()
	brick.add_to_group("brick")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(24, 24)
	col.shape = shape
	brick.add_child(col)
	root.add_child(brick)
	brick.global_position = Vector2(288, 240)

	var start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.RIGHT)

	var timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	assert(wall.global_position.x == start_pos.x + 48.0, "Wall should advance 48px right")
	assert(brick.is_queued_for_deletion() or not is_instance_valid(brick), "Brick should be crushed and deleted")

	# 2. Test ramming an enemy
	var enemy = CharacterBody2D.new()
	enemy.add_to_group("enemy")
	var e_col = CollisionShape2D.new()
	var e_shape = RectangleShape2D.new()
	e_shape.size = Vector2(32, 32)
	e_col.shape = e_shape
	enemy.add_child(e_col)
	root.add_child(enemy)
	enemy.global_position = Vector2(336, 240)
	enemy.set_script(load("res://scripts/enemy.gd"))
	enemy.current_health = 4

	start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.RIGHT)

	timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	assert(enemy.current_health < 4, "Enemy should take ramming contact damage from wooden wall")
	assert(enemy.is_stunned, "Enemy should be stunned by wooden wall ram")

	enemy.queue_free()
	wall.queue_free()
	print("  [PASS] Wooden Wall crushes destructible blocks and damages/stuns enemies on contact.")

func _test_wooden_wall_damage_stages_and_destruction() -> void:
	print("\n[STEP 4] Wooden Wall visual damage stages and destruction splinter blast...")
	var wall = WoodenWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(200, 200)

	assert(wall.current_health == 3, "Initial HP should be 3")
	assert(wall.damage_frames.size() >= 3, "Should have 3 damage stage textures")

	# Damage to 2 HP
	wall.take_damage(1)
	assert(wall.current_health == 2, "HP should decrease to 2")
	assert(wall.sprite.texture == wall.damage_frames[1], "Sprite should update to cracked stage 1")

	# Damage to 1 HP
	wall.take_damage(1)
	assert(wall.current_health == 1, "HP should decrease to 1")
	assert(wall.sprite.texture == wall.damage_frames[2], "Sprite should update to splintered stage 2")

	# Fatal damage -> Destroy
	wall.take_damage(1)
	assert(wall.is_queued_for_deletion(), "Wall should queue_free on 0 HP")
	print("  [PASS] Damage stages and destruction correctly handled.")

func _test_builder_and_shop_and_encyclopedia_integration() -> void:
	print("\n[STEP 5] Checking BuilderController, ShopDialog, and EncyclopediaData integration...")
	
	# 1. BuilderController StructureType
	var builder = BuilderControllerScript.new()
	root.add_child(builder)
	assert(builder.structure_ids.has(BuilderControllerScript.StructureType.WOODEN_WALL), "BuilderController should have WOODEN_WALL in structure_ids")
	assert(builder.structure_ids[BuilderControllerScript.StructureType.WOODEN_WALL] == "wooden_wall", "Structure ID should be 'wooden_wall'")
	assert(builder.wooden_wall_scene != null, "wooden_wall_scene should be loaded")
	builder.queue_free()

	# 2. ShopDialog BUILDING_ITEMS
	var found_in_shop = false
	for item in ShopDialogScript.BUILDING_ITEMS:
		if item.get("id") == "wooden_wall":
			found_in_shop = true
			assert(item.has("cost") and item["cost"] > 0, "Shop item should have valid cost")
			assert(item.has("icon") and ResourceLoader.exists(item["icon"]), "Shop item icon should exist: %s" % item["icon"])
			break
	assert(found_in_shop, "ShopDialog BUILDING_ITEMS should contain 'wooden_wall'")

	# 3. EncyclopediaData
	var found_in_enc = false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "bld_wooden_wall":
			found_in_enc = true
			assert(ResourceLoader.exists(entry["icon"]), "Encyclopedia icon should exist: %s" % entry["icon"])
			break
	assert(found_in_enc, "EncyclopediaData should contain 'bld_wooden_wall'")

	print("  [PASS] BuilderController, Shop, and Encyclopedia integration verified.")
