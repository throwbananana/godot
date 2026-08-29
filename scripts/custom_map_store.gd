class_name CustomMapStore
extends RefCounted

## 玩家在关卡编辑器里画的自定义地图, 存档结构跟 GameState 的
## campaign_save.json / daily_challenge_save.json 是同一套 user:// JSON 惯例,
## 但故意不放进 GameState 本体 —— 这些是编辑器产物, 不是某一局战役的进度,
## 不该被 reset_campaign() 清掉, 也不该被 test_persistence_roundtrip.gd 的
## 存档往返检查盯上。
##
## save_path 特意不是 const: tools/test_custom_map_editor.gd 需要在跑测试时
## 把它指到一个临时文件, 跑完再指回来, 绝不能污染玩家真实的 custom_maps.json。

static var save_path: String = "user://custom_maps.json"

static var _cache: Array = []
static var _loaded: bool = false


static func load_all() -> Array:
	if _loaded:
		return _cache
	_loaded = true
	_cache = []
	if not FileAccess.file_exists(save_path):
		return _cache
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return _cache
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		_cache = parsed
	return _cache


static func save_all(entries: Array) -> void:
	_cache = entries
	_loaded = true
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_cache))


## 强制下一次 load_all() 重新读盘, 而不是继续用内存缓存。
## 只有切换 save_path (测试用) 时需要调用。
static func invalidate_cache() -> void:
	_loaded = false
	_cache = []


static func next_id() -> String:
	return "custom_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]


## 按 id 覆盖或新增。entry 至少要有 "id" 字段 (新建时用 next_id() 生成)。
static func upsert(entry: Dictionary) -> void:
	var all := load_all()
	var id = entry.get("id", "")
	for i in range(all.size()):
		if all[i].get("id", "") == id:
			all[i] = entry
			save_all(all)
			return
	all.append(entry)
	save_all(all)


static func delete(id: String) -> void:
	var all := load_all()
	all = all.filter(func(e): return e.get("id", "") != id)
	save_all(all)


static func get_by_id(id: String) -> Dictionary:
	for e in load_all():
		if e.get("id", "") == id:
			return e
	return {}


## 供 MapTemplates.get_layout_for_stage() 在每个池子分支里调用, 拿到"这一档
## 可以出的自定义图"。三个过滤条件对应编辑器里勾的三样东西:
## min_floor、battle_type、act —— 跟内置模板的 TEMPLATE_MIN_FLOOR + 各 actN_pool
## 是同一套分档逻辑, 只是数据来自玩家存档而不是常量数组。
##
## "shop" 是例外: 跟内置的 SHOP_POOL 一样不分 act (商店房不看视觉主题),
## 所以这里不检查 acts 字段, 只看 battle_types 和 min_floor。
static func eligible_layouts(act: int, battle_type: String, floor_idx: int) -> Array:
	var out: Array = []
	for e in load_all():
		var min_floor := int(e.get("min_floor", 0))
		if floor_idx < min_floor:
			continue
		var types: Array = e.get("battle_types", [])
		if not types.has(battle_type):
			continue
		if battle_type != "shop":
			var acts: Array = e.get("acts", [])
			if not acts.has(act):
				continue
		var layout = e.get("layout", [])
		if layout is Array and layout.size() == 13:
			out.append(layout)
	return out
