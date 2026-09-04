extends SceneTree

const DarknessDevice = preload("res://scripts/buildings/darkness_device.gd")
const DarknessFog = preload("res://scripts/darkness_fog.gd")
const BuilderController = preload("res://scripts/builder_controller.gd")
const ShopDialog = preload("res://scripts/shop_dialog.gd")
const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")
const GameState = preload("res://scripts/game_state.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING DARKNESS DEVICE & FOG TESTS <<<")
	print("==================================================")

	# 1. Test Scene & Script Loading
	var device_scene = load("res://scenes/buildings/darkness_device.tscn")
	assert(device_scene != null, "[FAIL] Darkness device scene could not be loaded!")
	print("  [PASS] Darkness device scene loaded successfully.")

	# 2. Test DarknessFog Shader & Extra Lights Capacity
	var fog = DarknessFog.new()
	assert(fog.material != null, "[FAIL] DarknessFog material is null!")
	var mat = fog.material as ShaderMaterial
	assert(mat != null, "[FAIL] DarknessFog material is not ShaderMaterial!")

	var dummy_p1 = Node2D.new()
	var dummy_p2 = Node2D.new()
	var dummy_base = Node2D.new()
	dummy_p1.position = Vector2(100, 200)
	dummy_p2.position = Vector2(300, 400)
	dummy_base.position = Vector2(312, 600)
	root.add_child(dummy_p1)
	root.add_child(dummy_p2)
	root.add_child(dummy_base)

	fog.setup_trackers(dummy_p1, dummy_p2, dummy_base)
	root.add_child(fog)
	await process_frame

	# 3. Test Darkness Device Instance & Light Emission
	var dev = device_scene.instantiate() as DarknessDevice
	assert(dev != null, "[FAIL] Could not instantiate DarknessDevice!")
	dev.position = Vector2(250, 250)
	root.add_child(dev)
	await process_frame

	assert(dev.is_in_group("darkness_device"), "[FAIL] DarknessDevice not in 'darkness_device' group!")
	assert(dev.is_in_group("building"), "[FAIL] DarknessDevice not in 'building' group!")
	assert(dev.is_in_group("destructible"), "[FAIL] DarknessDevice not in 'destructible' group!")

	# Simulate process step on fog
	fog._process(0.016)

	var extra_count = mat.get_shader_parameter("extra_lights_count")
	var extra_pos = mat.get_shader_parameter("extra_lights_pos")
	var extra_rad = mat.get_shader_parameter("extra_lights_radius")

	assert(extra_count > 0, "[FAIL] Darkness device was not captured in extra_lights_count!")
	var found_device_light := false
	for i in range(extra_count):
		if extra_pos[i].distance_to(dev.position) < 1.0 and extra_rad[i] > 80.0:
			found_device_light = true
			break
	assert(found_device_light, "[FAIL] Darkness device position & radius not found in extra_lights!")
	print("  [PASS] Darkness device registered and illuminated properly in DarknessFog.")

	# 4. Test Bullet Light & Explosion Flash
	var dummy_bullet = Node2D.new()
	dummy_bullet.add_to_group("bullet")
	dummy_bullet.position = Vector2(150, 150)
	root.add_child(dummy_bullet)
	await process_frame

	fog.add_flash(Vector2(400, 400), 160.0, 0.4)
	fog._process(0.016)

	extra_count = mat.get_shader_parameter("extra_lights_count")
	extra_pos = mat.get_shader_parameter("extra_lights_pos")
	assert(extra_count >= 3, "[FAIL] Extra lights should include flash + darkness_device + bullet (got %d)!" % extra_count)

	var found_bullet := false
	var found_flash := false
	for i in range(extra_count):
		if extra_pos[i].distance_to(dummy_bullet.position) < 1.0:
			found_bullet = true
		if extra_pos[i].distance_to(Vector2(400, 400)) < 1.0:
			found_flash = true
	assert(found_bullet, "[FAIL] Bullet dynamic light not found in DarknessFog!")
	assert(found_flash, "[FAIL] Explosion flash dynamic light not found in DarknessFog!")
	print("  [PASS] Bullet illumination and explosion flashes verified in darkness.")

	# 5. Test Multi-Device Lifetime & Destruction
	var dev2 = device_scene.instantiate() as DarknessDevice
	dev2.position = Vector2(500, 500)
	root.add_child(dev2)
	await process_frame

	# Damage dev
	dev.take_damage(2)
	assert(dev.current_hp == 3, "[FAIL] dev HP should be 3 after 2 damage, got %d" % dev.current_hp)
	dev.take_damage(dev.current_hp) # lethal
	assert(dev.is_queued_for_deletion() or not dev.is_active, "[FAIL] Destroyed dev should be inactive or queued for deletion!")

	# Clean up dev2
	dev2._destroy()
	print("  [PASS] Multi-device lifecycle and damage handling verified.")

	# 6. Test BuilderController Integration
	var bc = BuilderController.new()
	assert(BuilderController.StructureType.DARKNESS_DEVICE in bc.structure_list, "[FAIL] DARKNESS_DEVICE missing from structure_list!")
	assert(bc.structure_ids.get(BuilderController.StructureType.DARKNESS_DEVICE) == "darkness_device", "[FAIL] structure_ids missing darkness_device!")
	assert("DARKNESS" in bc.structure_names.get(BuilderController.StructureType.DARKNESS_DEVICE), "[FAIL] structure_names missing darkness_device!")
	bc.queue_free()
	print("  [PASS] BuilderController registration verified.")

	# 7. Test ShopDialog Integration
	var found_shop_item := false
	for item in ShopDialog.BUILDING_ITEMS:
		if item.get("id") == "darkness_device":
			found_shop_item = true
			assert(item.get("cost") > 0, "[FAIL] darkness_device cost invalid!")
			assert(ResourceLoader.exists(item.get("icon")), "[FAIL] darkness_device shop icon missing: %s" % item.get("icon"))
			break
	assert(found_shop_item, "[FAIL] darkness_device not found in ShopDialog.BUILDING_ITEMS!")
	print("  [PASS] ShopDialog catalog item verified.")

	# 8. Test Encyclopedia Integration
	var found_enc := false
	for entry in EncyclopediaData.ENTRIES:
		if entry.get("id") == "bld_darkness_device":
			found_enc = true
			assert(ResourceLoader.exists(entry.get("icon")), "[FAIL] encyclopedia icon missing: %s" % entry.get("icon"))
			break
	assert(found_enc, "[FAIL] bld_darkness_device not found in EncyclopediaData!")
	print("  [PASS] EncyclopediaData compendium entry verified.")

	# Clean up
	dummy_bullet.queue_free()
	dummy_p1.queue_free()
	dummy_p2.queue_free()
	dummy_base.queue_free()
	fog.queue_free()

	print("\n>>> ALL DARKNESS DEVICE CHECKS PASSED! <<<")
	quit(0)
