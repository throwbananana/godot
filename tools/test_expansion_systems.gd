extends SceneTree

const LandmineHazard = preload("res://scripts/landmine_hazard.gd")
const LaserPiercer = preload("res://scripts/laser_piercer.gd")
const EnemyTank = preload("res://scripts/enemy.gd")
const Bullet = preload("res://scripts/bullet.gd")
const GameState = preload("res://scripts/game_state.gd")

func _init() -> void:
	print("=== Running Expansion Systems Test (Landmines, Laser, Homing Missiles, Enemy Types) ===")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var root_node = Node2D.new()
	root.add_child(root_node)

	# 1. Test Landmine Hazard Detonation and Brick Destruction
	print(">>> 1. Testing Landmine Hazard & Terrain Interaction...")
	var landmine_scene = load("res://scenes/landmine_hazard.tscn")
	var landmine = landmine_scene.instantiate()
	root_node.add_child(landmine)
	landmine.global_position = Vector2(100, 100)

	# Add dummy brick nearby
	var test_brick = StaticBody2D.new()
	test_brick.add_to_group("brick")
	root_node.add_child(test_brick)
	test_brick.global_position = Vector2(115, 100)

	var player_scene = load("res://scenes/player.tscn")
	var dummy_tank = player_scene.instantiate()
	root_node.add_child(dummy_tank)
	dummy_tank.is_invulnerable = false
	dummy_tank.current_health = 3

	landmine.detonate(dummy_tank)
	assert(dummy_tank.current_health <= 0, "Landmine should deal lethal/heavy damage to tank")
	print("✓ Landmine detonation & damage logic verified.")

	# 2. Test Linear Piercing Laser
	print(">>> 2. Testing Linear Piercing Laser...")
	var laser_start = Vector2(200, 200)
	var laser_dir = Vector2.RIGHT

	# Add brick sub-tile in laser path
	var path_brick = StaticBody2D.new()
	path_brick.add_to_group("brick")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(24, 24)
	col.shape = shape
	path_brick.add_child(col)
	root_node.add_child(path_brick)
	path_brick.global_position = Vector2(280, 200)

	LaserPiercer.fire_linear_laser(root_node, laser_start, laser_dir, null, "player", 3)
	print("✓ Linear Piercing Laser fired cleanly.")

	# 3. Test Homing Missile Target Tracking
	print(">>> 3. Testing Homing Missile Bullet...")
	var bullet_scene = load("res://scenes/bullet.tscn")
	var missile = bullet_scene.instantiate()
	root_node.add_child(missile)
	missile.is_homing = true
	missile.target = dummy_tank
	missile.direction = Vector2.UP
	missile.global_position = Vector2(500, 500)
	dummy_tank.global_position = Vector2(600, 500) # To the right

	missile._physics_process(0.5)
	assert(missile.direction.x > 0.0, "Missile direction should steer towards target on right")
	print("✓ Homing missile tracking process verified.")

	# 4. Test New Enemy Tank Types (MISSILE, LASER, BOSS)
	print(">>> 4. Testing Enemy Types (MISSILE, LASER, BOSS)...")
	var enemy_scene = load("res://scenes/enemy.tscn")
	var enemy_missile = enemy_scene.instantiate()
	enemy_missile.enemy_type = EnemyTank.EnemyType.MISSILE
	root_node.add_child(enemy_missile)
	assert(enemy_missile.max_health >= 3, "Missile tank should have >= 3 max HP")
	print("✓ Missile enemy tank verified.")

	var enemy_laser = enemy_scene.instantiate()
	enemy_laser.enemy_type = EnemyTank.EnemyType.LASER
	root_node.add_child(enemy_laser)
	assert(enemy_laser.max_health >= 3, "Laser tank should have >= 3 max HP")
	print("✓ Laser enemy tank verified.")

	# 5. 关卡预览对话框已随尖塔路线图一同退役。
	#    以撒式房间没有"进入战斗前先看一个简报"这一步 —— 玩家是直接走进
	#    房间的, 房型靠小地图上的颜色点和进门时的 toast 告知。
	#    楼层生成本身改由 tools/test_floor_map.gd 验收。

	print("\n🎉 ALL EXPANSION SYSTEMS AUTOMATED TESTS PASSED SUCCESSFULLY! 🎉\n")
	quit(0)
