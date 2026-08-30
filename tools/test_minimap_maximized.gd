extends SceneTree

const Minimap = preload("res://scripts/minimap.gd")
const FloorMap = preload("res://scripts/floor_map.gd")
const GameState = preload("res://scripts/game_state.gd")

func _init() -> void:
	print("=== Testing Minimap Enlargement & Maximization System ===")
	
	# Mock game state floor rooms
	var map_data = FloorMap.generate(1, 12345, 1)
	GameState.floor_rooms = map_data["rooms"]
	GameState.current_room = map_data["start"]
	GameState.current_act = 1
	
	var root_ctrl = Control.new()
	root_ctrl.name = "HUD"
	root_ctrl.size = Vector2(1024, 768)
	root.add_child(root_ctrl)
	
	var minimap = Minimap.new()
	root_ctrl.add_child(minimap)
	
	print("Minimap size: ", minimap.size)
	print("Minimap custom_minimum_size: ", minimap.custom_minimum_size)
	assert(minimap.size.x >= 180.0, "Minimap width should be at least 180px")
	assert(minimap.size.y >= 180.0, "Minimap height should be at least 180px")
	
	# Test toggling maximized
	print("Testing toggle_maximized(true)...")
	minimap.toggle_maximized(true)
	assert(minimap.is_maximized() == true, "Minimap should be maximized")
	
	# Test refresh
	minimap.refresh()
	
	print("Testing toggle_maximized(false)...")
	minimap.toggle_maximized(false)
	assert(minimap.is_maximized() == false, "Minimap should not be maximized")
	
	print("[PASS] Minimap enlargement and full tactical map modal tested successfully!")
	root_ctrl.free()
	quit(0)
