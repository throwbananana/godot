extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==========================================================")
	print(">>> RUNNING ALL WALLS & STEEL SUBDIVISION TESTS (4/4)  <<<")
	print("==========================================================")

	var main_scene = load("res://scenes/main.tscn")
	if not main_scene:
		print("  [FAIL] Failed to load main.tscn!")
		quit(1)
		return

	var main_node = main_scene.instantiate()
	root.add_child(main_node)

	# 以撒式房间: main.tscn 一启动进的是**起始房**, 没有敌人也没有鹰巢
	# (基地只在没打完的战斗房里存在, 一清空就被 _despawn_base() 撤掉)。
	# 铲子作用于基地, 所以得先挪进一间战斗房 —— 否则测到的是一间空房,
	# 报出来的是"20 块钢砖实际 0 块"这种看起来像功能坏了、实际只是站错
	# 房间的结论。
	_enter_first_combat_room(main_node)

	var map_container = main_node.get_node_or_null("GameArea/MapContainer")
	var base_wall_container = main_node.get_node_or_null("GameArea/BaseWallContainer")
	if not map_container or not base_wall_container:
		print("  [FAIL] MapContainer or BaseWallContainer missing!")
		quit(1)
		return

	# TEST 1: Brick Wall (砖墙)
	print("  [STEP 1] Testing Map Brick Wall 2x2 Subdivision & Partial Destruction...")
	var test_parent = Node2D.new()
	root.add_child(test_parent)

	var test_tile_pos = Vector2(100.0, 100.0)
	main_node._spawn_brick_tile(test_parent, test_tile_pos, false)

	var sub_tiles = test_parent.get_children()
	if sub_tiles.size() != 4:
		print("  [FAIL] Expected 4 sub-bricks for brick tile, got %d" % sub_tiles.size())
		quit(1)
		return

	var bullet_scene = load("res://scenes/bullet.tscn")
	var bullet = bullet_scene.instantiate()
	bullet.direction = Vector2.UP
	bullet.speed = 480.0
	test_parent.add_child(bullet)
	bullet.global_position = Vector2(100.0, 112.0)

	var bl = sub_tiles[2] # (r=1, c=0)
	var br = sub_tiles[3] # (r=1, c=1)
	var tl = sub_tiles[0] # (r=0, c=0)
	var tr = sub_tiles[1] # (r=0, c=1)

	bullet._on_body_entered(bl)
	bullet._on_body_entered(br)

	if not bl.is_queued_for_deletion() or not br.is_queued_for_deletion():
		print("  [FAIL] Bottom sub-bricks were not destroyed by bullet!")
		quit(1)
		return
	if tl.is_queued_for_deletion() or tr.is_queued_for_deletion():
		print("  [FAIL] Top sub-bricks should NOT be destroyed by bottom hit!")
		quit(1)
		return

	print("    [PASS] Brick wall partial destruction (bottom half destroyed, top half intact)")

	# TEST 2: Steel Wall (铁墙)
	print("  [STEP 2] Testing Steel Wall (铁墙) 2x2 Subdivision & Tier 3 Plasma Destruction...")
	var test_parent_steel = Node2D.new()
	root.add_child(test_parent_steel)

	main_node._spawn_brick_tile(test_parent_steel, Vector2(200.0, 200.0), true)
	var steel_subs = test_parent_steel.get_children()
	if steel_subs.size() != 4:
		print("  [FAIL] Expected 4 sub-steels, got %d" % steel_subs.size())
		quit(1)
		return

	var norm_bullet = bullet_scene.instantiate()
	norm_bullet.can_destroy_steel = false
	test_parent_steel.add_child(norm_bullet)
	norm_bullet._on_body_entered(steel_subs[0])

	if steel_subs[0].is_queued_for_deletion():
		print("  [FAIL] Normal bullet should NOT destroy steel sub-block!")
		quit(1)
		return
	print("    [PASS] Normal bullet blocked by steel wall")

	var plasma_bullet = bullet_scene.instantiate()
	plasma_bullet.can_destroy_steel = true
	test_parent_steel.add_child(plasma_bullet)
	plasma_bullet._on_body_entered(steel_subs[0])
	plasma_bullet._on_body_entered(steel_subs[1])

	if not steel_subs[0].is_queued_for_deletion() or not steel_subs[1].is_queued_for_deletion():
		print("  [FAIL] Plasma bullet should destroy hit steel sub-blocks!")
		quit(1)
		return
	if steel_subs[2].is_queued_for_deletion() or steel_subs[3].is_queued_for_deletion():
		print("  [FAIL] Other steel sub-blocks should remain intact!")
		quit(1)
		return
	print("    [PASS] Steel wall partial destruction by plasma bullet (front half destroyed, back half intact)")

	# TEST 3: Base Bunker & Shovel
	print("  [STEP 3] Testing Base Eagle Bunker & Shovel Steel Walls...")
	main_node.trigger_shovel()
	var shovel_sub_steels = base_wall_container.get_children().filter(func(c): return not c.is_queued_for_deletion() and c.is_in_group("steel"))
	if shovel_sub_steels.size() != 20:
		print("  [FAIL] Expected 20 steel sub-bricks around base, got %d" % shovel_sub_steels.size())
		quit(1)
		return
	print("    [PASS] Base bunker fortified with 20 subdivided steel blocks on Shovel powerup")

	# TEST 4: Fortified Wall building
	print("  [STEP 4] Testing Fortified Wall Building (4 Sub-pieces)...")
	var wall_bld_scene = load("res://scenes/buildings/fortified_wall.tscn")
	var wall_bld = wall_bld_scene.instantiate()
	root.add_child(wall_bld)
	wall_bld.global_position = Vector2(300.0, 300.0)

	var pieces = wall_bld.get_children().filter(func(c): return c is StaticBody2D)
	if pieces.size() != 4:
		print("  [FAIL] Fortified wall should have 4 StaticBody2D pieces, got %d" % pieces.size())
		quit(1)
		return

	var p0 = pieces[0]
	p0.take_damage(3)
	if not p0.is_queued_for_deletion():
		print("  [FAIL] Piece 0 should be destroyed after taking 3 damage!")
		quit(1)
		return
	if pieces[1].is_queued_for_deletion() or pieces[2].is_queued_for_deletion() or pieces[3].is_queued_for_deletion():
		print("  [FAIL] Other 3 pieces of fortified wall should remain intact!")
		quit(1)
		return
	print("    [PASS] Fortified wall building 4-piece partial destruction verified")

	print("\n>>> ALL 4/4 SUBDIVISION & PARTIAL DESTRUCTION TESTS PASSED! <<<\n")
	quit(0)


const GameStateT = preload("res://scripts/game_state.gd")
const FloorMapT = preload("res://scripts/floor_map.gd")

func _enter_first_combat_room(main_node) -> void:
	if GameStateT.mode != GameStateT.GameMode.CAMPAIGN:
		return
	for k in GameStateT.floor_rooms.keys():
		if FloorMapT.is_combat_room(GameStateT.floor_rooms[k]):
			main_node.enter_room(str(k), -1)
			return
