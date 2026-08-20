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
			tex = ImageTexture.create_from_image(img)
	
	if tex:
		_cache[path] = tex
	return tex
