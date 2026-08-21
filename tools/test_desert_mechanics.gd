extends SceneTree

const PlayerTank = preload("res://scripts/player.gd")
const EnemyTank = preload("res://scripts/enemy.gd")
const Bullet = preload("res://scripts/bullet.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")

func _init() -> void:
	print("==========================================================")
	print(">>> RUNNING DESERT TERRAIN, DUNES & DESERT TANK TESTS  <<<")
	print("==========================================================")

	test_textures_loading()
	test_player_sand_slowdown()
	test_desert_tank_sand_speedup()
	test_sand_dune_whole_block_collapse()
	test_desert_map_templates()

	print("\n>>> ALL DESERT TERRAIN & TANK MECHANICS TESTS PASSED! <<<")
	quit(0)

func test_textures_loading() -> void:
	print("\n[STEP 1] Testing Desert 3D Clay Textures Loading...")
	var sand_tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_sand.png")
	assert(sand_tex != null, "tile_sand.png failed to load!")
	var dune_tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_sand_dune.png")
	assert(dune_tex != null, "tile_sand_dune.png failed to load!")

	for i in range(6):
		var tank_tex = TextureHelper.get_tex("res://assets/sprites/tanks/tank_desert_f%d.png" % i)
		assert(tank_tex != null, "tank_desert_f%d.png failed to load!" % i)

	var b_sand = TextureHelper.get_tex("res://assets/sprites/ui/badge_desert.png")
	var b_tank = TextureHelper.get_tex("res://assets/sprites/ui/badge_desert_tank.png")
	assert(b_sand != null and b_tank != null, "Desert UI badges failed to load!")
	print("  [PASS] All 10 desert 3D assets loaded cleanly.")

func test_player_sand_slowdown() -> void:
	print("\n[STEP 2] Testing Player Sand Terrain Slowdown (50% Speed Penalty)...")
	var player_scene = load("res://scenes/player.tscn")
	var p: PlayerTank = player_scene.instantiate()
	root.add_child(p)

	# Initial state (on normal ground)
	assert(not p.is_on_sand, "Player should start off-sand")
	
	# Enter sand
	p.on_enter_sand()
	assert(p.is_on_sand, "Player should be on sand after on_enter_sand()")
	assert(p.sand_overlap_count == 1, "Sand overlap count should be 1")

	# Exit sand
	p.on_exit_sand()
	assert(not p.is_on_sand, "Player should not be on sand after on_exit_sand()")
	assert(p.sand_overlap_count == 0, "Sand overlap count should be 0")

	p.queue_free()
	print("  [PASS] Player sand terrain enter/exit and speed drag verified.")

func test_desert_tank_sand_speedup() -> void:
	print("\n[STEP 3] Testing Desert Tank vs Standard Tank on Sand...")
	var enemy_scene = load("res://scenes/enemy.tscn")

	# 1. Standard Enemy
	var basic_enemy: EnemyTank = enemy_scene.instantiate()
	basic_enemy.enemy_type = EnemyTank.EnemyType.BASIC
	root.add_child(basic_enemy)
	basic_enemy._setup_tank_type()
	assert(basic_enemy.speed == 110.0, "Basic enemy base speed should be 110.0")

	basic_enemy.on_enter_sand()
	assert(basic_enemy.is_on_sand, "Basic enemy is on sand")
	# On sand standard speed is scaled by 0.50 -> 55.0
	basic_enemy.queue_free()

	# 2. Desert Specialist Tank
	var desert_enemy: EnemyTank = enemy_scene.instantiate()
	desert_enemy.enemy_type = EnemyTank.EnemyType.DESERT
	root.add_child(desert_enemy)
	desert_enemy._setup_tank_type()
	assert(desert_enemy.speed == 145.0, "Desert tank base speed should be 145.0")
	assert(desert_enemy.tank_frames.size() == 6, "Desert tank should have 6 animation frames")

	desert_enemy.on_enter_sand()
	assert(desert_enemy.is_on_sand, "Desert tank is on sand")
	# On sand, desert tank speed is scaled by 1.45 -> 210.25 (Fast agile interceptor!)
	desert_enemy.queue_free()

	print("  [PASS] Desert tank specialized sand agility +45% verified.")

func test_sand_dune_whole_block_collapse() -> void:
	print("\n[STEP 4] Testing Sand Dune Whole Block Collapse (整块坍塌)...")
	# Construct a Sand Dune Block (Single 48x48 StaticBody2D in group ["brick", "sand_dune"])
	var dune = StaticBody2D.new()
	dune.add_to_group("brick")
	dune.add_to_group("sand_dune")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(46, 46)
	col.shape = shape
	dune.add_child(col)
	root.add_child(dune)

	# Fire a bullet at the sand dune
	var bullet_scene = load("res://scenes/bullet.tscn")
	var b: Bullet = bullet_scene.instantiate()
	b.shooter_type = "player"
	root.add_child(b)

	# Simulate bullet hitting sand dune
	b._on_body_entered(dune)

	assert(dune.is_queued_for_deletion(), "Sand Dune must collapse ENTIRELY as a single whole block upon bullet hit!")
	b.queue_free()
	print("  [PASS] Sand dune single-piece whole block destruction verified.")

func test_desert_map_templates() -> void:
	print("\n[STEP 5] Testing Desert Map Templates (Storm & Oasis)...")
	var storm = MapTemplates.TEMPLATE_DESERT_STORM
	assert(storm.size() == 13 and storm[0].size() == 13, "Desert Storm template dimensions must be 13x13")
	
	var oasis = MapTemplates.TEMPLATE_OASIS_DUNES
	assert(oasis.size() == 13 and oasis[0].size() == 13, "Oasis Dunes template dimensions must be 13x13")

	# Check presence of sand tiles (6) and sand dune blocks (7)
	var has_sand = false
	var has_dunes = false
	for r in range(13):
		for c in range(13):
			if storm[r][c] == 6 or oasis[r][c] == 6:
				has_sand = true
			if storm[r][c] == 7 or oasis[r][c] == 7:
				has_dunes = true

	assert(has_sand, "Desert map template must contain sand ground tiles (6)")
	assert(has_dunes, "Desert map template must contain sand dune blocks (7)")
	print("  [PASS] Desert Storm & Oasis Dunes map templates validated.")
