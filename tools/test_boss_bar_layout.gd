extends SceneTree

const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

func _init() -> void:
	var root_ctrl = Control.new()
	root_ctrl.size = Vector2(1024, 768)
	
	var boss_dict = UIThemeHelper.create_boss_bar(root_ctrl)
	var root: Control = boss_dict["root"]
	var prog: TextureProgressBar = boss_dict["prog"]
	var lbl: Label = boss_dict["label"]
	
	print("Root position: ", root.position)
	print("Root custom_minimum_size: ", root.custom_minimum_size)
	print("Root size: ", root.size)
	print("Prog nine_patch: ", prog.nine_patch_stretch)
	print("Prog size: ", prog.size)
	print("Prog min size: ", prog.get_minimum_size())
	
	# Verify that root bottom edge is strictly <= 48.0
	var bottom_y = root.position.y + prog.size.y
	print("Boss Bar Bottom Y on screen: ", bottom_y)
	if bottom_y <= 48.0:
		print("SUCCESS: Boss Bar bottom Y (", bottom_y, ") is strictly <= GameArea Top Y (48.0). Zero occlusion of Row 0!")
	else:
		print("FAILURE: Boss Bar encroaches into GameArea! Bottom Y: ", bottom_y)
	
	root_ctrl.free()
	quit(0)
