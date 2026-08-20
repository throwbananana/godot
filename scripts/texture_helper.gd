class_name TextureHelper
extends RefCounted

static var _cache: Dictionary = {}

static func get_tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	
	if not tex:
		var global_p = ProjectSettings.globalize_path(path)
		var img = Image.load_from_file(global_p)
		if img:
			# 256px 的渲染稿在 48px 网格上是 5.33 倍缩小。没有 mipmap 的话
			# 采样会直接丢像素产生锯齿和爬行, 配合 project.godot 里的
			# Linear Mipmap 过滤才能把黏土表面缩干净。
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	
	if tex:
		_cache[path] = tex
	return tex
