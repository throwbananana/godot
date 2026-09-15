extends SceneTree

const Bullet = preload("res://scripts/bullet.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")

func _init() -> void:
	print("Instantiating bullet.tscn...")
	var bullet_scene = load("res://scenes/bullet.tscn")
	var b_std = bullet_scene.instantiate() as Bullet
	root.add_child(b_std)
	print("Bullet sprite in node: ", b_std.get_node("Sprite2D"))
	print("Bullet @onready sprite: ", b_std.sprite)
	if b_std.sprite:
		print("Sprite texture: ", b_std.sprite.texture)
	b_std.free()
	quit(0)
