extends SceneTree

const Bullet = preload("res://scripts/bullet.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")

func _init() -> void:
	print("=== Testing 3D Clay Bullet Generation & Texture Integration ===")
	
	var bullet_paths = [
		"res://assets/sprites/effects/bullet.png",
		"res://assets/sprites/effects/bullet_plasma.png",
		"res://assets/sprites/effects/bullet_missile.png",
		"res://assets/sprites/effects/bullet_ricochet.png"
	]
	
	for path in bullet_paths:
		var tex = TextureHelper.get_tex(path)
		assert(tex != null, "Failed to load bullet texture: " + path)
		print("✓ Texture OK: ", path, " Size: ", tex.get_size())
		assert(tex.get_width() > 0 and tex.get_height() > 0, "Texture must have non-zero dimensions")
		
	var bullet_scene = load("res://scenes/bullet.tscn")
	assert(bullet_scene != null, "Failed to load bullet.tscn")
	
	# Test standard bullet
	var b_std = bullet_scene.instantiate() as Bullet
	root.add_child(b_std)
	b_std._ready()
	var sp_std = b_std.get_node("Sprite2D") as Sprite2D
	assert(sp_std != null and sp_std.texture != null, "Standard Bullet sprite texture must be set")
	print("✓ Standard Bullet instantiated OK with texture: ", sp_std.texture)
	b_std.free()
	
	# Test plasma bullet
	var b_plasma = bullet_scene.instantiate() as Bullet
	b_plasma.can_destroy_steel = true
	root.add_child(b_plasma)
	b_plasma._ready()
	var sp_pl = b_plasma.get_node("Sprite2D") as Sprite2D
	assert(sp_pl.texture != null, "Plasma Bullet sprite texture must be set")
	print("✓ Plasma Bullet instantiated OK with texture: ", sp_pl.texture)
	b_plasma.free()
	
	# Test homing missile
	var b_mis = bullet_scene.instantiate() as Bullet
	b_mis.is_homing = true
	root.add_child(b_mis)
	b_mis._ready()
	var sp_mis = b_mis.get_node("Sprite2D") as Sprite2D
	assert(sp_mis.texture != null, "Missile Bullet sprite texture must be set")
	print("✓ Homing Missile instantiated OK with texture: ", sp_mis.texture)
	b_mis.free()

	print("🎉 All 3D Clay Bullet Tests Passed Cleanly! 🎉")
	quit(0)
