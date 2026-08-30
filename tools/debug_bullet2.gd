extends SceneTree

const Bullet = preload("res://scripts/bullet.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")

func _init() -> void:
	var bullet_scene = load("res://scenes/bullet.tscn")
	var b_std = bullet_scene.instantiate() as Bullet
	root.add_child(b_std)
	b_std._ready()
	print("b_std.sprite: ", b_std.sprite)
	if b_std.sprite:
		print("b_std.sprite.texture: ", b_std.sprite.texture)
	b_std.free()
	quit(0)
