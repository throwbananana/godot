extends SceneTree

func _init() -> void:
	print("=== Testing Title Screen VFX, Halo & Animations ===")
	var scene = load("res://scenes/title_screen.tscn")
	assert(scene != null, "Failed to load title_screen.tscn")
	
	var instance = scene.instantiate()
	root.add_child(instance)
	
	var bg_tex = instance.get_node("BackgroundTexture") as TextureRect
	assert(bg_tex != null and bg_tex.texture != null, "BackgroundTexture must be loaded")
	print("✓ Background Texture OK: ", bg_tex.texture.resource_path)
	
	var halo = instance.get_node("CenterContainer/VBox/LogoContainer/HaloSprite") as Sprite2D
	assert(halo != null and halo.texture != null, "HaloSprite must exist and have texture")
	print("✓ Halo Sprite OK: ", halo.texture.resource_path)
	
	var logo = instance.get_node("CenterContainer/VBox/LogoContainer/LogoTexture") as TextureRect
	assert(logo != null and logo.texture != null, "LogoTexture must exist and have texture")
	print("✓ Title Logo OK: ", logo.texture.resource_path)
	
	var sparkle_cnt = instance.get_node("CenterContainer/VBox/LogoContainer/SparkleContainer") as Control
	assert(sparkle_cnt != null, "SparkleContainer must exist")
	print("✓ Sparkle Container OK")
	
	var menu_panel = instance.get_node("CenterContainer/VBox/MenuPanel") as PanelContainer
	assert(menu_panel != null, "MenuPanel must exist")
	print("✓ MenuPanel OK")
	
	# Simulate 1 frame process
	instance._process(0.016)
	
	instance.free()
	print("🎉 Title Screen VFX & Curve Animations Test Passed Successfully! 🎉")
	quit(0)
