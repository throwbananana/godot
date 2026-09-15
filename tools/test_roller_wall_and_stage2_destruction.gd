extends SceneTree

const RollerWallScript = preload("res://scripts/buildings/roller_wall.gd")
const BulletScript = preload("res://scripts/bullet.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING ROLLER WALL & STAGE 2 TESTS <<<")
	print("==================================================")

	_test_roller_wall_directional_push()
	_test_roller_wall_crushes_brick()
	_test_stage2_shell_destroys_all_buildings()
	_test_builder_and_shop_integration()

	print("\n>>> ALL ROLLER WALL & STAGE 2 CHECKS PASSED! <<<")
	quit(0)

func _test_roller_wall_directional_push() -> void:
	print("\n[STEP] Roller Wall moves 1 grid cell (48px) in attack direction...")
	var wall = RollerWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(240, 240)

	# 1. Hit from left towards right (direction Vector2.RIGHT)
	var start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.RIGHT)

	# Process frame/tween
	var timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	assert(wall.global_position.x == start_pos.x + 48.0, "Wall should move 48px right, got %f" % wall.global_position.x)
	assert(wall.global_position.y == start_pos.y, "Wall Y position should remain unchanged")

	# 2. Hit from top towards bottom (direction Vector2.DOWN)
	start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.DOWN)

	timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	assert(wall.global_position.y == start_pos.y + 48.0, "Wall should move 48px down, got %f" % wall.global_position.y)
	assert(wall.global_position.x == start_pos.x, "Wall X position should remain unchanged")

	wall.queue_free()
	print("  [PASS] Roller Wall correctly responds to kinetic attack direction and shifts 1 cell.")

func _test_roller_wall_crushes_brick() -> void:
	print("\n[STEP] Roller Wall crushes brick obstacles in its path...")
	var wall = RollerWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(240, 240)

	# Create a dummy brick obstacle at (288, 240)
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

	assert(wall.global_position.x == start_pos.x + 48.0, "Wall should crush brick and move 48px right")
	assert(brick.is_queued_for_deletion() or not is_instance_valid(brick), "Brick should be crushed")

	wall.queue_free()
	print("  [PASS] Roller Wall crushes obstacles in path and completes push.")

func _test_stage2_shell_destroys_all_buildings() -> void:
	print("\n[STEP] Stage 2 shells (can_destroy_steel=true) destroy all buildings...")

	var building_scenes = [
		"res://scenes/buildings/fortified_wall.tscn",
		"res://scenes/buildings/electric_wall.tscn",
		"res://scenes/buildings/defense_turret.tscn",
		"res://scenes/buildings/wind_blower.tscn",
		"res://scenes/buildings/street_lamp.tscn",
		"res://scenes/buildings/roller_wall.tscn"
	]

	for b_path in building_scenes:
		var scene = load(b_path)
		var b_inst = scene.instantiate()
		root.add_child(b_inst)
		b_inst.global_position = Vector2(200, 200)

		# Create a Stage 2 bullet
		var bullet_scene = load("res://scenes/bullet.tscn")
		var bullet = bullet_scene.instantiate()
		bullet.can_destroy_steel = true
		bullet.damage = 2
		bullet.shooter_type = "player"
		root.add_child(bullet)
		bullet.global_position = Vector2(200, 200)

		# Trigger body entered
		if b_inst is CollisionObject2D:
			bullet._on_body_entered(b_inst)
		else:
			for child in b_inst.get_children():
				if child is CollisionObject2D:
					bullet._on_body_entered(child)
					break

		await process_frame
		await process_frame
		assert(b_inst.is_queued_for_deletion() or b_inst.get_child_count() == 0 or not is_instance_valid(b_inst), "Building %s should be destroyed by Stage 2 shell" % b_path)
		if is_instance_valid(b_inst):
			b_inst.queue_free()
		if is_instance_valid(bullet):
			bullet.queue_free()

	print("  [PASS] All buildings are destroyed by Stage 2 shells.")

func _test_builder_and_shop_integration() -> void:
	print("\n[STEP] Builder Controller & Shop Dialog integrate Roller Wall...")

	# ShopDialog check
	var shop_scene = load("res://scenes/shop_dialog.tscn")
	var shop = shop_scene.instantiate()
	root.add_child(shop)

	var has_roller_in_shop = false
	for item in shop.BUILDING_ITEMS:
		if item["id"] == "roller_wall":
			has_roller_in_shop = true
			break
	assert(has_roller_in_shop, "Shop BUILDING_ITEMS must contain roller_wall")
	shop.queue_free()

	# BuilderController check
	var builder_scene = load("res://scenes/builder_controller.tscn") if ResourceLoader.exists("res://scenes/builder_controller.tscn") else null
	var builder = builder_scene.instantiate() if builder_scene else BuilderController.new()
	root.add_child(builder)

	assert(builder.structure_ids.has(BuilderController.StructureType.ROLLER_WALL), "builder structure_ids must contain ROLLER_WALL")
	assert(builder.structure_ids[BuilderController.StructureType.ROLLER_WALL] == "roller_wall", "ROLLER_WALL id must be 'roller_wall'")
	builder.queue_free()

	print("  [PASS] Builder and Shop correctly recognize roller_wall.")
