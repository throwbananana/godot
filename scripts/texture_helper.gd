class_name TextureHelper
extends RefCounted

static var _cache: Dictionary = {}

## 后台预热队列。
##
## 冷加载一张贴图实测 3.2ms (部分带法线图的更贵), 而 get_tex() 是**懒加载**:
## 某个敌人类型、某串特效、某种地形第一次出现在战场上的那一帧, 才去 load()
## 它的 6 帧贴图 —— 一次 6 x 3.2ms ≈ 19ms, 60fps 的帧预算才 16.7ms。表现出来
## 就是"第一次见到某个东西的时候顿一下", 之后再也不顿 (缓存命中只要 0.4us)。
##
## 全量预加载不是选项: 1125 张图按 compress/mode=0 (无损) 解到内存是 RGBA8,
## 256x256 加 mipmap 约 350KB 一张, 全加载接近 390MB。所以这里只做两件事 ——
## 后台线程慢慢加载**一份有界的常用清单**, 且任何时刻只有一个请求在飞,
## 不跟主线程抢 I/O; 没轮到的贴图仍然走原来的懒加载路径, 功能上没有依赖。
static var _warm_queue: Array[String] = []
static var _warm_active: String = ""
static var _warm_done: int = 0

## 把一批路径排进后台预热队列。已经在缓存里的直接跳过。
static func warm_async(paths) -> void:
	for p in paths:
		var s := String(p)
		if not _cache.has(s) and not _warm_queue.has(s):
			_warm_queue.append(s)

## 每帧调一次 (main.gd / title_screen.gd)。队列空时是一次布尔判断, 没有代价。
##
## 同时只保持一个在途请求: 预热是背景工作, 它的目的是消掉战斗中的尖峰,
## 而不是自己变成一个尖峰 —— 一次性扔几百个请求进线程池会把磁盘 I/O 占满,
## 主线程真正等着要用某张图时反而更慢。
static func warm_pump() -> void:
	if _warm_active != "":
		var st := ResourceLoader.load_threaded_get_status(_warm_active)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			# 资源已经进了引擎自己的资源缓存, 这时候再走一遍 get_tex() 很便宜,
			# 顺手把法线图封装和本地缓存也一并做掉。
			get_tex(_warm_active)
			_warm_done += 1
		_warm_active = ""

	while _warm_active == "" and not _warm_queue.is_empty():
		var p: String = _warm_queue.pop_front()
		if _cache.has(p):
			continue
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
			_warm_active = p

static func warm_progress() -> Array:
	return [_warm_done, _warm_queue.size()]

## 本局到目前为止真正被加载过的贴图路径, 交给 TextureWarmStore 存档,
## 下次启动照着它预热。
static func loaded_paths() -> Array:
	return _cache.keys()

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
		# 如果存在对应的相机空间法线贴图 (*_n.png)，自动封装为 CanvasTexture 以支持 2D 动态光照
		if not path.ends_with("_n.png"):
			var dot_idx = path.rfind(".")
			if dot_idx != -1:
				var norm_path = path.left(dot_idx) + "_n" + path.substr(dot_idx)
				if ResourceLoader.exists(norm_path):
					var norm_tex = load(norm_path) as Texture2D
					if norm_tex:
						var canvas_tex = CanvasTexture.new()
						canvas_tex.diffuse_texture = tex
						canvas_tex.normal_texture = norm_tex
						canvas_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
						tex = canvas_tex
		_cache[path] = tex
	return tex
