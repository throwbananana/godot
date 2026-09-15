extends SceneTree

const WoodenWallScript = preload("res://scripts/buildings/wooden_wall.gd")
const BuilderControllerScript = preload("res://scripts/builder_controller.gd")
const ShopDialogScript = preload("res://scripts/shop_dialog.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func check(cond: bool, msg: String) -> bool:
	if not cond:
		fail(msg)
	return cond

## queue_free() 只是排队延迟释放；wooden_wall.gd 会把自己加进 "buildings" 分组，
## 而 _try_push() 判断目标格是否被"坚固障碍"挡住时，正是按 is_in_group("buildings")
## 来识别的。如果上一步测试的墙刚 queue_free() 就立刻进入下一步，物理服务器还没
## 真正把它移出场景，下一堵新墙的 intersect_shape 查询完全可能扫到这个"僵尸"墙体，
## 把一次原本畅通的推移误判为"被建筑挡住"而拒绝移动——这正是本文件曾经的 bug。
## 等待几帧，让延迟释放真正落地，再进入下一步。
func _settle_frames(n: int = 3) -> void:
	for i in range(n):
		await process_frame

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING WOODEN WALL (木墙) COMPREHENSIVE TESTS <<<")
	print("==================================================")

	await _test_wooden_wall_directional_push()
	await _settle_frames()
	await _test_wooden_wall_physical_contact_push()
	await _settle_frames()
	await _test_wooden_wall_crushes_brick_and_damages_enemy()
	await _settle_frames()
	await _test_wooden_wall_damage_stages_and_destruction()
	_test_builder_and_shop_and_encyclopedia_integration()

	if failures > 0:
		print("\n[FAIL] %d 项失败" % failures)
		quit(1)
	else:
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

	check(wall.global_position.x == start_pos.x + 48.0, "Wooden Wall should move 48px right, got %f" % wall.global_position.x)
	check(wall.global_position.y == start_pos.y, "Wooden Wall Y position should remain unchanged")

	# 2. Hit from top towards bottom (Vector2.DOWN)
	start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.DOWN)

	timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	check(wall.global_position.y == start_pos.y + 48.0, "Wooden Wall should move 48px down, got %f" % wall.global_position.y)
	check(wall.global_position.x == start_pos.x, "Wooden Wall X position should remain unchanged")

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

	check(wall.global_position.x == start_pos.x + 48.0, "Wooden Wall should move 48px right upon contact push")
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

	# 刚创建并定位的碰撞体，物理服务器的 broadphase 要下一步物理帧才会真正收录——
	# 和 CLAUDE.md 里"传送后同帧 intersect_shape 仍查到旧位置"是同一类问题的镜像
	# 情形（这里是全新节点而非传送，但结论一样）：不等一帧就直接查询，会查不到
	# 这块砖，wall 既撞不碎它也不会把它算进"被挡住"的判断。
	await process_frame
	await process_frame

	var start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.RIGHT)

	var timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	check(wall.global_position.x == start_pos.x + 48.0, "Wall should advance 48px right")
	check(brick.is_queued_for_deletion() or not is_instance_valid(brick), "Brick should be crushed and deleted")

	# 2. Test ramming an enemy. 用真实的 enemy.tscn 实例，而不是 CharacterBody2D.new()
	# 之后再 set_script(enemy.gd)：脚本是在节点已经进入场景树之后才挂上去的，
	# _ready() 早就跑过（那时还没有脚本），所以 enemy.gd 的 @onready var sprite =
	# $Sprite2D 永远不会被解析，take_damage() 里对 sprite 做 Tween 会直接在一个
	# null 目标上崩，报 "Parameter p_target is null" / "Tween ... no Tweeners"。
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	root.add_child(enemy)
	enemy.global_position = Vector2(336, 240)
	# enemy.gd 的生命值字段叫 health，不是 current_health（后者在整个脚本里根本不
	# 存在）；对不存在的属性赋值/比较在这个已挂脚本的 CharacterBody2D 上会直接抛
	# 运行时 "Invalid assignment of property or key" 错误。
	enemy.health = 4

	# 同样给刚创建的碰撞体一帧时间让 broadphase 收录。
	await process_frame
	await process_frame

	start_pos = wall.global_position
	wall.take_hit_direction(1, Vector2.RIGHT)

	timer = 0.0
	while wall.is_moving and timer < 1.0:
		await process_frame
		timer += 0.016

	check(enemy.health < 4, "Enemy should take ramming contact damage from wooden wall")
	# enemy.gd 用 freeze_timer (freeze() 方法) 表示定身状态，没有 is_stunned 字段；
	# 访问不存在的属性会直接抛运行时错误，让整条 check() 语句连带失效、悄悄不报告。
	check(enemy.freeze_timer > 0.0, "Enemy should be frozen/stunned by wooden wall ram")

	enemy.queue_free()
	wall.queue_free()
	print("  [PASS] Wooden Wall crushes destructible blocks and damages/stuns enemies on contact.")

