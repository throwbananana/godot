class_name TextureWarmStore
extends RefCounted

## 贴图预热清单 —— 记录"上一局实际用到了哪些贴图", 下次启动在后台提前加载。
##
## 为什么不是一张写死的清单: 贴图冷加载 3.2ms 一张, 而 TextureHelper.get_tex()
## 是懒加载, 于是某类敌人/某串特效第一次出场的那一帧要一口气 load 6 张 ≈ 19ms,
## 直接掉帧。想提前加载就得知道"要加载哪些", 而手写清单一定会烂 —— 新加一种
## 敌人、一串特效、一块地形, 没人会记得回来补这张表, 漏了也不报错, 只是那个
## 东西第一次出现时卡一下。所以清单由**上一局的真实使用记录**生成, 自动跟着
## 内容走。
##
## 全量预加载不是选项: 1125 张图无损导入 (compress/mode=0), 解到内存是 RGBA8
## 加 mipmap 约 350KB 一张, 全部加载接近 390MB。按实际使用记录预热, 占用的
## 就是这一局本来也会占的那些, 不多花一分内存 —— 只是把加载时机从"战斗中途"
## 挪到"标题界面和过场"。
##
## 按 CLAUDE.md "两个状态层" 的分层规则, 这属于第三层 (装机级产物, 不是本局
## 进度): 自己的 user:// JSON, 不进 GameState, 不参与 reset_campaign(), 也不
## 进 test_persistence_roundtrip.gd 的往返契约。save_path 故意是非 const 的
## static var, 好让测试把它指到临时文件, 不会去动玩家真正的清单。
static var save_path: String = "user://texture_warm_list.json"

## 清单上限。预热本身是加速手段, 不该变成内存负担; 真实一局大约用到 200-400 张。
const MAX_ENTRIES: int = 700

static func load_list() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(save_path):
		return out
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return out
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY:
		return out
	for p in parsed:
		if typeof(p) == TYPE_STRING:
			out.append(p)
	return out

static func save_list(paths) -> void:
	var trimmed: Array[String] = []
	for p in paths:
		trimmed.append(String(p))
		if trimmed.size() >= MAX_ENTRIES:
			break
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(trimmed))
	f.close()
