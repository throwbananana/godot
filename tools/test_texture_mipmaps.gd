extends SceneTree

## 检查所有精灵都带 mipmap。
##
## 这条不是洁癖: 美术按 256x256 渲染, 游戏按 TILE_SCALE = TILE_SIZE / 256.0
## = 0.1875 绘制, 也就是 5.33 倍缩小。project.godot 里
## textures/canvas_textures/default_texture_filter=3 (Linear Mipmap) 就是
## 冲着这个比例设的 —— 但**没有 mipmap 的纹理在这个 filter 下只会退回双线性**,
## 5.33 倍缩小时采样点跨过五六个纹素, 画面一动就爬行锯齿, 而不是像素风该有的
## 硬边块。
##
## 历史上这里出过一次"看起来有保障、其实空转"的事故: TextureHelper.get_tex()
## 写了 Image.load_from_file() + generate_mipmaps() 作兜底, 但那条分支只在
## ResourceLoader.exists() 为假时才走; 而 .import 文件一旦入库, load() 必然
## 成功, 兜底永远不触发。于是 453 个 .import 全是 mipmaps/generate=false,
## 整条管线赖以成立的 mipmap 保证一个都不存在, 却没有任何东西会报错。
##
## 顺带守住 filter 设置: 只要有一头改了 (关掉 mipmap, 或把 filter 调回
## 非 mipmap 档), 这个测试就会红。

const SPRITE_ROOT := "res://assets/sprites"

var checked: int = 0
var missing: Array[String] = []


func _init() -> void:
	print("==================================================")
	print(">>> TEXTURE MIPMAP TEST <<<")
	print("==================================================")

	var filter: int = int(ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", 0))
	# 3 = Linear Mipmap, 4 = Nearest Mipmap, 5/6 = 各向异性 mipmap 档
	if filter < 3:
		print("  [FAIL] default_texture_filter=%d 不是 mipmap 档, mipmap 生成了也用不上" % filter)
		quit(1)
		return
	print("  default_texture_filter=%d (mipmap 档) ✓" % filter)

	_scan(SPRITE_ROOT)

	print("--------------------------------------------------")
	print("  检查了 %d 张贴图" % checked)
	if missing.is_empty():
		print("🎉 全部带 mipmap")
		quit(0)
		return
	print("  [FAIL] %d 张缺 mipmap:" % missing.size())
	for m in missing.slice(0, 20):
		print("    - %s" % m)
	if missing.size() > 20:
		print("    ... 另有 %d 张" % (missing.size() - 20))
	print("❌ 修法: 把对应 .import 里的 mipmaps/generate 置为 true, 再跑")
	print("   godot --headless --path . --import")
	quit(1)


func _scan(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if not d:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan(full)
		elif name.ends_with(".png"):
			_check(full)
		name = d.get_next()
	d.list_dir_end()


func _check(path: String) -> void:
	var tex := load(path) as Texture2D
	if not tex:
		tex = TextureHelper.get_tex(path)
	if not tex:
		missing.append("%s (加载失败)" % path)
		return
	checked += 1
	var img := tex.get_image()
	if img == null or not img.has_mipmaps():
		missing.append(path)
