extends SceneTree

func _init() -> void:
	var paths = [
		"res://assets/sprites/tanks/tank_engineer_f0.png",
		"res://assets/sprites/tanks/tank_engineer_f1.png",
		"res://assets/sprites/tanks/tank_engineer_f2.png",
		"res://assets/sprites/tanks/tank_engineer_f3.png",
		"res://assets/sprites/tanks/tank_engineer_f4.png",
		"res://assets/sprites/tanks/tank_engineer_f5.png",
		"res://assets/sprites/tanks/enemy_engineer_f0.png",
		"res://assets/sprites/tanks/enemy_engineer_f1.png",
		"res://assets/sprites/tanks/enemy_engineer_f2.png",
		"res://assets/sprites/tanks/enemy_engineer_f3.png",
		"res://assets/sprites/tanks/enemy_engineer_f4.png",
		"res://assets/sprites/tanks/enemy_engineer_f5.png",
		"res://assets/sprites/tanks/tank_engineer.png"
	]
	for p in paths:
		var t = ResourceLoader.load(p)
		print("Loaded: ", p, " -> ", t)
	quit(0)