func _test_wooden_wall_damage_stages_and_destruction() -> void:
	print("\n[STEP 4] Wooden Wall visual damage stages and destruction splinter blast...")
	var wall = WoodenWallScript.new()
	root.add_child(wall)
	wall.global_position = Vector2(200, 200)

	check(wall.current_health == 3, "Initial HP should be 3")
	check(wall.damage_frames.size() >= 3, "Should have 3 damage stage textures")

	# Damage to 2 HP
	wall.take_damage(1)
	check(wall.current_health == 2, "HP should decrease to 2")
	check(wall.sprite.texture == wall.damage_frames[1], "Sprite should update to cracked stage 1")

	# Damage to 1 HP
	wall.take_damage(1)
	check(wall.current_health == 1, "HP should decrease to 1")
	check(wall.sprite.texture == wall.damage_frames[2], "Sprite should update to splintered stage 2")

	# Fatal damage -> Destroy
	wall.take_damage(1)
	check(wall.is_queued_for_deletion(), "Wall should queue_free on 0 HP")
	print("  [PASS] Damage stages and destruction correctly handled.")

func _test_builder_and_shop_and_encyclopedia_integration() -> void:
	print("\n[STEP 5] Checking BuilderController, ShopDialog, and EncyclopediaData integration...")

	# 1. BuilderController StructureType
	var builder = BuilderControllerScript.new()
	root.add_child(builder)
	check(builder.structure_ids.has(BuilderControllerScript.StructureType.WOODEN_WALL), "BuilderController should have WOODEN_WALL in structure_ids")
	check(builder.structure_ids[BuilderControllerScript.StructureType.WOODEN_WALL] == "wooden_wall", "Structure ID should be 'wooden_wall'")
	check(builder.wooden_wall_scene != null, "wooden_wall_scene should be loaded")
	builder.queue_free()

	# 2. ShopDialog BUILDING_ITEMS
	var found_in_shop = false
	for item in ShopDialogScript.BUILDING_ITEMS:
		if item.get("id") == "wooden_wall":
			found_in_shop = true
			check(item.has("cost") and item["cost"] > 0, "Shop item should have valid cost")
			check(item.has("icon") and ResourceLoader.exists(item["icon"]), "Shop item icon should exist: %s" % item["icon"])
			break
	check(found_in_shop, "ShopDialog BUILDING_ITEMS should contain 'wooden_wall'")

	# 3. EncyclopediaData
	var found_in_enc = false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "bld_wooden_wall":
			found_in_enc = true
			check(ResourceLoader.exists(entry["icon"]), "Encyclopedia icon should exist: %s" % entry["icon"])
			break
	check(found_in_enc, "EncyclopediaData should contain 'bld_wooden_wall'")

	print("  [PASS] BuilderController, Shop, and Encyclopedia integration verified.")
