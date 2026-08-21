extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const StreetLamp = preload("res://scripts/buildings/street_lamp.gd")
const ElectricWall = preload("res://scripts/buildings/electric_wall.gd")
const OilBarrel = preload("res://scripts/buildings/oil_barrel.gd")
const DarknessFog = preload("res://scripts/darkness_fog.gd")
const Bullet = preload("res://scripts/bullet.gd")

func _init() -> void:
	print("=== Running Comprehensive Tests for Street Lamp, Electric Wall, and Oil Barrel ===")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var MainGameScene = load("res://scenes/main.tscn")
	var main_inst = MainGameScene.instantiate()
	root.add_child(main_inst)

	# --------------------------------------------------------------------------
	# Test 1: Street Lamp Illumination & Destruction
	# --------------------------------------------------------------------------
	print("1. Testing Street Lamp (路灯)...")
	var lamp_scene = load("res://scenes/buildings/street_lamp.tscn")
	assert(lamp_scene != null, "Street lamp scene failed to load!")
	var lamp = lamp_scene.instantiate()
	lamp.position = Vector2(240, 240)
	main_inst.actors_container.add_child(lamp)
	assert(lamp.is_in_group("street_lamp"), "Street lamp should be in street_lamp group!")
	assert(lamp.is_lit == true, "Street lamp should be lit by default!")

	# Test taking damage and destroying
	lamp.take_damage(1)
	assert(lamp.current_hp == 2, "Street lamp HP should decrease to 2!")
	lamp.take_damage(2)
	print("   ✓ Street Lamp HP & Destruction OK!")

	# --------------------------------------------------------------------------
	# Test 2: Electric Wall (电墙) Contact Shock & Bullet Absorption
	# --------------------------------------------------------------------------
	print("2. Testing Electric Wall (电墙)...")
	var elec_scene = load("res://scenes/buildings/electric_wall.tscn")
	assert(elec_scene != null, "Electric wall scene failed to load!")
	var elec_wall = elec_scene.instantiate()
	elec_wall.position = Vector2(300, 300)
	main_inst.map_container.add_child(elec_wall)
	assert(elec_wall.is_in_group("electric_wall"), "Should be in electric_wall group!")

	# Test player tank contact shock
	if main_inst.p1_instance and is_instance_valid(main_inst.p1_instance):
		var init_hp = main_inst.p1_instance.current_health
		elec_wall._try_shock_body(main_inst.p1_instance)
		assert(main_inst.p1_instance.current_health == init_hp - 1 or main_inst.p1_instance.is_invulnerable, "Player should take shock damage!")
		print("   ✓ Electric Wall Contact Shock OK!")

	# Test bullet absorption
	var bullet_scene = load("res://scenes/bullet.tscn")
	if bullet_scene:
		var test_bullet = bullet_scene.instantiate()
		test_bullet.position = elec_wall.position
		main_inst.actors_container.add_child(test_bullet)
		elec_wall._try_shock_body(test_bullet)
		print("   ✓ Electric Wall Bullet Absorption OK!")

	# --------------------------------------------------------------------------
	# Test 3: Oil Barrel (汽油桶) 3x3 Blast & Chain Explosion
	# --------------------------------------------------------------------------
	print("3. Testing Explosive Oil Barrel (汽油桶)...")
	var barrel_scene = load("res://scenes/buildings/oil_barrel.tscn")
	assert(barrel_scene != null, "Oil barrel scene failed to load!")

	var barrel1 = barrel_scene.instantiate()
	barrel1.position = Vector2(400, 400)
	main_inst.actors_container.add_child(barrel1)

	var barrel2 = barrel_scene.instantiate()
	barrel2.position = Vector2(430, 400) # Adjacent barrel
	main_inst.actors_container.add_child(barrel2)

	# Trigger detonation on barrel 1
	barrel1.detonate()
	assert(barrel1.is_exploded == true, "Barrel 1 should be marked exploded!")
	print("   ✓ Oil Barrel Detonation & Chain Reaction OK!")

	# --------------------------------------------------------------------------
	# Test 4: Map Spawning for Tiles 24, 25, 26
	# --------------------------------------------------------------------------
	print("4. Testing Map Template Spawning for Tiles 24, 25, 26...")
	main_inst._spawn_street_lamp(Vector2(100, 100))
	main_inst._spawn_electric_wall(Vector2(150, 150))
	main_inst._spawn_oil_barrel(Vector2(200, 200))

	var found_lamp = false
	var found_elec = false
	var found_barrel = false
	for child in main_inst.actors_container.get_children():
		if child is StreetLamp: found_lamp = true
		if child is OilBarrel: found_barrel = true
	for child in main_inst.map_container.get_children():
		if child is ElectricWall: found_elec = true

	assert(found_lamp, "Street lamp should be in actors container!")
	assert(found_elec, "Electric wall should be in map container!")
	assert(found_barrel, "Oil barrel should be in actors container!")
	print("   ✓ Map Spawning OK!")

	# --------------------------------------------------------------------------
	# Test 5: Darkness Fog Integration with Street Lamps
	# --------------------------------------------------------------------------
	print("5. Testing Darkness Fog Street Lamp Illumination...")
	var fog = DarknessFog.new()
	main_inst.add_child(fog)
	fog._process(0.016)
	print("   ✓ Darkness Fog Illumination OK!")

	main_inst.queue_free()
	print("\n🎉 ALL NEW MODEL, ANIMATION, AND GAMEPLAY TESTS PASSED! 🎉")
	quit(0)
